#!/usr/bin/env hy
"""Read-only catalog probe for the adnetwork-scout collection job."""
(import json os subprocess sys)

(setv REPO (os.environ.get "ADNETWORK_REPO" (os.path.expanduser "~/github/com-junkawasaki"))
      NAMESPACE (os.environ.get "ADNETWORK_NAMESPACE" "cloud_itonami")
      TABLE (os.environ.get "ADNETWORK_TABLE" "adnetwork_advertiser")
      PYTHON "/opt/homebrew/bin/python3")

(defn refuse [why]
  (print "REFUSED — no evidence was gathered this run.")
  (print why)
  (print)
  (print "Do not write anything. A catalog write built on an unread catalog is a write built on nothing. Report this refusal and stop.")
  (raise (SystemExit 0)))

(defn main []
  (when (not (os.path.exists PYTHON)) (refuse (+ "no python with pyiceberg at " PYTHON)))
  (setv py-script-dir (json.dumps (os.path.join REPO "scripts"))
        namespace (json.dumps NAMESPACE)
        table (json.dumps TABLE)
        code (.format "import json, sys\nsys.path.insert(0, {0})\nfrom datalake_catalog import connect\ncat = connect()\nns = [n[0] for n in cat.list_namespaces()]\nprint('CATALOG\\t' + ','.join(ns))\nif {1} not in ns:\n    print('NAMESPACE\\tabsent')\n    sys.exit(0)\nprint('NAMESPACE\\tpresent')\ntry:\n    tbl = cat.load_table(({1}, {2}))\n    sc = tbl.scan().to_arrow()\n    print('TABLE\\t{2}\\trows=' + str(sc.num_rows))\n    print('SCHEMA\\t' + ','.join(sc.column_names))\nexcept Exception as e:\n    print('TABLE\\tabsent\\t' + type(e).__name__)\n" py-script-dir namespace table)
        proc (subprocess.run [PYTHON "-c" code] :capture_output True :text True :timeout 300)
        output (+ (.strip (.stdout proc)) (if (.strip (.stderr proc)) (+ "\n" (.strip (.stderr proc))) "")))
  (when (!= (.returncode proc) 0)
    (refuse (.format "catalog probe failed (exit {}):\n{}" (.returncode proc) (cut output None -800))))
  (when (not-in "CATALOG\t" output) (refuse (+ "catalog probe produced no CATALOG line:\n" (cut output None -400))))
  (print output)
  (print)
  (print "agent-turn contract: rows= present means readback is possible;")
  (print "TABLE absent means create the table with the fixed schema in")
  (print "scripts/adnetwork_datalake_sync.py — never invent columns."))

(when (= __name__ "__main__") (main))
