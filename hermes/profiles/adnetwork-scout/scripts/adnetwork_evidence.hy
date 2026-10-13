"""Verify catalog access and the target table shape before a write turn."""
(import importlib)
(import os)
(import sys)

(setv REPO (os.path.expanduser (os.environ.get "ADNETWORK_REPO" "~/github/com-junkawasaki")))
(setv NAMESPACE (os.environ.get "ADNETWORK_NAMESPACE" "cloud_itonami"))
(setv TABLE (os.environ.get "ADNETWORK_TABLE" "adnetwork_advertiser"))
(sys.path.insert 0 (os.path.join REPO "root" "scripts"))

(defn refuse [why]
  (print "REFUSED — no evidence was gathered this run.")
  (print why)
  (print)
  (print "Do not write anything. A catalog write built on an unread catalog is a write built on nothing. Report this refusal and stop.")
  (sys.exit 0))

(defn main []
  (try
    (setv connect (getattr (importlib.import_module "datalake_catalog") "connect"))
    (setv catalog (connect))
    (setv namespaces (list (.list_namespaces catalog)))
    (except [error Exception]
      (refuse (+ "catalog probe failed: " (str error)))))
  (print (+ "CATALOG\t" (.join "," (map (fn [item] (get item 0)) namespaces))))
  (when (not-in (tuple [NAMESPACE]) namespaces)
    (print "NAMESPACE\tabsent")
    (refuse (+ "target namespace is absent: " NAMESPACE)))
  (print "NAMESPACE\tpresent")
  (try
    (setv table (.load_table catalog (tuple [NAMESPACE TABLE])))
    (setv arrow (.to_arrow (.scan table)))
    (print (+ "TABLE\t" TABLE "\trows=" (str arrow.num_rows)))
    (print (+ "SCHEMA\t" (.join "," (list arrow.column_names))))
    (except [error Exception]
      (print (+ "TABLE\tabsent\t" (getattr (type error) "__name__")))
      (refuse (+ "table readback failed: " (str error)))))
  0)

(when (= __name__ "__main__")
  (sys.exit (main)))
