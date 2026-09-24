#!/usr/bin/env python3
"""Decision-free measurements for the murakumo-adnetwork bot.

Measures the LIVE murakumo.cloud ad network surface and the local checkout.
Writes nothing. Output is MEASURE<TAB>key<TAB>value lines so the cron agent
reads facts instead of re-deriving them. On any environment failure it prints
REFUSED and the reason, so the agent reports blindness instead of guessing.

Live surfaces (2026-09-17 first measured):
  GET  /api/v1/ads/placement         placement decision (auction output)
  POST /api/v1/ads/apply             advertiser intake
  POST /mcp                          MCP advertiser intake (tools/list)
  GET  /advertise                    advertiser-facing page
  GET  /api/v1/free/status           ad-funded free lane funding state
  GET  /.well-known/x402             priced endpoint discovery
  HEAD /sdk/x402-agent.mjs           browser-neutral SDK
Repo surfaces:
  orgs/kotoba-lang/adnet             pure auction/billing/entitlement core
  orgs/network-awai/cloud-murakumo   publisher wiring (ads*.cljk, free_tier*)
"""
from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
import urllib.request

SITE = "https://murakumo.cloud"
REPO = "~/github/com-junkawasaki"
ADS = REPO + "/orgs/network-awai/cloud-murakumo"
ADNET = REPO + "/orgs/kotoba-lang/adnet"

UA = "murakumo-adnetwork-bot/1 (evidence collector; contact: owner)"


def fetch(path: str, method: str = "GET", body: bytes | None = None,
          headers: dict | None = None, timeout: int = 20):
    req = urllib.request.Request(SITE + path, method=method, data=body)
    req.add_header("user-agent", UA)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def main() -> int:
    print("ADNETWORK_SURFACE_EVIDENCE_V1")
    print("measured_at=" + dt.datetime.now(dt.timezone.utc).isoformat())

    def m(key: str, value: str) -> None:
        print(f"MEASURE\t{key}\t{value}")

    # --- live placement (auction output; house copy = no paid campaign) ----
    try:
        st, b = fetch("/api/v1/ads/placement?id=free-tier")
        d = json.loads(b)
        m("placement_http", str(st))
        m("placement_kind", d.get("kind", "?"))
        m("placement_id", d.get("placement", "?"))
    except Exception as e:
        m("placement_http", "ERROR:" + type(e).__name__)

    # --- MCP intake is the advertiser integration surface ------------------
    try:
        st, b = fetch("/mcp", "POST",
                      json.dumps({"jsonrpc": "2.0", "id": 1,
                                  "method": "tools/list"}).encode(),
                      {"content-type": "application/json",
                       "Accept": "application/json, text/event-stream"})
        tools = [t.get("name") for t in json.loads(b)["result"]["tools"]]
        m("mcp_http", str(st))
        m("mcp_tools", ",".join(tools))
        m("mcp_tool_count", str(len(tools)))
    except Exception as e:
        m("mcp_http", "ERROR:" + type(e).__name__)

    # --- /advertise page reachable (advertiser funnel entry) ---------------
    try:
        st, b = fetch("/advertise")
        ok = b"Murakumo Ads" in b
        m("advertise_http", str(st))
        m("advertise_page_present", "yes" if ok else "no")
    except Exception as e:
        m("advertise_http", "ERROR:" + type(e).__name__)

    # --- ad-funded free lane: who funds it today ---------------------------
    try:
        st, b = fetch("/api/v1/free/status")
        d = json.loads(b)
        m("free_status_http", str(st))
        m("free_advertiser_funded", str(d.get("advertiserFunded")))
        m("free_funding_source", d.get("fundingSource", "?"))
        m("free_impressions_per_unit", str(d.get("impressionsPerUnit")))
        m("free_available", str(d.get("available")))
        m("free_daily_unit_cap", str(d.get("dailyUnitCap")))
    except Exception as e:
        m("free_status_http", "ERROR:" + type(e).__name__)

    # --- x402 SDK + discovery (integration surface for third-party callers)
    try:
        st, b = fetch("/.well-known/x402")
        d = json.loads(b)
        res = d.get("resources", [])
        m("x402_http", str(st))
        m("x402_resource_count", str(len(res)))
        m("x402_versions", ",".join(str(v) for v in d.get("versions", [])))
    except Exception as e:
        m("x402_http", "ERROR:" + type(e).__name__)
    try:
        req = urllib.request.Request(SITE + "/sdk/x402-agent.mjs", method="HEAD")
        req.add_header("user-agent", UA)
        with urllib.request.urlopen(req, timeout=20) as resp:
            m("sdk_http", str(resp.status))
            m("sdk_len", resp.headers.get("content-length", "?"))
    except Exception as e:
        m("sdk_http", "ERROR:" + type(e).__name__)

    # --- repo: adnet core present, publisher wiring present ----------------
    import os
    adnet_core = ADNET + "/src/adnet/core.cljk"
    m("adnet_core_present", "yes" if os.path.isfile(adnet_core) else "no")
    for f in ["ads.cljk", "ads_http.cljk", "ads_review.cljk", "ads_mcp.cljk",
              "free_tier.cljk", "free_tier_http.cljk"]:
        m("repo_" + f, "yes" if os.path.isfile(ADS + "/src/cloud_murakumo/" + f) else "no")

    # campaigns config: repo docs default = KV ads:campaigns; runtime value is
    # observable only via the auction output (house kind = no campaigns) and
    # free/status. We do not claim the KV value directly.
    campaigns_set = "unmeasured-observable-only"
    try:
        st, b = fetch("/api/v1/ads/placement?id=go-sidebar")
        d = json.loads(b)
        campaigns_set = "paid" if d.get("kind") == "paid" else "house-only"
    except Exception as e:
        campaigns_set = "ERROR:" + type(e).__name__
    m("campaigns_observable", campaigns_set)

    # advertiser leads from the R2 catalog (readback only; adnetwork-scout owns it)
    try:
        py = "/opt/homebrew/bin/python3"
        code = """
import sys, collections
sys.path.insert(0, '__REPO__/scripts')
from datalake_catalog import connect
t = connect().load_table(('cloud_itonami', 'adnetwork_advertiser'))
a = t.scan().to_arrow()
print('LEADS\trows=%d' % a.num_rows)
nets = collections.Counter(r['network'] for r in a.select(['network']).to_pylist())
print('LEADS\tnetworks=%s' % sorted(nets.items())[:40])
""".replace("__REPO__", REPO)
        proc = subprocess.run([py, "-c", code], capture_output=True,
                              text=True, timeout=300)
        out = (proc.stdout + proc.stderr).strip()
        if proc.returncode == 0 and "LEADS" in out:
            for line in out.splitlines():
                if line.startswith("LEADS"):
                    print(line.replace("\t", " "))
        else:
            m("advertiser_leads", "ERROR:" + (out[-120:] or proc.returncode.__str__()))
    except Exception as e:
        m("advertiser_leads", "ERROR:" + type(e).__name__)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never look like a success on an env failure
        print("REFUSED - no evidence was gathered this run.")
        print(type(e).__name__ + ": " + str(e))
        sys.exit(2)
