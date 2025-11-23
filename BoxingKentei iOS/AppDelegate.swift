import UIKit
import GoogleMobileAds
import AppTrackingTransparency   // ATT
import AdSupport                 // IDFA

extension Notification.Name {
    static let gmaInitialized = Notification.Name("gma_initialized")
}

// Obj-C 実装の C 関数を Swift から呼ぶ（Bridging Header 不要）
@_silgen_name("ForceKeepIDFA") func ForceKeepIDFA() -> Void

/// IDFA シンボルが最適化で除去されないように明示参照
@inline(never) private func touchIDFASymbols() {
    let m = ASIdentifierManager.shared()
    _ = m.advertisingIdentifier
    _ = m.isAdvertisingTrackingEnabled
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private(set) var adsReady = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 初期画面（SwiftUIに依存しない構成）
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = HomeController()   // ← 初期画面VCに合わせて変更
        win.makeKeyAndVisible()
        self.window = win

        // 起動直後に “確実に” IDFA シンボルへ触れる（Obj-C + Swift の二段構え）
        ForceKeepIDFA()
        touchIDFASymbols()

        // ATT を要求 → 結果に関係なく GMA 起動
        requestATTThenStartGMA()
        return true
    }

    // MARK: - ATT → GMA 初期化
    private func requestATTThenStartGMA() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { [weak self] status in
                print("[ATT] status=\(status.rawValue)")

                // 追加の保険：コールバック内でも IDFA に触れる
                ForceKeepIDFA()
                touchIDFASymbols()

                DispatchQueue.main.async { self?.startGMA() }
            }
        } else {
            // iOS 13 以下は ATT なしでそのまま起動
            startGMA()
        }
    }

    private func startGMA() {
        MobileAds.shared.start { [weak self] _ in
            self?.adsReady = true
            print("[Ads] GMA started")
            NotificationCenter.default.post(name: .gmaInitialized, object: nil)
        }
    }
}
