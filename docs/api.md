# API

Base URL: `API_URL`. All endpoints except `/health` need `Authorization: Bearer <Supabase access token>`.
Errors are always `{ "error": { "code": "...", "message": "..." } }`.

## REST

| Method & path | Who | Purpose |
|---|---|---|
| `GET /health` | public | liveness |
| `GET /v1/me` | any signed-in | profile + `needs: {age, handle}`. The profile includes `band` (`teen` \| `adult`) and, for teens, `teenFloor` (the content floor the server adds). Same for `PUT /v1/me` and the avatar routes |
| `PUT /v1/me` | any | `{handle?, avatar?, bio?, accent?, boundaries?}` (bio ≤ 120 chars, no links or @handles; accent neon|pink|lime|blue|violet|aqua|coral). Handle `^[a-z0-9_]{3,20}$`; boundaries must leave ≥ 2 categories on |
| `POST /v1/me/age` | any | `{birthDate: "YYYY-MM-DD"}` → profile; 403 `underage` if < 16. **The first answer is final:** later calls ignore the body. An under-age answer is stored (unverified) so it cannot be retried, and verifies itself on the 16th birthday |
| `DELETE /v1/me` | any | deletes profile and (if configured) the Supabase auth user; closes sockets |
| `GET /v1/me/history`, `GET /v1/leaderboard` | adult | recent rounds / 30-day top players (round points plus ledger points) |
| `PUT /v1/me/avatar` | signed-in adult-attested | `{data: <base64>}`, JPEG/PNG/WebP, ≤ 500 KB decoded. The real type is sniffed from the bytes. Sets `avatar` to `/v1/avatars/<id>?v=<version>`. 5 per 10 min |
| `DELETE /v1/me/avatar` | signed-in | removes the photo, resets to built-in `a01` |
| `GET /v1/avatars/:id` | **public** (images cannot send a bearer token) | the photo bytes; locked-down CSP, 1 day cache |
| `GET /v1/me/wallet` | adult | `{balance, completed, activity[], cashOut:{available:false, note}}` |
| `GET /v1/me/quests` | adult | `{day, streak, week[7], quests[{id,title,desc,goal,reward,progress,claimed}]}` (UTC day) |
| `POST /v1/quests/:id/claim` | adult | `{amount}`; 409 `not_done` / `claimed`; idempotent per quest per day |
| `GET /v1/users/search?q=` | adult | up to 12 handle matches (prefix), blocks excluded; 20 per minute |
| `GET /v1/duels` | adult | my duels, newest first, from my point of view (`role`, `other`) |
| `GET /v1/duels/ideas?target=<id>` | adult | library dares that already pass the target's boundaries |
| `POST /v1/duels` | adult | `{targetId, libraryIndex}` or `{targetId, custom:{title,objective,difficulty}}`. Custom text goes through the safety policy and the target's boundaries. Max 5 open, one open duel per pair, 10 per hour |
| `POST /v1/duels/:id/{accept,decline,cancel}` | target / target / challenger | state changes |
| `POST /v1/duels/:id/submit` | target | `{note?, clipId?}`; the clip must be your own posted video |
| `POST /v1/duels/:id/judge` | challenger | `{approve}` → `{duel, paid, capped}` |
| `POST /v1/mod/users/:id/reset-avatar` | moderator | removes a custom photo (audit-logged) |
| `GET /v1/sessions` | adult | public live sessions: `{id, code, title, phase, watchers, player{id,handle,avatar,streak}, dare{title,difficulty,category}, round}`. Powers the Live page |
| `POST /v1/sessions` | adult | `{title, twist?, visibility?, hostPlays?}` → `{id, code}`. 409 `already_hosting` |
| `POST /v1/sessions/join` | adult | `{code}` → `{sessionId}` |
| `POST /v1/sessions/:id/media-token` | session member or moderator | → `{url, token, canPublish}`; **`canPublish` only for the current Player** |
| `GET /v1/users/:id` | adult | public profile: `{profile{handle,avatar,bio,accent,joinedAt,staff}, isMe, iBlocked, stats, badges, recent, clips}`. 404 if they blocked you; clips hidden if you blocked them. Never includes boundaries, birth date or role flags other than `staff` |
| `POST /v1/cipher/chat` | adult | `{messages:[{role:user|cipher,text}], loyalty, tone, hour?, ctx?}` → `{messages, mood, loyaltyDelta, crisis?, offline?}`. Rate-limited (burst 6, then 1 per 4 s). Nothing is stored |
| `GET /v1/feed?sort=hot\|new&page=n` | adult | clips with short-lived signed `videoUrl`; `nextPage` is null at the end |
| `POST/DELETE /v1/clips/:id/like`, `POST /v1/clips/:id/view` | adult | idempotent like; one view per user |
| `POST /v1/clips/:id/publish` | the clip's author | `{caption?}`; the Player's explicit consent to publish |
| `DELETE /v1/clips/:id` | author or moderator | removes the row and the stored file |
| `GET /v1/me/clips` | adult | your clips with status |
| `GET /v1/mod/clips`, `POST /v1/mod/clips/:id/{restore,remove}` | moderator | auto-hidden clips |
| `POST /v1/reports` | adult | `{kind, note?, targetUserId?, sessionId?, clipId?}` (kinds include `inappropriate_avatar`) |
| `GET/POST/DELETE /v1/blocks` | adult | block list |
| `GET /v1/mod/reports`, `GET /v1/mod/sessions` | moderator | queues |
| `POST /v1/mod/reports/:id/resolve` | moderator | `{action: dismiss|warn|kick|suspend_24h|suspend_7d}` |
| `POST /v1/mod/sessions/:id/{end,cut}` | moderator | end session / cut stream |
| `POST /v1/dev/sessions/:id/bots` | host, **dev only** | adds clearly-labelled simulated viewers |

