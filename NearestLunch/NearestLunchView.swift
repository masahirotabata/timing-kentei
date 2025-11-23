//
//  NearestLunchView.swift
//  TimingKentei APP
//
//  Created by 田端政裕 on 2025/11/22.
//

import SwiftUI
import CoreLocation   // 位置情報用
import StoreKit       // StoreKit2

// MARK: - モード種別

enum LunchMode: String, CaseIterable, Identifiable {
    case quick   // サクッとランチ
    case relax   // まったりランチ
    case cheers  // 乾杯ご飯屋さん
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .quick:  return "サクッと"
        case .relax:  return "まったり"
        case .cheers: return "乾杯"
        }
    }
    
    var description: String {
        switch self {
        case .quick:
            return "近くですぐ入れるお店を優先"
        case .relax:
            return "少し歩いてでもゆっくりできるお店"
        case .cheers:
            return "夜の乾杯に合うお店"
        }
    }
}

// MARK: - 画面状態

enum AppScreen {
    case home
    case searching
    case result
}

// MARK: - ご飯屋モデル

struct Restaurant: Identifiable {
    let id = UUID()
    let placeId: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Int
    let walkingMinutes: Int
    let rating: Double
    let reviewCount: Int
    let priceLevel: Int?      // 1〜4くらいを想定（¥〜¥¥¥¥）
    let isOpenNow: Bool
    let closingTimeText: String?  // 例: "22:00 まで"（Nearby Search だけだと詳細は nil）
    
    /// 表示用の料金目安（¥〜¥¥¥¥）
    var priceText: String {
        guard let priceLevel = priceLevel, priceLevel > 0 else { return "-" }
        return String(repeating: "¥", count: priceLevel)
    }
    
    /// 距離表示
    var distanceText: String {
        if distanceMeters < 1000 {
            return "\(distanceMeters)m"
        } else {
            let km = Double(distanceMeters) / 1000.0
            return String(format: "%.1fkm", km)
        }
    }
    
    /// 営業状況表示
    var openStatusText: String {
        if isOpenNow {
            if let closing = closingTimeText {
                return "営業中（\(closing)）"
            } else {
                return "営業中"
            }
        } else {
            return "営業時間外"
        }
    }
}

// MARK: - Places API 用エラー（クォータ超過など）

enum PlacesAPIError: LocalizedError {
    /// 429（クォータ上限）相当
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            return "本日の無料検索回数が上限に達しました。明日またお試しください。"
        }
    }
}

// MARK: - 課金 / 広告非表示 管理（StoreKit2）

@MainActor
final class NearestLunchPurchaseManager: ObservableObject {
    static let shared = NearestLunchPurchaseManager()
    
    /// App Store Connect で作る非消耗型の Product ID
    /// 例: com.tabata.NearestLunch.removeAds
    private let productId = "com.tabata.NearestLunch.removeAds"
    
    private let premiumKey = "NearestLunch_isPremium"
    
    @Published private(set) var isPremium: Bool
    @Published var purchaseErrorMessage: String?
    @Published var isProcessing: Bool = false
    
    private init() {
        self.isPremium = UserDefaults.standard.bool(forKey: premiumKey)
        // 起動時に一応 Entitlement から再チェック
        Task {
            await refreshPurchasedStatus()
        }
        // トランザクション更新監視
        Task {
            await observeTransactions()
        }
    }
    
    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: premiumKey)
    }
    
    /// removeAds の購入処理
    func purchaseRemoveAds() async {
        guard !isPremium else { return }
        isProcessing = true
        purchaseErrorMessage = nil
        
        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                throw NSError(domain: "NearestLunchPurchase", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "課金情報が見つかりませんでした。少し時間をおいて再度お試しください。"
                ])
            }
            
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // 正常に購入完了
                    setPremium(true)
                    await transaction.finish()
                case .unverified(_, let error):
                    throw error
                }
            case .userCancelled:
                break
            case .pending:
                purchaseErrorMessage = "購入が保留状態です。しばらくしてから再度ご確認ください。"
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
        
        isProcessing = false
    }
    
    /// 購入の復元
    func restorePurchases() async {
        isProcessing = true
        purchaseErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshPurchasedStatus()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
        isProcessing = false
    }
    
    /// 現在の Entitlement から isPremium を再判定
    func refreshPurchasedStatus() async {
        var hasPremium = false
        
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == productId &&
                    transaction.revocationDate == nil &&
                    (transaction.expirationDate == nil || transaction.expirationDate! > Date()) {
                    hasPremium = true
                }
            case .unverified:
                break
            }
        }
        
        setPremium(hasPremium)
    }
    
    /// トランザクションのライブ更新監視
    private func observeTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == productId {
                    if transaction.revocationDate == nil &&
                        (transaction.expirationDate == nil || transaction.expirationDate! > Date()) {
                        setPremium(true)
                    } else {
                        setPremium(false)
                    }
                }
                await transaction.finish()
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class NearestRestaurantViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var screen: AppScreen = .home
    @Published var selectedMode: LunchMode = .quick
    @Published var restaurants: [Restaurant] = []
    @Published var errorMessage: String?

    /// メインで表示する一番近いお店
    var primaryRestaurant: Restaurant? {
        restaurants.first
    }

    private let placesService = GooglePlacesService()
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// 起動画面からの検索開始
    func startSearch() {
        screen = .searching
        errorMessage = nil

        Task {
            do {
                let coord = try await requestLocation()
                let result = try await placesService.searchNearbyRestaurants(
                    location: coord,
                    mode: selectedMode
                )
                self.restaurants = result
                self.screen = .result
            } catch {
                let nsError = error as NSError

                if nsError.domain == kCLErrorDomain,
                   nsError.code == CLError.denied.rawValue {
                    self.errorMessage = "位置情報の利用が許可されていません。設定アプリで位置情報をオンにしてから、もう一度お試しください。"
                } else if let placesError = error as? PlacesAPIError {
                    self.errorMessage = placesError.localizedDescription
                } else {
                    self.errorMessage = "お店の取得に失敗しました: \(error.localizedDescription)"
                }

                self.restaurants = []
                self.screen = .result
            }
        }
    }

    /// モード変更時に再検索（結果画面のタブ切り替え用）
    func changeModeAndSearch(_ mode: LunchMode) {
        selectedMode = mode
        startSearch()
    }

    // MARK: - 位置情報

    private func requestLocation() async throws -> CLLocationCoordinate2D {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            throw NSError(domain: "Location", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "位置情報の利用が許可されていません。設定アプリから許可してください。"
            ])
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            break
        @unknown default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    // CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        locationContinuation?.resume(returning: coord)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 必要ならここで再リクエストなど
    }
}

