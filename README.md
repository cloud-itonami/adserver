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
GET  /campaigns                         → the registry itself (public creative + bid + targeting + budget); 503 + count null when CAMPAIGNS_JSON is unreadable
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
npm test           # portable suite on kbb, then the compiled Worker: node test runner + HTTP surface (worker_http_test.cljk)
kbb -M:lint
npm run build      # scripts/cljk-mirror.cljk -> .cljk-build/, then shadow-cljs release worker -> dist/worker.js
npm run deploy     # wrangler deploy -> https://ads.x402.nexus
```

Sources are `.cljk` (ADR-2609111500); shadow-cljs reads the git-ignored mirror
`scripts/cljk-mirror.cljk` derives from `cljk-origin.edn`.

## Live (2026-09-16)

`https://ads.x402.nexus` (network-awai Cloudflare account, zone `x402.nexus`).
`CAMPAIGNS_JSON` is `[]`: **the registry is empty by fact, not by omission** —
no advertiser has funded a campaign. `/serve` therefore answers the house ad,
and `/campaigns` answers `count 0`. The first publisher wired to this host is
murakumo.cloud (`cloud-murakumo.adnetwork`: pulls `/campaigns` into its KV on
a cron, serves from that cache, reports `/api/v1/ads/inventory`).

Apache-2.0.
