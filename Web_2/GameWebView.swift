import SwiftUI
import WebKit

struct GameWebView: UIViewRepresentable {
    let htmlFile: String              // 例: "number_laser_siege_items_boss_fix2"
    private let folder = "Web_2"      // 既存のままでOK

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)

        loadHTML(into: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // ここだけ追加 / 修正
    private func loadHTML(into web: WKWebView) {
        // ① まず Web_2 フォルダの中を探す
        var url = Bundle.main.url(
            forResource: htmlFile,
            withExtension: "html",
            subdirectory: folder
        )

        // ② 見つからなければ、フォルダなし（バンドル直下）を探す
        if url == nil {
            url = Bundle.main.url(
                forResource: htmlFile,
                withExtension: "html"
            )
        }

        // ③ それでもダメならエラーメッセージHTML
        guard let finalURL = url else {
            let html = """
            <html><body>
            <p>ファイルが見つかりません。<br>
            \(htmlFile).html がバンドルに含まれていないか、パスが違います。<br>
            Xcode の Copy Bundle Resources と Target Membership を確認してください。
            </p>
            </body></html>
            """
            web.loadHTMLString(html, baseURL: nil)
            return
        }

        web.loadFileURL(finalURL, allowingReadAccessTo: finalURL.deletingLastPathComponent())
    }
}
