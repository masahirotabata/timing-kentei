import SwiftUI
import WebKit
import StoreKit
import UIKit          // ← 追加
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// MARK: - AdMob 共通

/// ルートVCを取得するヘルパ
func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let baseVC: UIViewController?
    if let base = base {
        baseVC = base
    } else {
        baseVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    if let nav = baseVC as? UINavigationController {
        return topViewController(base: nav.visibleViewController)
    }
    if let tab = baseVC as? UITabBarController {
        return topViewController(base: tab.selectedViewController)
    }
    if let presented = baseVC?.presentedViewController {
        return topViewController(base: presented)
    }
    return baseVC
}

// MARK: - バナー広告ビュー

struct AdBannerView: UIViewRepresentable {
    /// バナー用ユニットID
    private let adUnitID = "ca-app-pub-3517487281025314/2001071381"

    func makeUIView(context: Context) -> BannerView {
        // 画面幅に応じたアダプティブバナー
        let width = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)

        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // 特に更新なし
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerView(_ bannerView: BannerView,
                        didFailToReceiveAdWithError error: Error) {
            print("Banner failed: \(error)")
        }
    }
}

// MARK: - インタースティシャル管理

final class InterstitialAdManager: NSObject, ObservableObject {
    /// インタースティシャル用ユニットID
    private let adUnitID = "ca-app-pub-3517487281025314/5941822894"

    private var interstitial: InterstitialAd?

    /// 直近表示した日時
    private var lastShowDate: Date?
    /// インターバル（秒）…ここでは「2分に1回まで」
    private let minInterval: TimeInterval = 120

    override init() {
        super.init()
        load()
    }

    /// 広告をロード
    func load() {
        let request = Request()
        InterstitialAd.load(with: adUnitID,
                            request: request) { [weak self] ad, error in
            if let error = error {
                print("Interstitial load error: \(error)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }

    /// 表示して良い状態か？
    private func canShow() -> Bool {
        // まだ一度も出していなければOK
        guard let last = lastShowDate else { return true }
        // 最後の表示から minInterval 秒以上あいていればOK
        return Date().timeIntervalSince(last) >= minInterval
    }

    /// 表示可能なら表示する
    func showIfReady() {
        guard canShow(),
              let root = topViewController(),
              let ad = interstitial else {
            return
        }
        lastShowDate = Date()
        ad.present(from: root)
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 閉じられたら次をロード
        load()
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("Interstitial present error: \(error)")
        load()
    }
}

// MARK: - ダブルタップの動作種別

enum DoubleTapAction: String, CaseIterable, Identifiable {
    case scrollDown   // 画面分スクロール（無料）
    case jumpBottom   // ページ大幅下部へジャンプ（有料）
    case jumpTop      // ページ最上部へジャンプ（有料）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scrollDown: return "下にスクロール（無料）"
        case .jumpBottom: return "ページの下部に大幅にジャンプ"
        case .jumpTop:    return "ページ最上部へジャンプ"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .scrollDown: return false
        case .jumpBottom, .jumpTop: return true
        }
    }

    var jsModeString: String {
        switch self {
        case .scrollDown: return "scrollDown"
        case .jumpBottom: return "jumpBottom"
        case .jumpTop:    return "jumpTop"
        }
    }
}

// MARK: - 共有設定

class AppSettings: ObservableObject {
    @Published var currentURLString: String = "https://www.yahoo.co.jp"
    @Published var isDoubleTapEnabled: Bool = true
    @Published var scrollFactor: Double = 1.0
    @Published var selectedAction: DoubleTapAction = .scrollDown
    @Published var isProUnlocked: Bool = false
    @Published var favoriteSites: [String] = [
        "https://www.yahoo.co.jp",
        "https://news.yahoo.co.jp",
        "https://www.youtube.com",
        "https://www.google.com"
    ]
}

// MARK: - StoreKit2: 買い切り Pro 解放管理

@MainActor
class StoreManager: ObservableObject {
    /// 非消耗型（買い切り）のプロダクトID
    let proUnlockID = "doubletap_full_unlock"

    @Published var products: [Product] = []
    @Published private(set) var activeEntitlementIDs: Set<String> = []

    /// Pro 機能が解放済みかどうか
    var isProUnlocked: Bool {
        activeEntitlementIDs.contains(proUnlockID)
    }

    init() {
        Task {
            await loadProducts()
            await updateEntitlementsFromHistory()
            await listenForTransactions()
        }
    }

    /// 商品情報を取得
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: [proUnlockID])
            products = storeProducts
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    /// 購入済みプロダクト（非消耗型含む）を履歴から再計算
    func updateEntitlementsFromHistory() async {
        var newIDs: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            newIDs.insert(transaction.productID)
        }
        activeEntitlementIDs = newIDs
    }

