import type { Boundaries } from '../policy/types.ts';
import type { EngineEvent, EngineState, RoundResult, Round } from '../engine/index.ts';
import type { GenerationReport } from '../director/director.ts';

export type UserRole = 'user' | 'moderator' | 'admin';

export interface Profile {
  id: string;
  handle: string | null;
  avatar: string;
  birthDate: string | null;
  ageVerifiedAt: string | null;
  role: UserRole;
  boundaries: Boundaries;
  bio: string;
  accent: string;
  suspendedUntil: string | null;
  createdAt: string;
}

/** `points` is the total earned: round points plus the points ledger (duels, quests). */
export interface UserStats { rounds: number; completed: number; points: number; bestStreak: number; clips: number; likes: number; duels: number }

export interface Report {
  id: string; reporterId: string | null; targetUserId: string | null; sessionId: string | null;
  kind: string; note: string; status: 'open' | 'resolved'; resolution: string | null; createdAt: string; clipId?: string | null;
}

export type ClipStatus = 'awaiting' | 'published' | 'hidden' | 'removed';

export interface Clip {
  id: string; sessionId: string | null; roundNo: number | null;
  authorId: string; authorHandle: string; authorAvatar: string;
  title: string; caption: string; category: string; difficulty: number; twist: string | null; durationMs: number;
  storagePath: string; status: ClipStatus; likes: number; views: number;
  createdAt: string; publishedAt: string | null;
}
export type NewClip = Pick<Clip, 'authorId' | 'authorHandle' | 'authorAvatar' | 'title' | 'category' | 'difficulty' | 'durationMs' | 'storagePath'>
  & Partial<Pick<Clip, 'sessionId' | 'roundNo' | 'twist' | 'caption' | 'status'>>;
export interface FeedQuery { viewerId: string; sort: 'hot' | 'new'; page: number; limit: number; blocked: string[]; /** Only clips by these authors (the "Following" feed). */ onlyAuthors?: string[] }

// ---- follows, chat and activity ----
export interface Conversation {
  id: string; userA: string; userB: string;   // userA < userB always, so a pair has exactly one conversation
  initiatorId: string;
  /** active = both can write; request = the first message is waiting for the other person to accept; declined = closed. */
  status: 'active' | 'request' | 'declined';
  createdAt: string; updatedAt: string; lastReadA: string | null; lastReadB: string | null;
}
export interface ChatMessage { id: string; conversationId: string; senderId: string; text: string; createdAt: string }
export type NotificationKind = 'follow' | 'like' | 'message_request' | 'request_accepted';
export interface Notification { id: string; userId: string; kind: NotificationKind; actorId: string; ref: string | null; createdAt: string; readAt: string | null }
export const pairOf = (a: string, b: string): [string, string] => (a < b ? [a, b] : [b, a]);
export type FeedRow = Clip & { liked: boolean };

export interface LeaderRow { userId: string; handle: string; avatar: string; points: number; completed: number }

// ---- duels, points ledger, user search -------------------------------------------------------------------------

export type DuelStatus = 'pending' | 'accepted' | 'submitted' | 'completed' | 'rejected' | 'declined' | 'cancelled' | 'expired';
export const OPEN_DUEL: readonly DuelStatus[] = ['pending', 'accepted', 'submitted'];

/** One player challenging another to do one dare. Points are minted by the system on approval; players never wager points. */
export interface Duel {
  id: string;
  challengerId: string; challengerHandle: string; challengerAvatar: string;
  targetId: string; targetHandle: string; targetAvatar: string;
  title: string; objective: string; category: string; difficulty: number; durationSeconds: number; criteria: string[];
  origin: 'library' | 'custom';
  status: DuelStatus;
  note: string; proofClipId: string | null;
  reward: number;      // points offered to the target
  rewarded: number;    // points actually paid to the target (after caps)
  createdAt: string; updatedAt: string; expiresAt: string; resolvedAt: string | null;
}

export type LedgerKind = 'duel_win' | 'duel_bonus' | 'quest' | 'bonus';
export interface LedgerEntry { id: string; userId: string; amount: number; kind: LedgerKind; ref: string; key: string; note: string; createdAt: string }
export type NewLedgerEntry = Pick<LedgerEntry, 'userId' | 'amount' | 'kind' | 'ref' | 'key' | 'note'>;
export interface HandleHit { id: string; handle: string; avatar: string }

/** Persistence boundary. Two implementations: PgRepo (Supabase Postgres) and MemoryRepo (dev and tests). */
export interface Repo {
  getProfile(id: string): Promise<Profile | null>;
  ensureProfile(id: string): Promise<Profile>;
  updateProfile(id: string, patch: Partial<Pick<Profile, 'handle' | 'avatar' | 'boundaries' | 'bio' | 'accent'>>): Promise<Profile>;
  userStats(userId: string): Promise<UserStats>;
  clipsByAuthor(authorId: string, limit: number): Promise<Clip[]>;
  /** Records the date of birth. `verified` = old enough to use the app (16+); an under-age answer is stored unverified so it cannot be retried. */
  setAge(id: string, birthDate: string, verified?: boolean): Promise<Profile>;
  setRole(id: string, role: UserRole): Promise<void>;
  suspend(id: string, until: string | null): Promise<void>;
  deleteUser(id: string): Promise<void>;
  searchHandles(prefix: string, limit: number, excludeIds: string[]): Promise<HandleHit[]>;

