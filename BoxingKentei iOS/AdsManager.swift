import UIKit
import GoogleMobileAds
import AppTrackingTransparency    // ← 追加
import AdSupport                 // ← 追加（IDFA参照する可能性に備えて）

final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    private var isLoading = false

    private var ready: Bool {
        (UIApplication.shared.delegate as? AppDelegate)?.adsReady == true
    }

    // 現在のリクエスト（ATT許可ならパーソナライズ、非許可/不許可/制限なら NPA）
    private func currentRequest() -> Request {
        let req = Request()
        let extras = Extras()
        if #available(iOS 14, *) {
            let st = ATTrackingManager.trackingAuthorizationStatus
            // authorized 以外は NPA=1
            extras.additionalParameters = ["npa": (st == .authorized ? "0" : "1")]
        } else {
            // iOS13以下：パーソナライズ可
            extras.additionalParameters = ["npa": "0"]
        }
        req.register(extras)
        return req
    }

    // ATTが未決定なら何もしない（AppDelegateでダイアログ→初期化後に再度呼ばれる想定）
    private var attResolved: Bool {
        if #available(iOS 14, *) { return ATTrackingManager.trackingAuthorizationStatus != .notDetermined }
        return true
    }

    // 公開API: 事前ロード
    func preloadInterstitial() {
        guard !isLoading, interstitial == nil else { return }
        guard ready, attResolved else { return }

        isLoading = true
        InterstitialAd.load(with: "<YOUR_INTERSTITIAL_UNIT_ID>",
                            request: currentRequest()) { [weak self] ad, err in
            guard let self else { return }
            self.isLoading = false
            if let err { print("[Ads] interstitial load error: \(err)"); return }
            self.interstitial = ad
            self.interstitial?.fullScreenContentDelegate = self
            print("[Ads] interstitial loaded")
        }
    }

    // 公開API: 表示
    func showInterstitialFromTopMost() {
        guard let ad = interstitial else { preloadInterstitial(); return }
        guard let top = topMostViewController() else { return }
        ad.present(from: top)
    }

    // 表示完了/失敗後は次をプリロード
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        interstitial = nil
        preloadInterstitial()
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        interstitial = nil
        preloadInterstitial()
    }

    private func topMostViewController(_ base: UIViewController? = UIApplication.shared
        .connectedScenes.compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topMostViewController(nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topMostViewController(tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topMostViewController(presented) }
        return base
    }
}
