#!/usr/bin/env python3
"""Outreach evidence for adnetwork-scout: read the collected advertiser leads
from the R2 Data Catalog (readback only; this bot owns the table) and pick a
small candidate set for /advertise outreach proposals. Decision-free: it ranks
by observed recency + completeness and prints MEASURE lines. No send, no write
outside the profile workspace.
"""
from __future__ import annotations
import datetime as dt
import json
import os
import subprocess
import sys

REPO = os.environ.get("ADNETWORK_REPO", "~/github/com-junkawasaki")
WS = os.path.expanduser("~/.hermes/profiles/adnetwork-scout/workspace")

INNER = """
import sys, json, datetime
sys.path.insert(0, '__REPO__/scripts')
from datalake_catalog import connect
t = connect().load_table(('cloud_itonami', 'adnetwork_advertiser'))
a = t.scan().to_arrow().to_pylist()
now = datetime.datetime.now(datetime.timezone.utc)
def score(r):
    s = 0
    if r.get('advertiser_name'): s += 1
    if r.get('notes'): s += 1
    try:
        obs = datetime.datetime.fromisoformat(r.get('observed_at') or '')
        age_days = (now - obs).days
    except Exception:
        age_days = 9999
    s -= age_days * 0.01
    return s
seen = {}
for r in a:
    k = (r.get('network'), r.get('advertiser_key'))
    if k not in seen or score(r) > score(seen[k]):
        seen[k] = r
cands = sorted(seen.values(), key=score, reverse=True)
print('LEADS\tunique=%d' % len(seen))
for r in cands[:10]:
    print('CANDIDATE\t' + json.dumps({
        'network': r.get('network'), 'advertiser_key': r.get('advertiser_key'),
        'advertiser_name': r.get('advertiser_name'), 'evidence_url': r.get('evidence_url'),
        'observed_at': r.get('observed_at'), 'notes': (r.get('notes') or '')[:160]},
        ensure_ascii=False))
""".replace('__REPO__', REPO)


def main() -> int:
    print("ADNETWORK_OUTREACH_EVIDENCE_V1")
    print("measured_at=" + dt.datetime.now(dt.timezone.utc).isoformat())
    py = "/opt/homebrew/bin/python3"
    if not os.path.exists(py):
        print("REFUSED - no /opt/homebrew/bin/python3")
        return 2
    proc = subprocess.run([py, "-c", INNER], capture_output=True, text=True, timeout=300)
    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode != 0 or "LEADS" not in out:
        print("REFUSED - catalog readback failed (exit %s):" % proc.returncode)
        print(out[-500:])
        return 2
    print(out)
    os.makedirs(WS, exist_ok=True)
    with open(os.path.join(WS, "outreach-candidates.jsonl"), "w") as f:
        for line in out.splitlines():
            if line.startswith("CANDIDATE"):
                f.write(line.split("\t", 1)[1] + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
