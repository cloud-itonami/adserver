#!/usr/bin/env python3
"""Measurements for the adnetwork-scout bot.

Same contract as whois_evidence.py. Decision-free: verifies the catalog
token, the target namespace, and the existing advertiser table shape.
REFUSED banner on any failure so the bot is told it is blind, never that
the dataset is complete.
"""
import os
import subprocess
import sys

REPO = os.environ.get(
    "ADNETWORK_REPO",
    os.path.expanduser("~/github/com-junkawasaki"))
NAMESPACE = os.environ.get("ADNETWORK_NAMESPACE", "cloud_itonami")
TABLE = os.environ.get("ADNETWORK_TABLE", "adnetwork_advertiser")


def refuse(why):
    print("REFUSED — no evidence was gathered this run.")
    print(why)
    print()
    print("Do not write anything. A catalog write built on an unread "
          "catalog is a write built on nothing. Report this refusal and stop.")
    sys.exit(0)


def main():
    py = "/opt/homebrew/bin/python3"
    if not os.path.exists(py):
        refuse(f"no python with pyiceberg at {py}")
    code = f"""
import sys
sys.path.insert(0, "{REPO}/scripts")
from datalake_catalog import connect
cat = connect()
ns = [n[0] for n in cat.list_namespaces()]
print("CATALOG\\t" + ",".join(ns))
if "{NAMESPACE}" not in ns:
    print("NAMESPACE\\tabsent")
    sys.exit(0)
print("NAMESPACE\\tpresent")
try:
    tbl = cat.load_table(("{NAMESPACE}", "{TABLE}"))
    sc = tbl.scan().to_arrow()
    print("TABLE\\t{TABLE}\\trows=" + str(sc.num_rows))
    print("SCHEMA\\t" + ",".join(sc.column_names))
except Exception as e:
    print("TABLE\\tabsent\\t" + type(e).__name__)
"""
    proc = subprocess.run([py, "-c", code], capture_output=True, text=True,
                          timeout=300)
    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode != 0:
        refuse(f"catalog probe failed (exit {proc.returncode}):\n"
               + out[-800:])
    if "CATALOG\t" not in out:
        refuse("catalog probe produced no CATALOG line:\n" + out[-400:])
    print(out)
    print()
    print("agent-turn contract: rows= present means readback is possible;")
    print("TABLE absent means create the table with the fixed schema in")
    print("scripts/adnetwork_datalake_sync.py — never invent columns.")


if __name__ == "__main__":
    main()
