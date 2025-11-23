import SwiftUI

struct ContentView_Kazulazer: View {

    // バナー用ユニットID
    private let bannerUnitID = "ca-app-pub-3517487281025314/4186629388"

    var body: some View {
        VStack(spacing: 0) {
            // ゲーム本体（HTML5）
            GameWebView(htmlFile: "number_laser_siege_items_boss_fix2")
                .ignoresSafeArea(edges: .top)

            // 画面下部バナー
            AdBannerView(adUnitID: bannerUnitID)
                .frame(height: 50)
        }
        // ★ ここには .task を付けない（Ads.start / preload は App 側だけ）
    }
}
