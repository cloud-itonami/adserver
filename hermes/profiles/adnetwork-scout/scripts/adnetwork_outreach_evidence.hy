"""Read advertiser leads, rank unique candidates, and write a bounded JSONL snapshot."""

(import datetime :as dt)
(import importlib)
(import json)
(import os)
(import sys)

(setv repo (os.path.expanduser (os.environ.get "ADNETWORK_REPO" "~/github/com-junkawasaki")))
(setv workspace (os.path.expanduser "~/.hermes/profiles/adnetwork-scout/workspace"))
(sys.path.insert 0 (os.path.join repo "root" "scripts"))

(defn score [row now]
  (setv completeness (+ (if (row.get "advertiser_name") 1 0)
                         (if (row.get "notes") 1 0)))
  (setv age-days
        (try
          (do
            (setv observed (dt.datetime.fromisoformat (row.get "observed_at" "")))
            (max 0 (// (- now observed).total_seconds 86400)))
          (except [Exception] 9999)))
  (- completeness (* age-days 0.01)))

(defn main []
  (print "ADNETWORK_OUTREACH_EVIDENCE_V1")
  (print (+ "measured_at=" (dt.datetime.now dt.timezone.utc).isoformat))
  (setv result
        (try
          (do
            (setv connect (getattr (importlib.import_module "datalake_catalog") "connect"))
            (setv table (.load_table (connect) (, "cloud_itonami" "adnetwork_advertiser")))
            (setv rows (.to_pylist (.to_arrow (.scan table))))
            (setv now (dt.datetime.now dt.timezone.utc))
            (setv newest {})
            (for [row rows]
              (setv key (, (row.get "network") (row.get "advertiser_key")))
              (when (or (not (in key newest))
                        (> (score row now) (score (get newest key) now)))
                (setv (get newest key) row)))
            (setv candidates (sorted (.values newest) :key (fn [row] (score row now)) :reverse True))
            (print f"LEADS\tunique={(len newest)}")
            (for [row (cut candidates 0 10)]
              (print (+ "CANDIDATE\t"
                        (json.dumps {"network" (row.get "network")
                                    "advertiser_key" (row.get "advertiser_key")
                                    "advertiser_name" (row.get "advertiser_name")
                                    "evidence_url" (row.get "evidence_url")
                                    "observed_at" (row.get "observed_at")
                                    "notes" (cut (row.get "notes" "") 0 160)}
                                   :ensure_ascii False))))
            (os.makedirs workspace :exist_ok True)
            (with [out (open (os.path.join workspace "outreach-candidates.jsonl") "w")]
              (for [row (cut candidates 0 10)]
                (.write out (+ (json.dumps {"network" (row.get "network")
                                            "advertiser_key" (row.get "advertiser_key")
                                            "advertiser_name" (row.get "advertiser_name")
                                            "evidence_url" (row.get "evidence_url")
                                            "observed_at" (row.get "observed_at")
                                            "notes" (cut (row.get "notes" "") 0 160)}
                                           :ensure_ascii False) "\n"))))
            0)
          (except [error Exception]
            (do
              (print (+ "REFUSED - catalog readback failed: " (type error).__name__))
              2))))
  result)

(when (= __name__ "__main__") (sys.exit (main)))
