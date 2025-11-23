import UIKit
import GoogleMobileAds

final class AdsManager: NSObject, FullScreenContentDelegate {
  static let shared = AdsManager()

  private var interstitial: InterstitialAd?
  private var isLoading = false
  private var onDismiss: (() -> Void)?   // 閉じた後のコールバック

  private var ready: Bool {
    (UIApplication.shared.delegate as? AppDelegate)?.adsReady == true
  }

  // ★ 実際のユニットIDに置き換え済み
  func preloadInterstitial(adUnitID: String = "ca-app-pub-3517487281025314/9240004961") {
    guard ready, !isLoading, interstitial == nil else { return }
    isLoading = true

    // v12: withAdUnitID
      InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
      guard let self = self else { return }
      self.isLoading = false
      if let error = error {
        print("[Ads] Interstitial load failed:", error.localizedDescription)
        return
      }
      self.interstitial = ad
      print("[Ads] Interstitial loaded")
    }
  }

  // 呼び出し元VCを指定して表示
  func showInterstitialIfReady(from vc: UIViewController, onDismiss: (() -> Void)? = nil) {
    guard let ad = interstitial else { print("[Ads] Interstitial not ready"); return }
    self.onDismiss = onDismiss
    ad.fullScreenContentDelegate = self
    ad.present(from: vc)
  }

  // 最前面VCを自動取得して表示（WebView等から使う）
  func showInterstitialFromTopMost(onDismiss: (() -> Void)? = nil) {
    guard let vc = Self.topMostViewController() else {
      print("[Ads] No top-most viewController to present from")
      return
    }
    showInterstitialIfReady(from: vc, onDismiss: onDismiss)
  }

  // MARK: - FullScreenContentDelegate
  func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
    interstitial = nil
    let cb = onDismiss; onDismiss = nil
    preloadInterstitial() // 次回に備えて
    cb?()
  }

  func ad(_ ad: any FullScreenPresentingAd,
          didFailToPresentFullScreenContentWithError error: Error) {
    interstitial = nil
    let cb = onDismiss; onDismiss = nil
    print("[Ads] Interstitial present failed:", error.localizedDescription)
    cb?()
  }
}

// MARK: - Top-most VC
private extension AdsManager {
  static func topMostViewController(base: UIViewController? = {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
    return window?.rootViewController
  }()) -> UIViewController? {
    if let nav = base as? UINavigationController {
      return topMostViewController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topMostViewController(base: tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topMostViewController(base: presented)
    }
    return base
  }

  static func topMostViewController() -> UIViewController? {
    topMostViewController(base: nil)
  }
}
