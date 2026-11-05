# 5-minute demo script

1. **Open** (20 s): splash with the liquid wordmark. "Live dares for ages 16 and up. The crowd chooses, the Player decides." Then swipe the Dares feed: the five demo clips (dinosaur costume, karaoke, a surprise splash, a fountain walk, a slackline) autoplay with their poster frames.
2. **Start a session** with two phones, or one phone plus `POST /v1/dev/sessions/:id/bots` for a labelled simulated audience. Show the join code.
3. **Boundaries** (30 s): exclude *Singing* and *Perform*, difficulty 3. "Enforced on the server from the text of every dare, not from the AI's tags."
4. **Generation** (30 s): five wires shimmer. Show the server log line `director ai=… fallback=… rejected=… reviewer=…`. Kill the Gemini key mid-demo: the game keeps going on approved fallbacks.
5. **Vote** (45 s): tap a dare, watch shares fill the wires. Try changing your vote: rejected by the server. `npm run simulate -- 100` in a terminal for the concurrency story, quoting only the numbers it prints.
6. **Accept / pass** (30 s): pass once (free, streak intact), accept the next.
7. **Live round + THE TWIST** (60 s): countdown wire crackles, twist vote opens, winner applied.
8. **Safety Stop** (20 s): hit it. "Zero points, streak preserved, no penalty, available in every attempt state."
9. **Verdict and scores** (30 s): judges vote, server scores, scoreboard.
10. **Engineering close** (60 s): airplane-mode the phone mid-vote → reconnect banner → fresh snapshot, vote intact. Show `npm test` (44 passing), the state machine file and the threat model.

11. **Feed** (60 s): open the Feed tab, swipe through clips, double-tap to like, switch For You / New. Explain consent: opt-in per run, Safety Stop deletes, nothing public until Post.
