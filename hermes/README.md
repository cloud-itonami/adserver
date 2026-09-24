# hermes/ — the resident bots that act for this repository

This directory is the **source of truth** for the Hermes profiles listed below
(ADR-2609241200). The host's `~/.hermes/profiles/<profile>` is materialized
from `hermes/profiles/<profile>/` and checked against it:

```
kbb --backend sci scripts/hermes-profile-repo.cljk materialize <profile>   # repo -> host
kbb --backend sci scripts/hermes-profile-repo.cljk check <profile>         # 0 agree / 1 drift / 2 could not compare
kbb --backend sci scripts/hermes-profile-repo.cljk export <profile>        # host -> repo, then commit
```

(run from the com-junkawasaki/root superproject; registry
`manifest/hermes-profile-repos.edn`.)

Each profile directory holds SOUL.md, profile.yaml, config.yaml (host-local
blocks removed), cron/jobs.json (definitions only), scripts/ and the skills the
profile owns. **Never here:** `.env` or any secret value, workspace/ledgers,
sessions, memories, logs, caches, run state.

## Profiles

| profile | description |
|---|---|
| `adnetwork-scout` | adnetwork 広告主情報を収集して Cloudflare R2 data catalog (Iceberg) に保存する bot |
| `adsk` | adsk: adult ad-creative generation bot using murakumo.cloud image/video |
| `adska` | adska: adult ad-operations bot. Campaign plans, budgets, placement compliance, |
| `murakumo-adnetwork` | murakumo.cloud ad network surface driver: measure the first-party ad network (adnet auction, /advertise intake, ads MCP, ad-funded free lane, x402 SDK) and prop |
