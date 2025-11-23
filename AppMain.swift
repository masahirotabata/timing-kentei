// AppMain.swift
import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct KazuLazerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView_Kazulazer()
                .task {
                    #if canImport(GoogleMobileAds)
                    // iPad は Ads.start()/preload() 側でもガードされているが、
                    // ここでも念のため phone のときだけ呼ぶ
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        await Ads.start()      // GMA SDK + ATT 初期化
                        await Ads.preload()    // インタースティシャル事前ロード
                    }
                    #endif
                }
        }
    }
}
