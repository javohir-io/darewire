# Game rules (published to players, enforced by the engine)

## Roles
* **Player**: one at a time. Performs the dares.
* **Watcher**: votes on dares and twists, judges attempts, chats, reacts, can queue for the stage.
* **Host**: created the session; can start runs, hand off the stage and end the session.
* **Moderator**: out-of-band role; can observe, cut the stream, remove people, end any session.

## Phases and clocks (defaults)

| Phase | Who acts | Ends when | Default |
|---|---|---|---|
| LOBBY | Host/Player starts | Start | none |
| READY_CHECK | Player confirms boundaries | Ready, or timeout → LOBBY | 60 s |
| CHALLENGE_GENERATION | server | options published; one fallback retry; then → LOBBY | 20 s + 10 s |
| CHALLENGE_VOTE | Watchers | timer, or every online watcher voted (after 5 s) | 20 s |
| PLAYER_REVIEW | Player accepts / passes | accept; pass → new generation; no answer = automatic pass | 20 s |
| LIVE_ROUND | Player | the dare's duration, or Player taps Finish | 20 to 180 s |
| SUBMISSION | Player adds a note | submit or timeout | 15 s |
| AUDIENCE_VERDICT | Watchers judge | timer | 15 s |
| ROUND_RESULT | Player/Host: next, hand off, end | action or idle → LOBBY | 45 s |

A huge clock jump never skips a phase: each phase gets its own full window from when it begins.

## Voting
* One vote per watcher per round. Resending the same vote is harmless (idempotent). A different second vote is rejected. Votes cannot be changed.
* The Player cannot vote on their own dare or judge their own attempt.
* A vote that arrives after the deadline is refused even if the server timer has not fired yet.
* **Winner**: most votes. **Tie**: the option whose final vote arrived earliest. **No votes**: the server picks at random and the app says so.
* Leaving after voting does not remove your vote.

## Player protections
* **Pass** is free: new dares, same round, no points lost, streak untouched.
* **Safety Stop** is available from the ready check through submission. It ends the turn immediately: zero points, **streak preserved**, no penalty of any kind.
* Boundaries (excluded categories, excluded themes, difficulty cap) are enforced on the server. Candidates that touch an excluded theme are rejected based on their *text*, not just on how the AI tagged them.
* Stage disconnects get 20 s of grace, then the round ends as *abandoned*, with no penalty.

## Teen sessions (16-17)
A session is a teen session when its host is 16 or 17: only 16-17 year olds can see, join or watch it, and adults cannot. Every Player in it gets a fixed floor on top of their own boundaries: difficulty never above 3, no social-courage dares, no romance or dark-humor themes, and extra word checks on every dare (pressure and humiliation, going public, money, meet-ups, body image). The Player sees these as locked options on the ready screen and cannot remove them. Everything else (free Pass, Safety Stop, block, report) is identical.

## Scoring (computed only on the server)
* **Player, completed:** `100 × difficulty + 25 × min(streak, 4)`. Nobody judged: half. Failed: 0 and streak resets. Safety stop / abandoned / moderated: 0, streak untouched.
* **Watcher:** +10 for taking part in a round's vote (once per round, so forcing passes cannot farm points), +25 if the dare you picked won, +10 if your verdict matched the majority, +10 if your twist vote won.
* Verdict: majority "completed" wins; a tie goes to the Player; no verdicts at all means "unjudged".

## THE TWIST
If enabled and the dare is 40 s or longer, at 40 % of the round three compatible modifiers (from a fixed template list, filtered by the Player's boundaries) open for an 8 s vote. The winner is applied; no votes means no twist. The twist never changes the round clock.

## Moderation
A moderator action wins over everything. *Cut stream* ends the attempt as `moderated` (no penalty to anyone), removes the Player from the LiveKit room and blocks continuing until the stage is handed to someone else. *Kick* bans the user from that session.
