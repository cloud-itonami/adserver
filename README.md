# adserver

**First-party ad-server Worker** for our own ad network — the advertising twin
of `nexus-x402`. Publishers (shinshi / isekai / …) call `/serve` at each
placement; this runs the `kotoba-lang/adnet` auction over the campaign registry
and returns the winning creative, or the **x402-promoting house ad**;
impressions/clicks POST to `/event` and accrue against the advertiser's prepaid
USDC balance. Advertisers fund campaigns with x402 USDC deposits (verified
on-chain via `treasury` over a keyless Base RPC). Ad income flows in our own
currency instead of a third-party network's payout.

Design: superproject ADR-2607093500. The pure decision is `adnet.core/serve` +
`adnet.billing/accrue` (vendored); the worker only adds HTTP + on-chain top-up
verification. `cloud-itonami` operates the campaign lifecycle (create/pause via
its ops-LLM ⊣ CertGovernor loop); campaigns arrive here as `CAMPAIGNS_JSON`.

## Endpoints

```
GET  /serve?slot=&tier=&format=&geo=   → {kind:paid|house, creative, campaign-id}
POST /event {campaign-id, kind, placement}  → {charge-micros, event}
POST /topup {tx}                        → verify an advertiser's USDC deposit on-chain
GET  /catalog                           → campaign count + slots + billing
GET  /health
```

## Campaign registry (`CAMPAIGNS_JSON`, no keys)

```json
[{"id":"cmp-1","advertiser":"did:key:z…",
  "creative":{"type":"image","image-url":"https://…","click-url":"https://…"},
  "bid":{"model":"cpm","usd":"4.00"},
  "targeting":{"tier":"adult","formats":["rectangle"],"placements":["scene-detail"]},
  "budget":{"total-usd":"50.00","spent-micros":0},"status":"active"}]
```

`ADNET_TREASURY_ADDR` (advertiser USDC deposits) via `wrangler secret`.

## Dev

```bash
kbb -M:test   # pure serve/auction/accrual smoke
kbb -M:lint
npm run build      # amu compile --target wasm32-browser worker
npm run deploy     # wrangler deploy
```

Apache-2.0.