// MARK: - Google Places API

final class GooglePlacesService {
    // TODO: 公開リポジトリに上げる場合はキーは埋め込まないように注意
    private let apiKey = "YOUR_API_KEY_HERE"

    struct PlacesResponse: Decodable {
        let results: [PlaceResult]
    }

    struct PlaceResult: Decodable {
        let place_id: String
        let name: String
        let geometry: Geometry
        let rating: Double?
        let user_ratings_total: Int?
        let price_level: Int?
        let opening_hours: OpeningHours?

        struct Geometry: Decodable {
            let location: Location
        }
        struct Location: Decodable {
            let lat: Double
            let lng: Double
        }
        struct OpeningHours: Decodable {
            let open_now: Bool?
        }
    }

    private func parameters(for mode: LunchMode) -> (radius: Int, keyword: String?) {
        switch mode {
        case .quick:
            return (radius: 600, keyword: nil)
        case .relax:
            return (radius: 1000, keyword: "cafe OR restaurant")
        case .cheers:
            return (radius: 800, keyword: "izakaya OR bar OR yakitori")
        }
    }

    func searchNearbyRestaurants(
        location: CLLocationCoordinate2D,
        mode: LunchMode
    ) async throws -> [Restaurant] {
        let (radius, keyword) = parameters(for: mode)

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "location", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "radius", value: "\(radius)"),
            URLQueryItem(name: "type", value: "restaurant"),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let keyword = keyword {
            queryItems.append(URLQueryItem(name: "keyword", value: keyword))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 429 {
            throw PlacesAPIError.quotaExceeded
        }

        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(PlacesResponse.self, from: data)

        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)

        let restaurants: [Restaurant] = decoded.results.compactMap { place in
            let lat = place.geometry.location.lat
            let lng = place.geometry.location.lng
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

            let there = CLLocation(latitude: lat, longitude: lng)
            let distance = Int(here.distance(from: there))
            let walkingMinutes = max(1, Int(round(Double(distance) / 80.0)))

            return Restaurant(
                placeId: place.place_id,
                name: place.name,
                coordinate: coord,
                distanceMeters: distance,
                walkingMinutes: walkingMinutes,
                rating: place.rating ?? 0.0,
                reviewCount: place.user_ratings_total ?? 0,
                priceLevel: place.price_level,
                isOpenNow: place.opening_hours?.open_now ?? false,
                closingTimeText: nil
            )
        }

        return restaurants.sorted { $0.distanceMeters < $1.distanceMeters }
    }
}


// MARK: - ルートビュー

struct RootView: View {
    @StateObject private var viewModel = NearestRestaurantViewModel()
    @StateObject private var purchaseManager = NearestLunchPurchaseManager.shared
    