"adult" in the table above means **member**: age verified (16 or over, or a moderator) and a handle chosen.

**Age bands.** Teens (16-17) and adults (18+) are kept apart wherever people can reach each other or see each other's accounts. For a person of the other band, `GET /v1/sessions` omits their sessions, `POST /v1/sessions/join` answers like a wrong code, `GET /v1/users/search` omits them, `GET /v1/users/:id`, `GET /v1/duels/ideas` and `POST /v1/duels` answer 404, the leaderboard and `GET /v1/feed` omit them, and the WebSocket refuses with `not_found`. Moderators and admins see both. Custom duel text (`custom`) is refused (400 `bad_dare`) when either person is a teen. Demo clips (authors without an account) are visible to everyone.

**Demo media (development only, `DEMO_CLIPS`).** `GET /demo/<file>` serves the demo videos and their poster frames from `server/public/demo`. Feed items carry `poster` (an absolute URL, or null for real clips) and, for demo clips, an absolute `videoUrl` built from the host the app used to reach the server.

## WebSocket `/v1/ws`

Client → server (all JSON). First frame must be `auth` within 5 s:

```json
{"type":"auth","data":{"token":"...","sessionId":"...","want":"watcher|player|observer"}}
{"type":"vote:cast","id":"7","data":{"option":2}}
```

Server → client:

```json
{"type":"ready"}
{"type":"session:state","rev":42,"data":{ /* SessionView */ }}
{"type":"ack","id":"7","data":{"ok":true}}            // or {"ok":false,"error":{"code":"already_voted","message":"..."}}
{"type":"error","data":{"code":"age_required"}}       // then the socket closes
```

### Commands

| Type | Allowed for | Phase |
|---|---|---|
| `session:start` | host, Player | LOBBY |
| `player:ready` | Player | READY_CHECK (`boundaries?`, `allowClips?` boolean consent to record this run) |
| `vote:cast {option}` | Watcher | CHALLENGE_VOTE |
| `challenge:accept`, `challenge:pass` | Player | PLAYER_REVIEW |
| `safety:stop` | Player | READY_CHECK … SUBMISSION |
| `attempt:finish`, `attempt:submit {note?}` | Player | LIVE_ROUND / SUBMISSION |
| `twist:vote {option}` | Watcher | LIVE_ROUND, twist open |
| `verdict:cast {completed}` | Watcher | AUDIENCE_VERDICT |
| `round:next`, `session:end` | host, Player | ROUND_RESULT / any |
| `stage:request`, `stage:cancel`, `stage:handoff {userId?}` | Watcher / host, Player | between rounds |
| `chat:send {text}`, `reaction:send {kind}` | member | any (rate-limited; chat 1-140 chars, no links/contact details) |
| `session:leave` | member | any |
| `mod:end`, `mod:cut`, `mod:kick {userId}`, `mod:chat:delete {id}` | moderator | any |

