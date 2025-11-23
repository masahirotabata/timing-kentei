import UIKit
import WebKit
import SafariServices
import AdSupport
import AppTrackingTransparency   // ← 追加

final class HomeController: UIViewController,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            WKScriptMessageHandler,
                            SFSafariViewControllerDelegate {

    private var webView: WKWebView!
    private let htmlFileName = "Boxing_Kentei_v5" // ★実ファイル名と完全一致（大文字小文字含む）

    // ATT を一度だけ出すためのフラグ（UserDefaults）
    private let attPromptedKey = "attPrompted_v1"

    // ATT確定／広告プリロードの一回きり制御
    private var didResolveATT = false
    private var hasPreloadedAds = false
    private var shouldPreloadAfterATT = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        // --- WKWebView 構成 ---
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // JS -> ネイティブ橋渡し
        config.userContentController.add(self, name: "ads")   // ads.postMessage("interstitial")
        config.userContentController.add(self, name: "log")   // log.postMessage("...")
        config.userContentController.add(self, name: "share") // share.postMessage({ text:"...", url:"..." })

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .systemBackground
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        // --- ローカルHTML読込（存在チェック＋白画面フォールバック付き） ---
        loadBundledHTML()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // ✅ ATT は広告SDKやトラッキング処理より「前」に呼ぶ
        maybeRequestATT()
    }

    // MARK: - ローカルHTML読込（白画面を防ぐフォールバック）
    private func loadBundledHTML() {
        guard let url = Bundle.main.url(forResource: htmlFileName, withExtension: "html") else {
            // そのまま白画面にしない：エラーメッセージを描画
            let msg = """
            <h2 style='font-family:-apple-system'>ファイルが見つかりません</h2>
            <p>\(htmlFileName).html がバンドルに含まれていません。<br>
            File Inspector の <b>Target Membership</b> と<br>
            Build Phases &gt; <b>Copy Bundle Resources</b> を確認してください。</p>
            """
            webView.loadHTMLString(msg, baseURL: nil)
            assertionFailure("HTML not found in bundle (\(htmlFileName).html)")
            return
        }

        // 相対パスのCSS/JS/画像も読めるように、同ディレクトリに readAccess を付与
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - ATT
    private func maybeRequestATT() {
        func markResolvedAndMaybePreload() {
            self.didResolveATT = true
            // 初回のみプリロード（既存フラグを尊重）
            if self.shouldPreloadAfterATT || !self.hasPreloadedAds {
                self.may12bePreloadAdsOnce()   // ← 既存のプリロード関数を呼ぶ（関数名は元のまま）
                self.shouldPreloadAfterATT = false
            }
        }

        guard #available(iOS 14, *) else {
            // iOS13 以下は ATT なし。即「確定」
            markResolvedAndMaybePreload()
            return
        }

        // すでに出していれば即確定扱い
        if UserDefaults.standard.bool(forKey: attPromptedKey) {
            markResolvedAndMaybePreload()
            return
        }

        // ★ 初回のみ ATT をリクエスト
        ATTrackingManager.requestTrackingAuthorization { _ in
            UserDefaults.standard.set(true, forKey: self.attPromptedKey)
            DispatchQueue.main.async {
                markResolvedAndMaybePreload()
            }
        }
    }

    private func may12bePreloadAdsOnce() {
        guard !hasPreloadedAds else { return }
        AdsManager.shared.preloadInterstitial()
        hasPreloadedAds = true
    }

    // MARK: - Main-thread helper
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async { block() } }
    }

    // MARK: - 外部URLハンドリング（X/Twitter優先、HTTPSフォールバック、SafariVCで開く）
    private func openExternal(_ url: URL) {
        // X / Twitter ディープリンク
        if let scheme = url.scheme?.lowercased(), scheme == "twitter" || scheme == "x" {
            if UIApplication.shared.canOpenURL(url) {
                runOnMain { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
                return
            }
            if let https = deepLinkToHttpsFallback(url) {
                presentSafari(for: https); return
            }
        }

        // http(s) はアプリ内 Safari 表示（iPad の「無反応」回避）
        if url.scheme?.hasPrefix("http") == true {
            presentSafari(for: url); return
        }

        // tel:, mailto:, など
        if UIApplication.shared.canOpenURL(url) {
            runOnMain { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            return
        }

        print("[External] cannot open url: \(url.absoluteString)")
    }

    private func presentSafari(for url: URL) {
        runOnMain {
            let vc = SFSafariViewController(url: url)
            vc.delegate = self
            vc.modalPresentationStyle = .formSheet // iPadでも安定
            self.present(vc, animated: true)
        }
    }

    /// twitter:// / x:// → https://x.com/intent/tweet への簡易フォールバック
    private func deepLinkToHttpsFallback(_ url: URL) -> URL? {
        if url.scheme?.hasPrefix("http") == true { return url }

        if url.host == "post" || url.host == "compose" {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let message = (q.first { $0.name == "message" || $0.name == "text" }?.value) ?? ""
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = "x.com"
            comps.path = "/intent/tweet"
            comps.queryItems = [URLQueryItem(name: "text", value: message)]
            return comps.url
        }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "https"
        comps?.host = "x.com"
        return comps?.url
    }

    // MARK: - JSブリッジ
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "ads":
            if let action = message.body as? String, action == "interstitial" {
                AdsManager.shared.showInterstitialFromTopMost()
            }

        case "log":
            if let text = message.body as? String { print("[JS] \(text)") }

        case "share":
            handleShareMessage(message.body)

        default: break
        }
    }

    private func handleShareMessage(_ body: Any) {
        var text: String?
        var urlString: String?
        var hashtags: String?
        var via: String?

        if let t = body as? String {
            text = t
        } else if let dict = body as? [String: Any] {
            text = dict["text"] as? String
            urlString = dict["url"] as? String
            hashtags = dict["hashtags"] as? String // "aaa,bbb"
            via = dict["via"] as? String
        }

        // 1) X アプリ優先（ディープリンク）
        if let compose = buildTwitterDeepLink(text: text, urlString: urlString, hashtags: hashtags, via: via),
           UIApplication.shared.canOpenURL(compose) {
            runOnMain { UIApplication.shared.open(compose, options: [:], completionHandler: nil) }
            return
        }

        // 2) Web intent（SafariVC）
        if let intent = buildTwitterIntentURL(text: text, urlString: urlString, hashtags: hashtags, via: via) {
            presentSafari(for: intent); return
        }

        // 3) 保険：標準シェアシート（iPadはポップオーバー指定）
        var items: [Any] = []
        if let t = text { items.append(t) }
        if let u = urlString, let uu = URL(string: u) { items.append(uu) }
        presentShareSheet(items: items.isEmpty ? [""] : items)
    }

    private func buildTwitterDeepLink(text: String?, urlString: String?, hashtags: String?, via: String?) -> URL? {
        var message = text ?? ""
        if let u = urlString { message += (message.isEmpty ? "" : " ") + u }
        if let tags = hashtags, !tags.isEmpty {
            let hs = tags.split(separator: ",").map { "#\($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: " ")
            message += (message.isEmpty ? "" : " ") + hs
        }
        if let v = via, !v.isEmpty { message += (message.isEmpty ? "" : " ") + "via @\(v)" }
        let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let xURL = URL(string: "x://post?message=\(encoded)") { return xURL }
        if let twURL = URL(string: "twitter://post?message=\(encoded)") { return twURL }
        return nil
    }

    private func buildTwitterIntentURL(text: String?, urlString: String?, hashtags: String?, via: String?) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "x.com"
        comps.path = "/intent/tweet"
        var items: [URLQueryItem] = []
        if let t = text, !t.isEmpty { items.append(URLQueryItem(name: "text", value: t)) }
        if let u = urlString, !u.isEmpty { items.append(URLQueryItem(name: "url", value: u)) }
        if let h = hashtags, !h.isEmpty { items.append(URLQueryItem(name: "hashtags", value: h)) } // "aaa,bbb"
        if let v = via, !v.isEmpty { items.append(URLQueryItem(name: "via", value: v)) }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.url
    }

    private func presentShareSheet(items: [Any]) {
        runOnMain {
            let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = ac.popoverPresentationController {
                pop.sourceView = self.view
                pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            self.present(ac, animated: true)
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[WebView] didFinish url=\(webView.url?.absoluteString ?? "nil")")
    }

    // ★ 失敗時は“白”にしない：エラーページを表示して原因を見える化
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showReadableError(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showReadableError(error)
    }
    private func showReadableError(_ error: Error) {
        let html = """
        <h2 style='font-family:-apple-system'>読み込みエラー</h2>
        <p>\(error.localizedDescription)</p>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // intent 等は外部で開く
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }

        if url.isFileURL { decisionHandler(.allow); return }

        if let host = url.host?.lowercased(),
           (host == "x.com" || host == "twitter.com"),
           url.path.hasPrefix("/intent/") {
            openExternal(url); decisionHandler(.cancel); return
        }

        if navigationAction.navigationType == .linkActivated {
            openExternal(url); decisionHandler(.cancel); return
        }

        decisionHandler(.allow)
    }

    // target="_blank" 対応
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, navigationAction.targetFrame == nil {
            openExternal(url)
        }
        return nil
    }

    // MARK: - SFSafariViewControllerDelegate
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        // 必要なら閉じ後の処理
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ads")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "log")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "share")
    }
}