    var body: some View {
        ZStack {
            switch viewModel.screen {
            case .home:
                HomeView(viewModel: viewModel)
            case .searching:
                SearchingView(mode: viewModel.selectedMode)
            case .result:
                ResultView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut, value: viewModel.screen)
        .environmentObject(purchaseManager)
    }
}

// MARK: - 起動画面

struct HomeView: View {
    @ObservedObject var viewModel: NearestRestaurantViewModel
    @EnvironmentObject var purchaseManager: NearestLunchPurchaseManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("いちばん近いご飯屋さんを\nサクッと見つけよう")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    
                    Text("今いる場所から近いお店を、モードに合わせて提案します。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("モードを選ぶ")
                        .font(.headline)
                    ModePickerView(selected: $viewModel.selectedMode)
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    viewModel.startSearch()
                }) {
                    Text("現在地から探す")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                Text("※ 近くのご飯屋さんを探すために位置情報を使用します。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // ★ ここに実バナーIDを設定
                VStack(spacing: 8) {
                    if purchaseManager.isPremium {
                        Text("広告非表示プランをご利用中です。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        AdBannerView(adUnitID: "ca-app-pub-3517487281025314/9611381269")
                            .frame(height: 50)
                        
                        Button {
                            Task {
                                await purchaseManager.purchaseRemoveAds()
                            }
                        } label: {
                            Text(purchaseManager.isProcessing ? "購入処理中…" : "広告を非表示にする（¥480）")
                                .font(.footnote.bold())
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .disabled(purchaseManager.isProcessing)
                        
                        Button {
                            Task {
                                await purchaseManager.restorePurchases()
                            }
                        } label: {
                            Text("購入を復元する")
                                .font(.footnote)
                        }
                        .disabled(purchaseManager.isProcessing)
                    }
                    
                    if let msg = purchaseManager.purchaseErrorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("近くのご飯屋")
        }
    }
}

// MARK: - 検索中画面

struct SearchingView: View {
    let mode: LunchMode
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.4)
            
            VStack(spacing: 8) {
                Text("近くのご飯屋さんを探しています…")
                    .font(.headline)
                Text("\(mode.displayName)モード")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - 結果画面

struct ResultView: View {
    @ObservedObject var viewModel: NearestRestaurantViewModel
    @EnvironmentObject var purchaseManager: NearestLunchPurchaseManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ModePickerView(selected: $viewModel.selectedMode) { newMode in
                    viewModel.changeModeAndSearch(newMode)
                }
                .padding()
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let msg = viewModel.errorMessage {
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }
                        
                        if let main = viewModel.primaryRestaurant {
                            Text("いちばん近いご飯屋さん")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            RestaurantCardView(restaurant: main, isPrimary: true)
                                .padding(.horizontal)
                        } else if viewModel.errorMessage == nil {
                            Text("近くに条件に合うお店が見つかりませんでした。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        
                        if viewModel.restaurants.count > 1 {
                            Text("徒歩10分以内の他の候補")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(viewModel.restaurants.dropFirst()) { r in
                                RestaurantCardView(restaurant: r, isPrimary: false)
                                    .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 24)
                        
                        VStack(spacing: 8) {
                            if purchaseManager.isPremium {
                                Text("広告非表示プランをご利用中です。")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                AdBannerView(adUnitID: "ca-app-pub-3517487281025314/9611381269")
                                    .frame(height: 50)
                                
                                Button {
                                    Task {
                                        await purchaseManager.purchaseRemoveAds()
                                    }
                                } label: {
                                    Text(purchaseManager.isProcessing ? "購入処理中…" : "広告を非表示にする（¥480）")
                                        .font(.footnote.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .disabled(purchaseManager.isProcessing)
                                
                                Button {
                                    Task {
                                        await purchaseManager.restorePurchases()
                                    }
                                } label: {
                                    Text("購入を復元する")
                                        .font(.footnote)
                                }
                                .disabled(purchaseManager.isProcessing)
                            }
                            
                            if let msg = purchaseManager.purchaseErrorMessage {
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("近くのご飯屋")
        }
    }
}

// MARK: - モードピッカー（チップUI）

struct ModePickerView: View {
    @Binding var selected: LunchMode
    var onChanged: ((LunchMode) -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(LunchMode.allCases) { mode in
                let isSelected = (mode == selected)
                Button {
                    selected = mode
                    onChanged?(mode)
                } label: {
                    VStack(spacing: 4) {
                        Text(mode.displayName)
                            .font(.subheadline.bold())
                        Text(mode.description)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

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

// MARK: - 店カード

struct RestaurantCardView: View {
    let restaurant: Restaurant
    let isPrimary: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(restaurant.name)
                    .font(isPrimary ? .title3.bold() : .headline)
                    .lineLimit(2)
                Spacer()
                Text("徒歩\(restaurant.walkingMinutes)分")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(String(format: "%.1f", restaurant.rating))
                        .font(.subheadline)
                }
                
                Text("(\(restaurant.reviewCount)件)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Divider()
                    .frame(height: 14)
                
                Text(restaurant.priceText)
                    .font(.subheadline)
                
                Spacer()
            }
            
            HStack {
                Text("距離: \(restaurant.distanceText)")
                    .font(.subheadline)
                Spacer()
                Text(restaurant.openStatusText)
                    .font(.subheadline)
                    .foregroundColor(restaurant.isOpenNow ? .green : .red)
            }
            
            Button {
                openInGoogleMaps()
            } label: {
                Text("Googleマップで開く")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: isPrimary ? 8 : 4, x: 0, y: 2)
    }

    private func openInGoogleMaps() {
        let encodedName = restaurant.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encodedName)&query_place_id=\(restaurant.placeId)") {
            openURL(url)
        }
    }
}

// MARK: - プレビュー

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
