// AppDelegate.swift
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
import AppTrackingTransparency
import AdSupport

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // iOS14 以降: ATT ダイアログ → ユーザー選択後に AdMob 初期化
        if #available(iOS 14, *) {

            // 起動直後すぎるとダイアログが出ないことがあるので、少しディレイ
            let workItem = DispatchWorkItem {
                ATTrackingManager.requestTrackingAuthorization { status in
                    // ここはメインスレッドで呼ばれるので、そのまま初期化して OK
                    #if canImport(GoogleMobileAds)
                    MobileAds.shared.start(completionHandler: nil)
                    #endif

                    // もし広告の事前ロードをしたい場合はここで（任意）
                    /*
                    Task { @MainActor in
                        await Ads.preload()
                    }
                    */
                }
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.5,
                execute: workItem
            )

        } else {
            // iOS13 以前は通常の初期化だけ
            #if canImport(GoogleMobileAds)
            MobileAds.shared.start(completionHandler: nil)
            #endif

            /*
            Task { @MainActor in
                await Ads.preload()
            }
            */
        }

        return true
    }
}
