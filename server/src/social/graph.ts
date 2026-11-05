// Following, direct messages and the activity feed. Every rule lives here so it can be tested without HTTP.
//
// Who can reach whom (the same age-band rule as everywhere else: teens (16-17) and adults never meet):
//   * follow:   same band, not blocked, not yourself.
//   * message:  same band, not blocked, AND
//                 teens   : only mutual followers ("friends"). If either side unfollows, the chat is closed to new messages.
//                 adults  : mutual followers chat freely; anyone else sends ONE message request that the other person must accept.
import type { Repo, Profile, Conversation, ChatMessage, Notification } from '../store/types.ts';
import { bandOf, sameBand, isStaff } from '../profile/age.ts';
import { moderateMessage } from './chat-policy.ts';
import { SocialError } from './service.ts';

export interface PersonRow { id: string; handle: string; avatar: string; iFollow: boolean; followsYou: boolean }
export interface Relation { followers: number; following: number; isFollowing: boolean; followsYou: boolean; canMessage: boolean; messageMode: 'chat' | 'request' | 'none' }
export interface ChatRow { id: string; person: { id: string; handle: string; avatar: string }; lastText: string | null; lastMine: boolean; lastAt: string; unread: number; status: Conversation['status']; incomingRequest: boolean; outgoingRequest: boolean }
export interface ThreadView { id: string; status: Conversation['status']; person: { id: string; handle: string; avatar: string }; incomingRequest: boolean; canSend: boolean; sendBlockedReason: string | null; messages: { id: string; mine: boolean; text: string; at: string }[]; teen: boolean }
export interface ActivityItem { id: string; kind: Notification['kind']; actor: { id: string; handle: string; avatar: string }; ref: string | null; at: string; read: boolean; iFollowActor: boolean }

const notFound = () => new SocialError(404, 'not_found', 'We could not find that person');

export class GraphService {
  private repo: Repo;
  constructor(repo: Repo) { this.repo = repo; }

  // ---- who can see / reach whom ---------------------------------------------------------------------------------

  /** The other person, if they exist, finished sign-up, are in the viewer's age band and neither has blocked the other. Otherwise 404 (no hints). */
  private async reachable(viewer: Profile, id: string): Promise<Profile> {
    const other = id === viewer.id ? null : await this.repo.getProfile(id);
    if (!other || !other.handle || !(other.ageVerifiedAt || isStaff(other)) || !sameBand(viewer, other) || (await this.repo.blockedEitherWay(viewer.id, other.id))) throw notFound();
    return other;
  }

  private async person(id: string): Promise<{ id: string; handle: string; avatar: string } | null> {
    const p = await this.repo.getProfile(id);
    return p && p.handle ? { id: p.id, handle: p.handle, avatar: p.avatar } : null;
  }

  // ---- follows --------------------------------------------------------------------------------------------------

  async follow(viewer: Profile, targetId: string) {
    await this.reachable(viewer, targetId);
    if (await this.repo.addFollow(viewer.id, targetId)) await this.repo.addNotification({ userId: targetId, kind: 'follow', actorId: viewer.id });
    return { isFollowing: true, ...(await this.repo.followCounts(targetId)) };
  }

  async unfollow(viewer: Profile, targetId: string) {
    await this.repo.removeFollow(viewer.id, targetId);
    return { isFollowing: false, ...(await this.repo.followCounts(targetId)) };
  }

  async relation(viewer: Profile, other: Profile): Promise<Relation> {
    const [counts, isFollowing, followsYou] = await Promise.all([this.repo.followCounts(other.id), this.repo.isFollowing(viewer.id, other.id), this.repo.isFollowing(other.id, viewer.id)]);
    const self = viewer.id === other.id;
    const blocked = !self && (await this.repo.blockedEitherWay(viewer.id, other.id));
    const mutual = isFollowing && followsYou;
    const mode = self || blocked || !sameBand(viewer, other) ? 'none' : mutual ? 'chat' : bandOf(viewer) === 'teen' ? 'none' : 'request';
    return { ...counts, isFollowing, followsYou, canMessage: mode !== 'none', messageMode: mode };
  }

  /** People rows for a list of ids, as the viewer may see them (same band, not blocked). */
  private async people(viewer: Profile, ids: string[], max: number): Promise<PersonRow[]> {
    const out: PersonRow[] = [];
    for (const id of ids) {
      if (out.length >= max) break;
      const p = await this.repo.getProfile(id);
      if (!p || !p.handle || !sameBand(viewer, p) || (await this.repo.blockedEitherWay(viewer.id, id))) continue;
      out.push({ id, handle: p.handle, avatar: p.avatar, iFollow: await this.repo.isFollowing(viewer.id, id), followsYou: await this.repo.isFollowing(id, viewer.id) });
    }
    return out;
  }