  // custom (gallery) avatars
  setAvatarBlob(userId: string, mime: string, data: Buffer): Promise<number>;
  getAvatarBlob(userId: string): Promise<{ mime: string; data: Buffer; version: number } | null>;
  clearAvatarBlob(userId: string): Promise<void>;

  // duels and the points ledger
  createDuel(d: Duel): Promise<Duel>;
  getDuel(id: string): Promise<Duel | null>;
  saveDuel(d: Duel): Promise<void>;
  listDuels(userId: string, limit: number): Promise<Duel[]>;
  addPoints(e: NewLedgerEntry): Promise<LedgerEntry | null>;   // null when this key was already used (idempotent)
  ledger(userId: string, limit: number): Promise<LedgerEntry[]>;
  ledgerSince(userId: string, kinds: LedgerKind[], sinceIso: string): Promise<number>;

  saveSession(state: EngineState, visibility: 'public' | 'private'): Promise<void>;
  loadActiveSessions(): Promise<{ state: EngineState; visibility: 'public' | 'private' }[]>;
  appendEvents(sessionId: string, events: EngineEvent[]): Promise<void>;
  saveRound(sessionId: string, round: Round, result: RoundResult): Promise<void>;
  saveGeneration(sessionId: string, roundNo: number, report: GenerationReport): Promise<void>;
  history(userId: string, limit: number): Promise<RoundResult[]>;
  leaderboard(limit: number): Promise<LeaderRow[]>;

  createReport(r: { reporterId: string; targetUserId?: string; sessionId?: string; clipId?: string; kind: string; note: string }): Promise<Report>;
  clipReporterCount(clipId: string): Promise<number>;
  listReports(status: 'open' | 'resolved'): Promise<Report[]>;
  resolveReport(id: string, moderatorId: string, action: string, note: string): Promise<Report | null>;
  // clips and feed
  createClip(c: NewClip): Promise<Clip>;
  getClip(id: string): Promise<Clip | null>;
  publishClip(id: string, authorId: string, caption: string): Promise<Clip | null>;
  setClipStatus(id: string, status: ClipStatus): Promise<void>;
  deleteClip(id: string): Promise<Clip | null>;
  listFeed(q: FeedQuery): Promise<FeedRow[]>;
  setLike(clipId: string, userId: string, on: boolean): Promise<{ likes: number; liked: boolean } | null>;
  recordView(clipId: string, userId: string): Promise<void>;
  myClips(userId: string): Promise<Clip[]>;
  clipsByStatus(status: ClipStatus): Promise<Clip[]>;
  expireAwaiting(olderThanMs: number): Promise<Clip[]>;

  // follows
  addFollow(follower: string, followee: string): Promise<boolean>;      // true when it is new
  removeFollow(follower: string, followee: string): Promise<void>;
  isFollowing(follower: string, followee: string): Promise<boolean>;
  followCounts(userId: string): Promise<{ followers: number; following: number }>;
  followerIds(userId: string, limit: number): Promise<string[]>;        // newest first
  followingIds(userId: string, limit: number): Promise<string[]>;
  // chat
  findConversation(a: string, b: string): Promise<Conversation | null>;
  getConversation(id: string): Promise<Conversation | null>;
  createConversation(a: string, b: string, initiatorId: string, status: Conversation['status']): Promise<Conversation>;
  setConversationStatus(id: string, status: Conversation['status']): Promise<void>;
  listConversations(userId: string, limit: number): Promise<Conversation[]>;   // most recently active first
  addMessage(conversationId: string, senderId: string, text: string): Promise<ChatMessage>;
  listMessages(conversationId: string, limit: number): Promise<ChatMessage[]>; // the latest `limit`, oldest first
  lastMessage(conversationId: string): Promise<ChatMessage | null>;
  messageCountBy(conversationId: string, senderId: string): Promise<number>;
  markRead(conversationId: string, userId: string): Promise<void>;
  unreadCount(conversationId: string, userId: string): Promise<number>;
  // activity
  addNotification(n: { userId: string; kind: NotificationKind; actorId: string; ref?: string | null }): Promise<void>;   // de-duplicated per (user, kind, actor, ref)
  listNotifications(userId: string, limit: number): Promise<Notification[]>;
  markNotificationsRead(userId: string): Promise<void>;
  unreadNotificationCount(userId: string): Promise<number>;

  addBlock(blocker: string, blocked: string): Promise<void>;
  removeBlock(blocker: string, blocked: string): Promise<void>;
  blockedIds(userId: string): Promise<string[]>;
  blockedEitherWay(a: string, b: string): Promise<boolean>;
  logModeration(a: { moderatorId: string; action: string; targetUserId?: string; sessionId?: string; reportId?: string; note?: string }): Promise<void>;
}
