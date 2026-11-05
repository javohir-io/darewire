# ADR 0003: Sessions live in one process

**Decision:** keep session state in memory with Postgres snapshots for restart recovery. **Why:** a live game is a tight state machine; distributing it early adds failure modes without adding learning value for the project. **Cost:** one instance per deployment. **Path out:** sticky routing by session id or Redis-based ownership leases and pub/sub; the `Repo` and `Client` interfaces already isolate the seams.