    /// トランザクションの変化（返金・ファミリー共有など）を監視
    func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await updateEntitlementsFromHistory()
            await transaction.finish()
        }
    }

    /// Pro 機能の買い切り購入
    func purchasePro() async throws {
        guard let product = products.first(where: { $0.id == proUnlockID }) else {
            throw PurchaseError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await updateEntitlementsFromHistory()
                await transaction.finish()
            }
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    /// 購入の復元（再インストール時など）
    func restorePurchases() async {
        await updateEntitlementsFromHistory()
    }

    enum PurchaseError: Error {
        case productNotFound
    }
}

// MARK: - エントリポイント

@main
struct DoubleTapBrowserApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var storeManager = StoreManager()

    init() {
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(storeManager)
                .task {
                    settings.isProUnlocked = storeManager.isProUnlocked
                }
        }
    }
}

// MARK: - メインタブ

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            WebBrowserView()
                .tabItem {
                    Image(systemName: "globe")
                    Text("ブラウズ")
                }

            FavoritesView()
                .tabItem {
                    Image(systemName: "star.fill")
                    Text("お気に入り")
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("設定")
                }
        }
    }
}

// MARK: - ブラウザ画面

struct WebBrowserView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var addressText: String = ""
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    @StateObject private var interstitialManager = InterstitialAdManager()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("URLを入力", text: $addressText, onCommit: loadFromAddressBar)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                Button("開く") {
                    loadFromAddressBar()
                }
                .padding(.leading, 4)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .onAppear {
                addressText = settings.currentURLString
            }
            .onChange(of: settings.currentURLString) { newURL in
                addressText = newURL
            }

            WebViewRepresentable(
                urlString: settings.currentURLString,
                isDoubleTapEnabled: settings.isDoubleTapEnabled,
                scrollFactor: settings.scrollFactor,
                action: settings.selectedAction,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
            .id(settings.selectedAction)

            HStack {
                Button(action: {
                    NotificationCenter.default.post(name: .webViewGoBack, object: nil)
                }) {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!canGoBack)
                .frame(maxWidth: .infinity)

                Button(action: {
                    NotificationCenter.default.post(name: .webViewReload, object: nil)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .frame(maxWidth: .infinity)

                Button(action: {
                    NotificationCenter.default.post(name: .webViewGoForward, object: nil)
                }) {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!canGoForward)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .background(Color(.systemBackground))

            // ★ Pro 解放済みならバナーを完全に非表示
            if !settings.isProUnlocked {
                AdBannerView()
                    .frame(height: 60)
            }
        }
    }

    private func loadFromAddressBar() {
        var text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://\(text)"
        }
        settings.currentURLString = text
        addressText = text

        // ★ Pro ではインタースティシャルも表示しない
        if !settings.isProUnlocked {
            interstitialManager.showIfReady()
        }
    }
}

// MARK: - お気に入り画面

