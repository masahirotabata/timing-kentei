// AppDelegate.swift
import UIKit
import AppTrackingTransparency
import AdSupport
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        if #available(iOS 14, *) {
            // 起動直後すぎると出ないことがあるので、少しディレイ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ATTrackingManager.requestTrackingAuthorization { status in
                    // ユーザーの選択後に AdMob 初期化
                    #if canImport(GoogleMobileAds)
                    MobileAds.shared.start(completionHandler: nil)
                    #endif
                }
            }
        } else {
            // iOS 13 以前はそのまま初期化
            #if canImport(GoogleMobileAds)
            MobileAds.shared.start(completionHandler: nil)
            #endif
        }

        return true
    }
}

