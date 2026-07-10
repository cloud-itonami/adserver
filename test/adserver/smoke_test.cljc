(ns adserver.smoke-test
  "Smoke test for the adserver wiring — exercises the pure adnet + billing the
  worker composes (serve decision, auction, accrual) without a Worker runtime.
  The impure seams (HTTP, RPC top-up verify) are covered by adnet/treasury's
  own tests."
  (:require [clojure.test :refer [deftest is testing]]
            [adnet.core :as adnet]
            [adnet.billing :as billing]))

(def registry
  [{:id "cmp-1" :advertiser "did:key:zA"
    :creative {:type :image :image-url "https://cdn/ad1.png" :click-url "https://advertiser/x"}
    :bid {:model :cpm :usd "4.00"}
    :targeting {:tier :adult :formats #{:rectangle} :placements #{"scene-detail"}}
    :budget {:total-usd "50.00" :spent-micros 0} :status :active}])

(def placement {:slot "scene-detail" :tier :adult :format :rectangle :geo "JP"
                :now "2026-07-10T12:00:00Z"})

(deftest serve-paid-then-house
  (testing "a matching campaign wins the placement"
    (let [d (adnet/serve registry placement)]
      (is (= :paid (:kind d)))
      (is (= "cmp-1" (:id (:campaign d))))
      (is (= "https://cdn/ad1.png" (:image-url (:creative d))))))
  (testing "house ad backfills when nothing matches (promotes the x402 catalog)"
    (let [d (adnet/serve registry (assoc placement :tier :general))]
      (is (= :house (:kind d)))
      (is (= "https://x402.nexus/catalog" (:click-url (:creative d)))))))

(deftest event-accrual
  (testing "an impression on a CPM campaign accrues bid/1000 and advances budget"
    (let [{:keys [charge-micros campaign event]}
          (billing/accrue (first registry)
                          {:kind :impression :placement "scene-detail" :at "2026-07-10T12:00:00Z"})]
      (is (= 4000 charge-micros))                       ; $4 / 1000
      (is (= 4000 (get-in campaign [:budget :spent-micros])))
      (is (= :impression (:ad/event event))))))
