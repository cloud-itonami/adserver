(ns adserver.worker
  "adserver — the deployable ad-server for our first-party ad network
  (ADR-2607093500). The advertising twin of nexus-x402: publishers call /serve
  at each placement, this runs the adnet auction over the campaign registry and
  returns the winning creative (or the x402-promoting house ad); impressions and
  clicks POST to /event and accrue against the advertiser's prepaid USDC
  balance. Advertisers fund campaigns with x402 USDC deposits (verified via
  treasury over a keyless Base RPC) — ad income flows in our own currency.

  Campaign registry is CAMPAIGNS_JSON config (public creative + bid + targeting
  + prepaid balance; no keys). Same invariants as nexus-x402: the pure decision
  is adnet.core/serve + adnet.billing/accrue; the worker only adds HTTP + the
  on-chain top-up verify. cloud-itonami operates campaign lifecycle (create/
  pause) through its governor; here they arrive as config the ops layer manages."
  (:require [clojure.string :as str]
            [goog.object :as gobj]
            [adnet.core :as adnet]
            [adnet.billing :as billing]
            [treasury.core :as treasury]))

(defn- json [body status]
  (js/Response. (js/JSON.stringify (clj->js body))
                #js {:status status
                     :headers #js {"content-type" "application/json; charset=utf-8"
                                   "access-control-allow-origin" "*"
                                   "cache-control" "no-store"}}))

(defn- now-iso [] (.toISOString (js/Date.)))

(defn- campaigns [env]
  (let [raw (gobj/get env "CAMPAIGNS_JSON")]
    (if (and (string? raw) (not= raw ""))
      (try
        ;; keywordize enums the pure core compares (:model :tier :status …)
        (->> (js->clj (js/JSON.parse raw) :keywordize-keys true)
             (map (fn [c]
                    (-> c
                        (update-in [:bid :model] keyword)
                        (update :status keyword)
                        (update-in [:targeting :tier] #(some-> % keyword))
                        (update-in [:targeting :formats] #(when % (set (map keyword %))))
                        (update-in [:targeting :placements] #(when % (set %)))
                        (update-in [:targeting :geo] #(when % (set %)))))))
        (catch :default _ []))
      [])))

;; ── GET /serve?slot=&tier=&format=&geo= ─────────────────────────────

(defn- handle-serve [^js request env]
  (let [url (js/URL. (.-url request))
        p (.-searchParams url)
        placement {:slot (.get p "slot")
                   :tier (some-> (.get p "tier") keyword)
                   :format (some-> (.get p "format") keyword)
                   :geo (.get p "geo")
                   :now (now-iso)}
        decision (adnet/serve (campaigns env) placement)]
    (json {:kind (:kind decision)
           :creative (:creative decision)
           :campaign-id (get-in decision [:campaign :id])
           :placement (:slot placement)} 200)))

;; ── POST /event {campaign-id, kind:impression|click, placement} ─────
;; Accrues the charge against the campaign (pure); persisting the updated
;; campaign + appending the ad-event ledger row is the host's follow-up
;; (KV/D1). For now we return the computed charge + event so the caller/edge
;; analytics can record it; the accrual store is a deploy-time binding.

(defn- handle-event [^js request env]
  (-> (.json request)
      (.then (fn [^js body]
               (let [{:keys [campaign-id kind placement]} (js->clj body :keywordize-keys true)
                     cmp (some #(when (= (:id %) campaign-id) %) (campaigns env))]
                 (if-not cmp
                   (json {:error "unknown campaign"} 404)
                   (let [{:keys [charge-micros event]}
                         (billing/accrue cmp {:kind (keyword kind) :placement placement :at (now-iso)})]
                     (json {:ok true :charge-micros charge-micros :event event} 200))))))
      (.catch (fn [_] (json {:error "bad request"} 400)))))

;; ── POST /topup {advertiser, tx} — verify an x402 USDC deposit ──────
;; An advertiser funds their prepaid balance by sending USDC to the ad-network
;; treasury; this verifies the tx on-chain (keyless Base RPC via treasury) and
;; reports the confirmed amount. Crediting the balance is the host's store step.

(defn- rpc-call [rpc method params]
  (-> (js/fetch rpc #js {:method "POST"
                         :headers #js {"content-type" "application/json"}
                         :body (js/JSON.stringify #js {:jsonrpc "2.0" :id 1 :method method
                                                       :params (clj->js params)})})
      (.then (fn [^js r] (.json r)))
      (.then (fn [^js j] (.-result j)))))

(defn- handle-topup [^js request env]
  (let [treasury-addr (gobj/get env "ADNET_TREASURY_ADDR")]
    (if-not (and (string? treasury-addr) (not= treasury-addr ""))
      (js/Promise.resolve (json {:error "ad network treasury not configured (ADNET_TREASURY_ADDR unset)"} 503))
      (-> (.json request)
          (.then (fn [^js body]
                   (let [{:keys [tx]} (js->clj body :keywordize-keys true)
                         {:keys [rpc usdc]} (treasury/chain-cfg "base")]
                     (-> (js/Promise.all #js [(rpc-call rpc "eth_getTransactionReceipt" [tx])
                                              (rpc-call rpc "eth_blockNumber" [])])
                         (.then (fn [^js results]
                                  (let [receipt (aget results 0)
                                        head (js/parseInt (aget results 1) 16)
                                        onchain (when receipt (treasury/receipt->onchain (js->clj receipt) head usdc))]
                                    (if (and onchain
                                             (= (str/lower-case (:to onchain)) (str/lower-case treasury-addr))
                                             (>= (:confirmations onchain) 3))
                                      (json {:ok true :credited-usdc (:amount onchain) :tx tx} 200)
                                      (json {:ok false :reason "unconfirmed or wrong recipient"} 402)))))))))
          (.catch (fn [_] (json {:error "bad request"} 400)))))))

;; ── catalog / discovery ─────────────────────────────────────────────

(defn- handle-catalog [env]
  (json {:service "adserver"
         :campaigns (count (campaigns env))
         :slots (->> (campaigns env) (mapcat #(get-in % [:targeting :placements])) (remove nil?) distinct vec)
         :billing "USDC on Base via x402 prepaid deposits"} 200))

(defn- fetch-handler [^js request env _ctx]
  (let [p (.-pathname (js/URL. (.-url request)))
        m (.-method request)]
    (cond
      (= m "OPTIONS")
      (js/Promise.resolve (js/Response. nil #js {:status 204
                                                 :headers #js {"access-control-allow-origin" "*"
                                                               "access-control-allow-methods" "GET, POST, OPTIONS"
                                                               "access-control-allow-headers" "content-type"}}))
      (and (= m "GET")  (= p "/serve"))   (js/Promise.resolve (handle-serve request env))
      (and (= m "POST") (= p "/event"))   (handle-event request env)
      (and (= m "POST") (= p "/topup"))   (handle-topup request env)
      (= p "/catalog")                    (js/Promise.resolve (handle-catalog env))
      (= p "/health")                     (js/Promise.resolve (json {:ok true :service "adserver"} 200))
      :else (js/Promise.resolve (json {:service "adserver" :see "/catalog"} 200)))))

(def app (clj->js {:fetch fetch-handler}))
