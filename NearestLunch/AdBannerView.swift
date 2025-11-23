//
//  AdBannerView.swift
//  TimingKentei APP
//
//  Created by 田端政裕 on 2025/11/23.
//

import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// --- ここで BannerView を定義しておく（ターゲットごとに共有される） ---
#if canImport(GoogleMobileAds)
typealias BannerView = GADBannerView
#else
// Preview や GoogleMobileAds 未リンク時用のダミー
typealias BannerView = UIView
#endif
// -------------------------------------------------------------------------


/// 画面下部に表示するバナー広告ビュー
struct AdBannerView: UIViewRepresentable {
    /// AdMob のバナー広告ユニットID
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        #if canImport(GoogleMobileAds)
        // 画面幅に合わせたアンカー型アダプティブバナー
        let width = UIScreen.main.bounds.width
        let size  = currentOrientationAnchoredAdaptiveBanner(width: width)

        let banner = BannerView(adSize: size)
        banner.adUnitID = adUnitID
        banner.rootViewController = topViewController()
        banner.load(Request())          // すでに定義済みの typealias Request = GADRequest を利用
        return banner
        #else
        // GoogleMobileAds が無い（Preview など）場合は空の UIView を返す
        return BannerView()
        #endif
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // ここでは特に更新なし
    }
}
