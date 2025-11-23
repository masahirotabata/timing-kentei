// AdsBootstrap.swift
import Foundation
import UIKit            // iPad 判定に必要
import GoogleMobileAds
import AdSupport
import AppTrackingTransparency

/// Google Mobile Ads の一度きり初期化＋ATTハンドリング
@MainActor
enum AdsBootstrap {

    /// 同時多発呼び出しに備えた起動タスク
    private static var startTask: Task<Void, Never>?
    private static var didStart = false

    /// 必要なら初期化（複数回呼ばれても1度だけ実行）
    static func startIfNeeded() async {

        // ✅ iPad は広告を出さない想定ならここで即リターン
        if UIDevice.current.userInterfaceIdiom == .pad {
            didStart = true
            return
        }

        // すでに完了していれば何もしない
        if didStart {
            return
        }

        // ほかの場所からすでに初期化タスクが走っていたらそれを待つ
        if let task = startTask {
            await task.value
            return
        }

        // ここで初めて初期化タスクを作る
        let task = Task { @MainActor in
            // 1) ATT（iOS 14+）：結果に応じて NPA を切り替え
            await requestATTIfAvailableAndSetNPA()

            // 2) Google Mobile Ads 初期化前に、Info.plist からアプリIDを確認
            let appID = Bundle.main.object(
                forInfoDictionaryKey: "GADApplicationIdentifier"
            ) as? String
            print("🍎 GADApplicationIdentifier from Info.plist =", appID as Any)

            // 3) Google Mobile Ads 初期化
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in
                    cont.resume()
                }
            }

            didStart = true
        }

        startTask = task

        // 実体タスクの完了を待つ
        await task.value
    }

    // MARK: - Helpers

    /// iOS14+ なら ATT を問い合わせ、結果で AdPrivacy の NPA フラグを更新
    private static func requestATTIfAvailableAndSetNPA() async {
        guard #available(iOS 14.0, *) else {
            // iOS13以下はトラッキング概念なし：デフォルトでパーソナライズ許可とみなす
            AdPrivacy.useNonPersonalizedAds = false
            return
        }

        let status = ATTrackingManager.trackingAuthorizationStatus
        if status == .notDetermined {
            // システムダイアログ表示（UIスレッド）
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ATTrackingManager.requestTrackingAuthorization { _ in
                    cont.resume()
                }
            }
        }

        // 取得し直して NPA を決定
        let finalStatus = ATTrackingManager.trackingAuthorizationStatus
        AdPrivacy.useNonPersonalizedAds = (finalStatus != .authorized)
    }
}
