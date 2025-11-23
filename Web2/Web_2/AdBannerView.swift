import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit

// 端末幅に応じたアンカー型アダプティブサイズ（v11）
@inline(__always)
private func makeAdaptiveBannerSize(width: CGFloat) -> AdSize {
    currentOrientationAnchoredAdaptiveBanner(width: width)
}

// SwiftUI バナーView
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let width  = UIScreen.main.bounds.width
        let size   = makeAdaptiveBannerSize(width: width)

        let banner = BannerView(adSize: size)
        banner.adUnitID = adUnitID

        // ✅ iPad は完全に非表示＆SDKには触れない
        if UIDevice.current.userInterfaceIdiom == .pad {
            banner.isHidden = true
            return banner
        }

        banner.rootViewController = UIHelpers.rootViewController()

        Task { @MainActor in
            await AdsBootstrap.startIfNeeded()
            banner.load(makeAdRequest())
        }
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // そのままでOK
    }
}

#endif
