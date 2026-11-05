# Points and rewards

## What exists today

- **Round points** are earned by a player when a round finishes (the engine scores it).
- **Duel points** are paid by the server when a challenger approves a duel: the challenged player gets `10 + 10 × difficulty` points and the challenger a small bonus (5).
- **Daily quests** (play a round, complete a dare, send a duel, finish a duel) pay a fixed amount once per day each.
- **Balance** = round points + the points ledger. Both show in the app under *Rewards*.

Everything is decided by the server. Every award in the ledger has a unique key (for example `duel:<id>:target`, `quest:play_round:2026-10-30:<user>`), so a retried request cannot pay twice.

## Limits that protect the economy

| Rule | Value |
|---|---|
| Duel earnings per player per UTC day | 150 |
| Challenger bonus per UTC day | 30 |
| Paid duels between the same two people per UTC day | 1 |
| Open duels you can have sent | 5 |
| Duel sends per hour | 10 |
| Duel answer windows | 48 h to answer, 72 h to do it, 48 h to be reviewed, then it expires |

These live in `server/src/social/service.ts` (`RULES`, `QUESTS`) and are covered by tests in `server/test/social.test.ts`.

## Points are NOT money

There is **no cash-out**. The wallet API returns `cashOut.available = false` and the app says so. Nothing in the app promises that points will ever become money.

You mentioned converting points to real money "maybe in the future". Before that is even considered:

1. **Legal and tax.** Paying users for activity is regulated differently per country (gambling, payments, tax reporting, labour rules). Get advice first.
2. **No wagering.** Today players never stake points on each other. Keep it that way: adding stakes to a points balance that can become cash turns a game into gambling in many places.
3. **Fraud.** Duels are agreed between two people, so two accounts can approve each other. The daily caps slow this down, they do not stop it. Cash-out needs real identity verification, device and behaviour checks, a delay before payout and manual review of large balances.
4. **Age and identity.** The current age gate is a self-declared date of birth. Paying out requires verified identity (KYC) and a payment provider. **Teen accounts (16-17) must never be eligible for cash-out or anything with monetary value**, whatever else changes; keep points status-only for them.
5. **Ledger first.** If cash-out is added, add negative ledger entries (`redeem`) rather than editing balances, so the history stays auditable. The ledger table already supports negative amounts.
