"""Read-only measurements for the murakumo.cloud ad network surfaces."""

(import datetime :as dt)
(import importlib)
(import json)
(import os)
(import sys)
(import urllib.request)

(setv site "https://murakumo.cloud")
(setv repo (os.path.expanduser "~/github/com-junkawasaki"))
(setv ads (os.path.join repo "orgs" "network-awai" "cloud-murakumo"))
(setv adnet (os.path.join repo "orgs" "kotoba-lang" "adnet"))
(setv user-agent "murakumo-adnetwork-bot/1 (evidence collector; contact: owner)")

(defn fetch [path [method "GET"] [body None] [headers None]]
  (setv request (urllib.request.Request (+ site path) :method method :data body))
  (.add_header request "user-agent" user-agent)
  (for [[key value] (.items (or headers {}))]
    (.add_header request key value))
  (with [response (urllib.request.urlopen request :timeout 20)]
    (, response.status (.read response))))

(defn measure [key value]
  (print f"MEASURE\t{key}\t{value}"))

(defn observe-json [path]
  (setv [status body] (fetch path))
  (, status (json.loads body)))

(defn main []
  (print "ADNETWORK_SURFACE_EVIDENCE_V1")
  (print (+ "measured_at=" (dt.datetime.now dt.timezone.utc).isoformat))
  (try
    (setv [status data] (observe-json "/api/v1/ads/placement?id=free-tier"))
    (measure "placement_http" status)
    (measure "placement_kind" (data.get "kind" "?"))
    (measure "placement_id" (data.get "placement" "?"))
    (except [Exception as error] (measure "placement_http" (+ "ERROR:" (type error).__name__))))
  (try
    (setv [status data] (fetch "/mcp" "POST"
      (.encode (json.dumps {"jsonrpc" "2.0" "id" 1 "method" "tools/list"}))
      {"content-type" "application/json" "Accept" "application/json, text/event-stream"}))
    (setv tools (lfor tool (get (get (json.loads data) "result") "tools") (tool.get "name")))
    (measure "mcp_http" status)
    (measure "mcp_tools" (.join "," tools))
    (measure "mcp_tool_count" (len tools))
    (except [Exception as error] (measure "mcp_http" (+ "ERROR:" (type error).__name__))))
  (try
    (setv [status body] (fetch "/advertise"))
    (measure "advertise_http" status)
    (measure "advertise_page_present" (if (in b"Murakumo Ads" body) "yes" "no"))
    (except [Exception as error] (measure "advertise_http" (+ "ERROR:" (type error).__name__))))
  (try
    (setv [status data] (observe-json "/api/v1/free/status"))
    (measure "free_status_http" status)
    (for [key ["advertiserFunded" "fundingSource" "impressionsPerUnit" "available" "dailyUnitCap"]]
      (measure (.replace key "advertiserFunded" "free_advertiser_funded") (data.get key "?")))
    (except [Exception as error] (measure "free_status_http" (+ "ERROR:" (type error).__name__))))
  (try
    (setv [status data] (observe-json "/.well-known/x402"))
    (measure "x402_http" status)
    (measure "x402_resource_count" (len (data.get "resources" [])))
    (measure "x402_versions" (.join "," (lfor version (data.get "versions" []) (str version))))
    (except [Exception as error] (measure "x402_http" (+ "ERROR:" (type error).__name__))))
  (try
    (setv request (urllib.request.Request (+ site "/sdk/x402-agent.mjs") :method "HEAD"))
    (.add_header request "user-agent" user-agent)
    (with [response (urllib.request.urlopen request :timeout 20)]
      (measure "sdk_http" response.status)
      (measure "sdk_len" (.get response.headers "content-length" "?")))
    (except [Exception as error] (measure "sdk_http" (+ "ERROR:" (type error).__name__))))
  (measure "adnet_core_present" (if (os.path.isfile (os.path.join adnet "src" "adnet" "core.cljk")) "yes" "no"))
  (for [filename ["ads.cljk" "ads_http.cljk" "ads_review.cljk" "ads_mcp.cljk" "free_tier.cljk" "free_tier_http.cljk"]]
    (measure (+ "repo_" filename)
             (if (os.path.isfile (os.path.join ads "src" "cloud_murakumo" filename)) "yes" "no")))
  (try
    (setv [_ data] (observe-json "/api/v1/ads/placement?id=go-sidebar"))
    (measure "campaigns_observable" (if (= (data.get "kind") "paid") "paid" "house-only"))
    (except [Exception as error] (measure "campaigns_observable" (+ "ERROR:" (type error).__name__))))
  (try
    (sys.path.insert 0 (os.path.join repo "root" "scripts"))
    (setv connect (getattr (importlib.import_module "datalake_catalog") "connect"))
    (setv table (.load_table (connect) (, "cloud_itonami" "adnetwork_advertiser")))
    (setv arrow (.to_arrow (.scan table)))
    (measure "advertiser_leads_rows" arrow.num_rows)
    (except [Exception as error] (measure "advertiser_leads_rows" (+ "ERROR:" (type error).__name__))))
  0)

(when (= __name__ "__main__") (sys.exit (main)))