### Pushed events
`clip:ready {id,title,durationMs}` goes only to the Player when a recorded round is waiting for their Post/Discard decision (re-sent on reconnect).
 (for animation and haptics; state still arrives as `session:state`)
`challenge:options`, `vote:locked`, `round:started`, `challenge:passed`, `attempt:submitted`, `verdict:finalized`, `safety:stop`, `twist:open`, `twist:closed`, `stream:cut`, `session:ended`, `round:timer`, `chat:message`, `chat:history`, `chat:deleted`, `reaction`.

### Challenge object (also the Gemini response schema)
```json
{ "id":"uuid", "category":"improvise|create|perform|solve|social_courage", "title":"3-48 chars",
  "objective":"12-220 chars", "durationSeconds":20-180, "difficulty":1-5,
  "completionCriteria":["1-4 items"], "allowedModifiers":["rhyme", "..."],
  "scoringType":"audience_judgment|objective_check", "tags":["themes"],
  "origin":"ai|fallback", "schemaVersion":1 }
```


## Following, chat and activity

All routes need a signed-in member. The age-band rule applies to every one of them: a person of the other band answers exactly like a person who does not exist (404). Blocked people do too.

| Route | Body / notes → result |
|---|---|
| `POST /v1/users/:id/follow` | → `{isFollowing: true, followers, following}`. Notifies the person once. 404 for yourself, the other age band, or a blocked person. Rate limited |
| `DELETE /v1/users/:id/follow` | → `{isFollowing: false, ...}` |
| `GET /v1/users/:id` | now also returns `relation: {followers, following, isFollowing, followsYou, canMessage, messageMode}`; `messageMode` is `chat` (mutual followers), `request` (adults only) or `none` |
| `GET /v1/users/:id/followers`, `/following` | → `{people: [{id, handle, avatar, iFollow, followsYou}]}` (up to 60, same band, not blocked) |
| `GET /v1/people/suggested` | → `{people}`: this month's top players in your band that you do not follow |
| `GET /v1/feed?sort=following` | only clips by people you follow (empty if you follow nobody) |
| `GET /v1/chats` | → `{chats: [{id, person, lastText, lastMine, lastAt, unread, status, incomingRequest, outgoingRequest}]}`; empty and declined conversations are not listed |
| `POST /v1/chats` | `{userId}` → `{id, status}`. Teens need a mutual follow (403 `chat_not_allowed`). Adults who are not mutual get a `request` conversation |
| `GET /v1/chats/:id` | → the thread: `{person, status, canSend, sendBlockedReason, teen, messages[]}`. Marks it read |
| `POST /v1/chats/:id/messages` | `{text}` (up to 500 characters) → the message. 400 `message_blocked` if it breaks the filter; 403 `cannot_send` with the reason (waiting for acceptance, no longer mutual, closed). Rate limited |
| `POST /v1/chats/:id/accept`, `/decline` | only the person who received the request |
| `GET /v1/activity` | → `{items: [{kind: follow\|like\|message_request\|request_accepted, actor, ref, at, read, iFollowActor}], unread}` |
| `POST /v1/activity/read` | marks all read (204) |
| `GET /v1/badges` | → `{activity, chats}` for the red dots |
| `GET /v1/blocks` | now also returns `people: [{id, handle, avatar}]` |
| `POST /v1/reports` | accepts `conversationId`: the last six messages are attached to the report note for moderators (only if the reporter is in that chat) |
| `POST /v1/blocks` | now also removes following in both directions |

**Chat rules** (`server/src/social/graph.ts`): same band and not blocked; teens only between mutual followers, re-checked on every send (unfollowing closes the chat to new messages); adults get one request message until the other person accepts. **Message filter** (`chat-policy.ts`): for everyone, no links, emails, phone numbers, @handles or explicit/threatening content; for teens also no personal questions, meet-up talk, other-app names or "keep it secret".
