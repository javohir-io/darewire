# Architecture

```
┌────────────────────┐   REST (JWT)    ┌───────────────────────────────────────────────┐
│  Flutter app       │ ──────────────▶ │  Express API   profile · sessions · reports   │
│  Riverpod          │                 │                blocks · moderation · media    │
│  go_router         │   WebSocket     ├───────────────────────────────────────────────┤
│  Custom painters   │ ◀─────────────▶ │  Gateway (ws)  auth in first frame, rev'd     │
│                    │   state + acks  │                snapshots, rate limits         │
│  LiveKit client ◀──┼──── WebRTC ───┐ ├───────────────────────────────────────────────┤
└────────────────────┘               │ │  SessionManager  timers · persistence ·       │
                                     │ │                  broadcast · effects          │
         ┌───────────────────┐       │ │       │ pure calls          │ effects         │
         │ LiveKit Cloud     │◀──────┘ │  ┌────▼─────────┐     ┌─────▼───────┐         │
         │ room dw_<session> │ tokens, │  │ GameSession  │     │ Director    │──▶ Gemini│
         │ cut / demote      │◀────────┤  │ (engine)     │     │ + policy    │  (REST)  │
         └───────────────────┘ admin   │  └──────────────┘     └─────────────┘         │
                                       ├───────────────────────────────────────────────┤
                                       │  Repo: PgRepo (Supabase Postgres) | MemoryRepo│
                                       └───────────────────────────────────────────────┘
```

## Principles

1. **The server is the only authority.** The phone renders a per-user projection of the state (`viewFor`) and sends commands. It never computes a tally, a winner, a timer or a score. Other users' ballots are never in anyone's snapshot.
2. **The engine is pure.** `GameSession` has no I/O. The clock, RNG and id generator are injected, so the state machine is tested without waiting on real time. Side effects (call the AI, cut a stream) come back as `Effect`s for the manager to run.
3. **AI output is untrusted input.** It is validated like a request body from the internet, then validated again by the engine before it can be voted on.
4. **Fail safe.** AI down → approved fallback dares. Reviewer down → no AI dares (fails closed). Player disconnects → grace period then no-penalty abandon. Server restarts → sessions restore from snapshots.
5. **Safety transitions outrank progression.** Safety Stop and moderator actions are accepted in every attempt state and can never be blocked by a vote or timer.

## Realtime model

* One socket per user per session. First frame is `auth`; no token ever appears in a URL.
* Every state push carries a monotonically increasing `rev`. Clients ignore older snapshots.
* **Reconnect = re-auth = fresh snapshot.** There is no event replay to get wrong: the client's state is always replaced by the truth.
* Counter-only changes (votes, presence) are coalesced to one push per 250 ms; phase changes go out immediately.
* Countdowns use the server clock (`serverTime` offset), so changing the phone's clock changes nothing.
* Slow consumers (>1 MB buffered) are dropped instead of growing server memory.

## Persistence

* `sessions.state` holds the engine snapshot (restart recovery); saves are immediate on phase changes and debounced (2 s) for vote noise.
* Each finished round writes `rounds` plus one `votes` row per ballot. `votes` has primary key `(round_id, user_id, kind)`, a database-level guarantee against double voting that does not depend on application code.
* `game_events` is an append-only log of phase-level events. `ai_generations` stores counts and rejection reasons only, no user text.

## Scaling notes (not built, deliberately)

Sessions live in one process; the REST layer is stateless. To go past one instance: shard sessions by id behind sticky routing (or use Redis for ownership leases and pub/sub for broadcast). See ADR 0003.