  async followers(viewer: Profile, targetId: string) { await this.listable(viewer, targetId); return this.people(viewer, await this.repo.followerIds(targetId, 200), 60); }
  async following(viewer: Profile, targetId: string) { await this.listable(viewer, targetId); return this.people(viewer, await this.repo.followingIds(targetId, 200), 60); }
  private async listable(viewer: Profile, targetId: string) { if (targetId !== viewer.id) await this.reachable(viewer, targetId); }

  /** People worth following: this month's top players in the viewer's band that they do not follow yet. */
  async suggested(viewer: Profile): Promise<PersonRow[]> {
    const rows = await this.repo.leaderboard(120);
    const mine = new Set(await this.repo.followingIds(viewer.id, 1000));
    const ids = rows.map((r) => r.userId).filter((id) => id !== viewer.id && !mine.has(id));
    return this.people(viewer, ids, 20);
  }

  // ---- chat -----------------------------------------------------------------------------------------------------

  private partner(c: Conversation, me: string) { return c.userA === me ? c.userB : c.userA; }

  /** Opens (or creates) the conversation with someone. Teens need a mutual follow; adults may send one request. */
  async openChat(viewer: Profile, targetId: string): Promise<{ id: string; status: Conversation['status'] }> {
    const other = await this.reachable(viewer, targetId);
    const existing = await this.repo.findConversation(viewer.id, other.id);
    const rel = await this.relation(viewer, other);
    if (existing && existing.status !== 'declined') return { id: existing.id, status: existing.status };
    if (rel.messageMode === 'none') throw new SocialError(403, 'chat_not_allowed', bandOf(viewer) === 'teen' ? 'You can chat with people who follow you back' : 'You cannot message this person');
    if (existing) {   // a declined request: only the other person's follow-back reopens it
      if (rel.messageMode !== 'chat') throw new SocialError(403, 'chat_not_allowed', 'This person is not taking messages from you right now');
      await this.repo.setConversationStatus(existing.id, 'active');
      return { id: existing.id, status: 'active' };
    }
    const c = await this.repo.createConversation(viewer.id, other.id, viewer.id, rel.messageMode === 'chat' ? 'active' : 'request');
    return { id: c.id, status: c.status };
  }

  /** The conversation, if the viewer is in it and may still see it (same band, not blocked). Otherwise 404. */
  private async mine(viewer: Profile, id: string): Promise<{ c: Conversation; other: Profile }> {
    const c = await this.repo.getConversation(id);
    if (!c || (c.userA !== viewer.id && c.userB !== viewer.id)) throw notFound();
    const other = await this.repo.getProfile(this.partner(c, viewer.id));
    if (!other || !other.handle || !sameBand(viewer, other) || (await this.repo.blockedEitherWay(viewer.id, other.id))) throw notFound();
    return { c, other };
  }

  async chats(viewer: Profile): Promise<ChatRow[]> {
    const out: ChatRow[] = [];
    for (const c of await this.repo.listConversations(viewer.id, 60)) {
      const otherId = this.partner(c, viewer.id);
      const other = await this.repo.getProfile(otherId);
      if (!other || !other.handle || !sameBand(viewer, other) || (await this.repo.blockedEitherWay(viewer.id, otherId))) continue;
      if (c.status === 'declined') continue;
      const last = await this.repo.lastMessage(c.id);
      if (!last) continue;   // opened but nothing sent yet: nothing to show
      out.push({
        id: c.id, person: { id: other.id, handle: other.handle, avatar: other.avatar }, lastText: last?.text ?? null, lastMine: last?.senderId === viewer.id, lastAt: (last?.createdAt ?? c.updatedAt),
        unread: await this.repo.unreadCount(c.id, viewer.id), status: c.status, incomingRequest: c.status === 'request' && c.initiatorId !== viewer.id, outgoingRequest: c.status === 'request' && c.initiatorId === viewer.id,
      });
    }
    return out;
  }

  async thread(viewer: Profile, id: string): Promise<ThreadView> {
    const { c, other } = await this.mine(viewer, id);
    await this.repo.markRead(c.id, viewer.id);
    const msgs = await this.repo.listMessages(c.id, 100);
    const sendCheck = await this.sendBlock(viewer, c, other);
    return {
      id: c.id, status: c.status, person: { id: other.id, handle: other.handle!, avatar: other.avatar }, incomingRequest: c.status === 'request' && c.initiatorId !== viewer.id,
      canSend: sendCheck === null, sendBlockedReason: sendCheck, teen: bandOf(viewer) === 'teen',
      messages: msgs.map((m: ChatMessage) => ({ id: m.id, mine: m.senderId === viewer.id, text: m.text, at: m.createdAt })),
    };
  }

