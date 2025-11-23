import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency   // ← 追加

// v12: BannerView, AdSizeBanner, Request
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

        context.coordinator.attach(banner)
        context.coordinator.loadIfReady()  // 既に初期化済みなら即ロード
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        context.coordinator.loadIfReady()
    }

    final class Coordinator: NSObject {
        private let parent: AdBannerView
        private weak var banner: BannerView?
        private var loaded = false
        private var observer: NSObjectProtocol?

        init(_ parent: AdBannerView) {
            self.parent = parent
            super.init()
            observer = NotificationCenter.default.addObserver(
                forName: .gmaInitialized, object: nil, queue: .main
            ) { [weak self] _ in
                self?.loadIfReady()
            }
        }
        deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

        func attach(_ banner: BannerView) { self.banner = banner }

        func loadIfReady() {
            guard !loaded else { return }
            guard UIDevice.current.userInterfaceIdiom != .pad else { return }

            // ★ ATT が未決定ならロードしない（ATT 組み込みの最小ガード）
            if #available(iOS 14, *) {
                if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                    return
                }
            }

            // AppDelegate のフラグのみで判定（sdkVersion 等は使わない）
            let appReady = (UIApplication.shared.delegate as? AppDelegate)?.adsReady ?? false
            guard appReady, let banner = banner else { return }

            DispatchQueue.main.async {
                guard !self.loaded else { return }
                banner.load(Request())
                self.loaded = true
                print("[Ads] Banner load() issued")
            }
        }
    }
}
