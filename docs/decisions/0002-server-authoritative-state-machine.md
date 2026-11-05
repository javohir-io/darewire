# ADR 0002: Server-authoritative, pure state machine

**Decision:** one `GameSession` object per session with injected clock/RNG/ids; commands return results, side effects return as `Effect`s. Clients receive per-user projections with a `rev`. **Why:** votes and safety transitions must be provable; time-dependent logic must be testable in milliseconds. **Deviation from the product brief:** a `PLAYER_REVIEW` state was added between vote and live round, because "Player accepts or passes" needs its own state and timer. Twist is a sub-state of `LIVE_ROUND`, not a phase.
