# ADR 0004: Gemini over REST, validated twice, reviewed by a second call

**Decision:** call Gemini via `fetch` with `responseSchema`, treat output as untrusted, run deterministic policy, then an independent reviewer call that **fails closed**, then fallbacks. **Why:** no SDK means a smaller supply chain and a trivially fakeable client; deterministic rules give guarantees a model cannot; a second model catches what regex cannot. **Cost:** extra latency and tokens per round (bounded by timeouts and one retry); the fallback library must be maintained and is itself tested against the policy.
