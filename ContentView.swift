import SwiftUI
import WebKit
import GoogleMobileAds

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // HTML（index名は必要に応じて変更）
            HTMLView(htmlFile: "Boxing_Kentei_V4_ComboUpperHookAnalytics")
                .ignoresSafeArea(edges: .bottom)

            // 50pt 高さのバナー（iPad では AppDelegate 側でスキップされる想定）
            //AdBannerView(adUnitID: "ca-app-pub-3517487281025314/2959050533")
               // .frame(height: 50)
        }
    }
}

/// このファイルだけで動く簡易 WebView（`WebView` の代替）
struct HTMLView: UIViewRepresentable {
    let htmlFile: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(iOS 14.0, *) {
            let p = WKWebpagePreferences()
            p.allowsContentJavaScript = true
            config.defaultWebpagePreferences = p
        } else {
            config.preferences.javaScriptEnabled = true
        }
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false

        // バンドル内の HTML を多段探索して読み込み
        if let url = bundledHTMLURL(htmlFile) {
            let dir = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: dir)
        } else {
            webView.loadHTMLString("""
                <meta name=viewport content="width=device-width,initial-scale=1">
                <style>body{font:-apple-system-body;margin:24px}</style>
                <h2>HTML not found</h2>
                <p>Tried: \(htmlFile).html / Web/ / Shared/Web/ / index.html</p>
                """, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Helpers
    private func bundledHTMLURL(_ name: String) -> URL? {
        let b = Bundle.main
        return [
            b.url(forResource: name, withExtension: "html"),
            b.url(forResource: name, withExtension: "html", subdirectory: "Web"),
            b.url(forResource: name, withExtension: "html", subdirectory: "Shared/Web"),
            b.url(forResource: "index", withExtension: "html")
        ].compactMap { $0 }.first
    }
}
