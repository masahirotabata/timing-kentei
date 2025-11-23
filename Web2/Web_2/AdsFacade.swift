// AdsFacade.swift
import UIKit

/// 広告関連はすべてメインアクター上で実行
@MainActor
enum Ads {

    /// GMA SDK（＋ATT処理）の初期化だけ行いたい時に使用
    static func start() async {
        // ✅ iPad では広告SDKを一切触らない（クラッシュ回避のため）
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        await AdsBootstrap.startIfNeeded()
    }

    /// インタースティシャルの事前ロード
    static func preload() async {
        // ✅ iPad は常にスキップ
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }

        await AdsBootstrap.startIfNeeded()
        await AdManager.shared.preload()
    }

    /// 可能ならインタースティシャルを表示
    /// - Parameter allowPad: iPadでも表示したい場合のみ true（通常は false のままでOK）
    static func showInterstitial(allowPad: Bool = false) async {
        // ✅ デフォルトでは iPad では絶対に出さない
        if UIDevice.current.userInterfaceIdiom == .pad, !allowPad {
            return
        }

        await AdsBootstrap.startIfNeeded()

        // ✅ いちばん上に出ている ViewController から表示
        guard let rootVC = currentTopViewController() else {
            // 取れなかったら何もせず終了（クラッシュさせない）
            return
        }
        AdManager.shared.showInterstitial(from: rootVC)
    }

    // MARK: - 最前面の ViewController を取得するヘルパー

    private static func currentTopViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    ) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return currentTopViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return currentTopViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return currentTopViewController(base: presented)
        }
        return base
    }
}
