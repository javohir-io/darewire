/** Token bucket per key. In-memory: fine for one instance; use Redis only once there are several (see ADR 0003). */
export class RateLimiter {
  private buckets = new Map<string, { tokens: number; at: number }>();
  private capacity: number;
  private perSecond: number;
  private now: () => number;

  constructor(capacity: number, perSecond: number, now: () => number = Date.now) {
    this.capacity = capacity; this.perSecond = perSecond; this.now = now;
  }

  take(key: string, cost = 1): boolean {
    const t = this.now();
    const b = this.buckets.get(key) ?? { tokens: this.capacity, at: t };
    b.tokens = Math.min(this.capacity, b.tokens + ((t - b.at) / 1000) * this.perSecond);
    b.at = t;
    const ok = b.tokens >= cost;
    if (ok) b.tokens -= cost;
    this.buckets.set(key, b);
    if (this.buckets.size > 50_000) this.gc(t);
    return ok;
  }

  private gc(t: number): void { for (const [k, b] of this.buckets) if (t - b.at > 120_000) this.buckets.delete(k); }
}
