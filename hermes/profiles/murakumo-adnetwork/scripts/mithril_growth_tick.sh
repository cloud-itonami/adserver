#!/bin/bash
set -euo pipefail

HERMES_HOME=${HERMES_HOME:-$HOME/.hermes}
RUNTIME=${MITHRIL_RUNTIME:-$HERMES_HOME/runtime/mithril}
PROFILE=$HERMES_HOME/profiles/murakumo-adnetwork
STATE="$PROFILE/workspace/mithril-growth"
mkdir -p "$STATE"
raw=$(mktemp)
obs=$(mktemp)
trap 'rm -f "$raw" "$obs"' EXIT

if ! PYTHONPATH="${KOTOBA_HY_DEPS:?Kotoba Hy runtime is required}${PYTHONPATH:+:$PYTHONPATH}" /opt/homebrew/bin/python3 -m hy "$PROFILE/scripts/adnetwork_surface_evidence.hy" >"$raw" 2>&1; then
  printf 'REFUSE\tobserver-failed\tadnetwork evidence probe did not complete\n'
  sed -n '1,20p' "$raw"
  exit 1
fi
if ! grep -q '^MEASURE' "$raw"; then
  printf 'REFUSE\tevidence-floor\tadnetwork probe returned zero MEASURE rows\n'
  exit 1
fi

/opt/homebrew/bin/python3 - "$raw" "$obs" <<'PY'
import datetime, json, pathlib, re, sys
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
values = {}
for line in lines:
    if line.startswith("MEASURE\t"):
        _, key, value = line.split("\t", 2)
        values[key] = value
    elif line.startswith("LEADS rows="):
        match = re.match(r"LEADS rows=(\d+)", line)
        if match:
            values["advertiser_leads"] = int(match.group(1))
        values["lead_networks"] = line[-12000:]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
doc = {
    "id": "murakumo-advertiser-" + now,
    "measured-at": now,
    "summary": "The live Murakumo ad-network evidence probe completed with MEASURE rows.",
    "values": values,
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(doc, ensure_ascii=False))
PY

cd "$RUNTIME"
/opt/homebrew/bin/kbb --backend sci bin/mithril-growth.cljk decide \
  examples/murakumo-advertiser-acquisition.mith "$obs" "$STATE/proposals.jsonl"
