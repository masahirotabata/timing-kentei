// UIHelpers.swift
import SwiftUI
#if canImport(UIKit)
import UIKit

@MainActor
public enum UIHelpers {

    /// 最前面の keyWindow を推定（複数シーン対応）
    public static func keyWindow() -> UIWindow? {
        // アクティブ/非アクティブ前面シーンを優先
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                // foregroundActive を最優先、それ以外は適当に並べ替え
                func score(_ s: UIScene.ActivationState) -> Int {
                    switch s {
                    case .foregroundActive: return 0
                    case .foregroundInactive: return 1
                    case .background: return 2
                    default: return 3
                    }
                }
                return score(lhs.activationState) < score(rhs.activationState)
            }

        for scene in scenes {
            if let win = scene.windows.first(where: { $0.isKeyWindow }) { return win }
            if let win = scene.windows.first(where: { $0.windowLevel == .normal && !$0.isHidden }) { return win }
        }
        // 旧APIフォールバック（将来の互換目的）
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    }

    /// ベースVCがあればそれを、なければ現在のrootVCを返す
    public static func rootViewController(from base: UIViewController? = nil) -> UIViewController? {
        if let base = base { return base }
        return keyWindow()?.rootViewController
    }

    /// 画面上で一番上にいるVCを取得（Nav/Tab/Split/presented 対応）
    public static func topViewController(from base: UIViewController? = nil) -> UIViewController? {
        var top: UIViewController? = rootViewController(from: base)

        while true {
            if let nav = top as? UINavigationController {
                top = nav.visibleViewController ?? nav.topViewController
                continue
            }
            if let tab = top as? UITabBarController {
                top = tab.selectedViewController
                continue
            }
            if let split = top as? UISplitViewController, let last = split.viewControllers.last {
                top = last
                continue
            }
            if let presented = top?.presentedViewController, !presented.isBeingDismissed {
                top = presented
                continue
            }
            break
        }
        return top
    }

    /// 最高位のVC上に安全にpresent
    public static func presentOnTop(_ vc: UIViewController,
                                    animated: Bool = true,
                                    completion: (() -> Void)? = nil) {
        guard let host = topViewController() else { return }
        // もし一瞬のUIAlertControllerが残っていたら念のため潰してから
        if host is UIAlertController, host.presentedViewController == nil {
            host.dismiss(animated: false) {
                host.present(vc, animated: animated, completion: completion)
            }
        } else {
            host.present(vc, animated: animated, completion: completion)
        }
    }
}

/// AdsFacade などから使うシンプルなトップVCヘルパー
/// - 例: `AdManager.shared.showInterstitial(from: topViewController())`
@MainActor
public func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
    UIHelpers.topViewController(from: base)
}

#endif