  /** Why the viewer cannot send right now, or null if they can. */
  private async sendBlock(viewer: Profile, c: Conversation, other: Profile): Promise<string | null> {
    if (c.status === 'declined') return 'This chat is closed';
    if (c.status === 'request') {
      if (c.initiatorId !== viewer.id) return 'Accept this request to reply';
      if ((await this.repo.messageCountBy(c.id, viewer.id)) >= 1) return 'Waiting for them to accept your request';
    }
    if (bandOf(viewer) === 'teen') {
      const mutual = (await this.repo.isFollowing(viewer.id, other.id)) && (await this.repo.isFollowing(other.id, viewer.id));
      if (!mutual) return 'You can only chat with people you both follow';
    }
    return null;
  }

  async send(viewer: Profile, id: string, raw: unknown) {
    const { c, other } = await this.mine(viewer, id);
    const why = await this.sendBlock(viewer, c, other);
    if (why) throw new SocialError(403, 'cannot_send', why);
    const verdict = moderateMessage(raw, bandOf(viewer) === 'teen');
    if (!verdict.ok) throw new SocialError(400, 'message_blocked', verdict.message);
    const first = (await this.repo.messageCountBy(c.id, viewer.id)) === 0;
    const m = await this.repo.addMessage(c.id, viewer.id, verdict.text);
    if (c.status === 'request' && first) await this.repo.addNotification({ userId: other.id, kind: 'message_request', actorId: viewer.id, ref: c.id });
    return { id: m.id, mine: true, text: m.text, at: m.createdAt };
  }

  async respond(viewer: Profile, id: string, accept: boolean) {
    const { c, other } = await this.mine(viewer, id);
    if (c.status !== 'request' || c.initiatorId === viewer.id) throw new SocialError(400, 'no_request', 'There is no request to answer');
    await this.repo.setConversationStatus(c.id, accept ? 'active' : 'declined');
    if (accept) await this.repo.addNotification({ userId: other.id, kind: 'request_accepted', actorId: viewer.id, ref: c.id });
    return { status: accept ? 'active' : 'declined' };
  }

  /** The last few messages, as plain text for a moderator to read when a chat is reported. */
  async transcript(viewer: Profile, id: string): Promise<string | null> {
    const c = await this.repo.getConversation(id);
    if (!c || (c.userA !== viewer.id && c.userB !== viewer.id)) return null;
    const msgs = (await this.repo.listMessages(c.id, 6)).map((m) => `${m.senderId === viewer.id ? 'reporter' : 'other'}: ${m.text}`);
    return msgs.join(' | ');
  }

  // ---- activity -------------------------------------------------------------------------------------------------

  async notify(userId: string, kind: Notification['kind'], actorId: string, ref?: string | null) { await this.repo.addNotification({ userId, kind, actorId, ref }); }

  async activity(viewer: Profile): Promise<{ items: ActivityItem[]; unread: number }> {
    const unread = await this.repo.unreadNotificationCount(viewer.id);
    const items: ActivityItem[] = [];
    for (const n of await this.repo.listNotifications(viewer.id, 50)) {
      const actor = await this.person(n.actorId);
      const prof = actor ? await this.repo.getProfile(n.actorId) : null;
      if (!actor || !prof || !sameBand(viewer, prof) || (await this.repo.blockedEitherWay(viewer.id, n.actorId))) continue;
      items.push({ id: n.id, kind: n.kind, actor, ref: n.ref, at: n.createdAt, read: !!n.readAt, iFollowActor: await this.repo.isFollowing(viewer.id, n.actorId) });
    }
    return { items, unread };
  }

  async markActivityRead(viewer: Profile) { await this.repo.markNotificationsRead(viewer.id); }

  /** Numbers for the badges on Home: unread activity, and chats with something new (plus incoming requests). */
  async badges(viewer: Profile): Promise<{ activity: number; chats: number }> {
    let chats = 0;
    for (const c of await this.repo.listConversations(viewer.id, 60)) {
      if (c.status === 'declined') continue;
      const n = await this.repo.unreadCount(c.id, viewer.id);
      if (n > 0) chats += 1;
    }
    return { activity: await this.repo.unreadNotificationCount(viewer.id), chats };
  }
}
