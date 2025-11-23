import SwiftUI
import UIKit
import GoogleMobileAds

#if canImport(GoogleMobileAds)
@MainActor
private func anchoredAdaptiveSize(width: CGFloat) -> GADAdSize {
    GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
}
#endif

struct AdBannerView: UIViewRepresentable {
    /// 例: "ca-app-pub-3517487281025314/4186629388"
    let adUnitID: String

    @MainActor
    func makeUIView(context: Context) -> GADBannerView {
        precondition(Thread.isMainThread)
        let width  = UIScreen.main.bounds.width
        let size   = anchoredAdaptiveSize(width: width)

        let banner = GADBannerView(adSize: size)
        banner.adUnitID = adUnitID
        banner.rootViewController = topViewController()   // ← UIHelpers.swift の関数を使用
        banner.load(makeAdRequest())                      // ← GADRequest + GADExtras(npa)
        return banner
    }

    @MainActor
    func updateUIView(_ view: GADBannerView, context: Context) {
        precondition(Thread.isMainThread)
        let width = UIScreen.main.bounds.width
        view.adSize = anchoredAdaptiveSize(width: width)
    }
}