struct FavoritesView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationView {
            List {
                ForEach(settings.favoriteSites, id: \.self) { url in
                    Button(action: {
                        settings.currentURLString = url
                    }) {
                        HStack {
                            Image(systemName: "star")
                            Text(url)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("お気に入りサイト")
        }
    }
}

// MARK: - 設定画面

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var storeManager: StoreManager

    @State private var isPurchasing = false
    @State private var purchaseError: String?

    var body: some View {
        NavigationView {
            Form {
                // --- ダブルタップ機能 ---
                Section(header: Text("ダブルタップ機能")) {
                    Toggle(isOn: $settings.isDoubleTapEnabled) {
                        Text("ダブルタップを有効にする")
                    }

                    // 動作選択
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ダブルタップの動作")

                        Picker("ダブルタップの動作", selection: $settings.selectedAction) {
                            ForEach(DoubleTapAction.allCases) { action in
                                HStack {
                                    Text(action.displayName)
                                    if action.requiresPro && !settings.isProUnlocked {
                                        Text("PRO")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .tag(action)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!settings.isProUnlocked && settings.selectedAction.requiresPro)
                        .onChange(of: settings.selectedAction) { newValue in
                            if newValue.requiresPro && !settings.isProUnlocked {
                                settings.selectedAction = .scrollDown
                            }
                        }

                        if !settings.isProUnlocked {
                            Text("※ ページ最上部/大幅下部ジャンプは Pro 解放後に利用できます。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    // ジャンプ系モード（jumpBottom / jumpTop）はカンスト表示
                    let isJumpMaxMode =
                        settings.isProUnlocked &&
                        (settings.selectedAction == .jumpBottom ||
                         settings.selectedAction == .jumpTop)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("スクロール量")
                            Spacer()
                            if isJumpMaxMode {
                                Text("10000.0 × 画面")
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(format: "%.1f × 画面", settings.scrollFactor))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Slider(
                            value: $settings.scrollFactor,
                            in: 0.5...1.5,
                            step: 0.1
                        )
                        .disabled(isJumpMaxMode)   // ジャンプ系のときは操作不可
                    }
                } // Section ダブルタップ機能

                // --- Pro アップグレード ---
                Section(header: Text("Pro アップグレード（買い切り）")) {
                    HStack {
                        Text(settings.isProUnlocked
                             ? "Pro 機能は解放済みです 🎉"
                             : "ページ最上部/大幅下部ジャンプ & 広告非表示を買い切りで解放できます")
                            .foregroundColor(settings.isProUnlocked ? .green : .primary)
                        Spacer()
                    }

                    if !settings.isProUnlocked {
                        Button {
                            Task { await purchase() }
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                }
                                Text("Pro 機能を解放（買い切り）")
                            }
                        }
                    }

                    Button {
                        Task {
                            await storeManager.restorePurchases()
                            settings.isProUnlocked = storeManager.isProUnlocked
                        }
                    } label: {
                        Text("購入を復元")
                    }
                }

                // --- 広告表示について ---
                Section(header: Text("広告表示について")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if settings.isProUnlocked {
                            Text("現在ご利用中の Pro 版では、画面下部のバナー広告やポップアップ広告は表示されません。")
                        } else {
                            Text("現在は、画面下部にバナー広告が表示され、一部の操作タイミングで全画面広告が表示されることがあります。")
                        }

                        Text("買い切りの Pro アップグレードをご購入いただくと、これらの広告はすべて非表示になり、より快適にブラウジングをお楽しみいただけます。")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }

                // --- 他のアプリ ---
                Section(header: Text("他のアプリ")) {
                    Button {
                        openAppStore(appId: "6753610818")   // 美女と英単語 - Beauty & Words
                    } label: {
                        HStack {
                            Image(systemName: "text.book.closed")
                            Text("美女と英単語 - Beauty & Words")
                        }
                    }

                    Button {
                        openAppStore(appId: "6753014764")   // ボクシング検定
                    } label: {
                        HStack {
                            Image(systemName: "figure.boxing")
                            Text("ボクシング検定 - 反射神経＆タイミング")
                        }
                    }

                    Button {
                        openAppStore(appId: "6752886026")   // タイミング検定
                    } label: {
                        HStack {
                            Image(systemName: "timer")
                            Text("タイミング検定")
                        }
                    }
                }

                // --- アプリ情報 ---
                Section(header: Text("情報")) {
                    Text("DoubleTapBrowser")
                    Text("バージョン 1.0.0")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("設定")
            .alert("購入エラー",
                   isPresented: .constant(purchaseError != nil),
                   actions: {
                       Button("OK") { purchaseError = nil }
                   },
                   message: {
                       Text(purchaseError ?? "")
                   })
        }
    }

    private func openAppStore(appId: String) {
        guard let url = URL(string: "https://apps.apple.com/jp/app/id\(appId)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await storeManager.purchasePro()
            settings.isProUnlocked = storeManager.isProUnlocked
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}


// MARK: - WebView + ダブルタップJS

extension Notification.Name {
    static let webViewGoBack = Notification.Name("webViewGoBack")
    static let webViewGoForward = Notification.Name("webViewGoForward")
    static let webViewReload = Notification.Name("webViewReload")
}

struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let isDoubleTapEnabled: Bool
    let scrollFactor: Double
    let action: DoubleTapAction

    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // ★ jumpBottom / jumpTop のときは factor を 10000 に固定
        let isJumpMax = (action == .jumpBottom || action == .jumpTop)
        let initialFactor: Double = isJumpMax ? 10000.0 : scrollFactor

        let configScriptSource = """
        window._doubleTapConfig = {
          enabled: \(isDoubleTapEnabled ? "true" : "false"),
          factor: \(initialFactor),
          mode: "\(action.jsModeString)"
        };
        """
        let configScript = WKUserScript(
            source: configScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(configScript)

        let doubleTapScriptSource = """
        (function () {
          if (window.__doubleTapScrollInstalled) { return; }
          window.__doubleTapScrollInstalled = true;
          const TAP_THRESHOLD = 300;
          let lastTapTime = 0;
          const IGNORE_TAGS = new Set([
            'INPUT','TEXTAREA','BUTTON','SELECT','OPTION','LABEL','A'
          ]);
          const scrollRoot = document.scrollingElement || document.documentElement || document.body;
          function isEditable(el) {
            if (!el) return false;
            if (IGNORE_TAGS.has(el.tagName)) return true;
            if (el.isContentEditable) return true;
            return false;
          }
          function getTarget() {
            return scrollRoot || window;
          }
          function scrollByAmount(target, amount) {
            if (target === window) {
              window.scrollBy({top: amount, left: 0, behavior: 'smooth'});
            } else {
              target.scrollBy({top: amount, left: 0, behavior: 'smooth'});
            }
          }
          function scrollToTopValue(target, top) {
            if (target === window) {
              window.scrollTo({top: top, left: 0, behavior: 'smooth'});
            } else {
              target.scrollTo({top: top, left: 0, behavior: 'smooth'});
            }
          }
          function getScrollHeight() {
            const root = document.scrollingElement || document.documentElement || document.body;
            return root ? (root.scrollHeight || 0) : 0;
          }
          function performAction() {
            const cfg = window._doubleTapConfig;
            if (!cfg || !cfg.enabled) return;
            const factor = cfg.factor || 1.0;
            const mode = cfg.mode || "scrollDown";
            const target = getTarget();
            if (mode === "scrollDown") {
              scrollByAmount(target, window.innerHeight * factor);
            } else if (mode === "jumpBottom") {
              const h = getScrollHeight();
              const dest = Math.max(0, h - window.innerHeight);
              scrollToTopValue(target, dest);
            } else if (mode === "jumpTop") {
              scrollToTopValue(target, 0);
            }
          }
          document.addEventListener('dblclick', function(e) {
            if (isEditable(e.target)) return;
            performAction();
          });
          document.addEventListener('touchend', function(e) {
            const now = Date.now();
            const diff = now - lastTapTime;
            if (diff > 0 && diff < TAP_THRESHOLD) {
              if (isEditable(e.target)) {
                lastTapTime = 0;
                return;
              }
              performAction();
              lastTapTime = 0;
            } else {
              lastTapTime = now;
            }
          }, {passive: true});
        })();
        """
        let doubleTapScript = WKUserScript(
            source: doubleTapScriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(doubleTapScript)

        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true

        NotificationCenter.default.addObserver(
            forName: .webViewGoBack,
            object: nil,
            queue: .main
        ) { _ in
            if webView.canGoBack { webView.goBack() }
        }

        NotificationCenter.default.addObserver(
            forName: .webViewGoForward,
            object: nil,
            queue: .main
        ) { _ in
            if webView.canGoForward { webView.goForward() }
        }

        NotificationCenter.default.addObserver(
            forName: .webViewReload,
            object: nil,
            queue: .main
        ) { _ in
            webView.reload()
        }

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let currentURL = webView.url?.absoluteString {
            if currentURL != urlString, let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        } else if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        let isJumpMax = (action == .jumpBottom || action == .jumpTop)
        let effectiveFactor: Double = isJumpMax ? 10000.0 : scrollFactor

        let configJS = """
        window._doubleTapConfig = {
          enabled: \(isDoubleTapEnabled ? "true" : "false"),
          factor: \(effectiveFactor),
          mode: "\(action.jsModeString)"
        };
        """
        webView.evaluateJavaScript(configJS, completionHandler: nil)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }
    }
}
