// AdManager.swift
import UIKit
import GoogleMobileAds
// ★ 共通の広告リクエスト生成（NPA対応したい場合用）

/// ATT 不許可時などにノンパーソナライズド広告を出したい場合に使うフラグ
enum AdPrivacy {
    static var useNonPersonalizedAds = false   // 必要に応じてどこかで true にする
}

/// Google Mobile Ads SDK v11 用のリクエスト生成ヘルパ
func makeAdRequest() -> Request {
    let req = Request()
    if AdPrivacy.useNonPersonalizedAds {
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]   // non-personalized ads
        req.register(extras)
    }
    return req
}

// ★ ここから元の AdManager 本体 --------------------------------

@MainActor
final class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    private let interstitialUnitID = "ca-app-pub-3517487281025314/7448337102"

    private override init() {
        super.init()
    }

    /// インタースティシャルを事前ロード
    /// - Note: iPad では何もしない（AdsFacade 側でもガードしているが二重チェックで安全に）
    func preload() async {
        // 念のため iPad はスキップ
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }

        // MobileAds の初期化は外側（AdsBootstrap.startIfNeeded()）で済ませておく前提
        InterstitialAd.load(
            with: interstitialUnitID,
            request: makeAdRequest()
        ) { [weak self] ad, err in
            guard let self = self else { return }

            if let err = err {
                print("[AdManager] load error:", err.localizedDescription)
                self.interstitial = nil
                return
            }

            self.interstitial = ad
            ad?.fullScreenContentDelegate = self
            print("[AdManager] interstitial loaded")
        }
    }

    /// 表示（未ロードなら preload だけ仕込んで戻る）
    /// - Parameter root: 表示元の UIViewController
    func showInterstitial(from root: UIViewController?) {
        // 念のため iPad はスキップ（allowPad の判定は Ads.showInterstitial 側で実施）
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }

        guard let root = root, let ad = interstitial else {
            // まだロードされていなければ次回に備えて仕込む
            Task { [weak self] in
                await self?.preload()
            }
            print("[AdManager] no interstitial ready, preload scheduled")
            return
        }

        ad.present(from: root)
    }

    // MARK: - FullScreenContentDelegate

    /// 閉じたら次回に向けて仕込み直し
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("[AdManager] interstitial dismissed, preload next")
        Task { [weak self] in
            await self?.preload()
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("[AdManager] present failed:", error.localizedDescription)
        Task { [weak self] in
            await self?.preload()
        }
    }
}
