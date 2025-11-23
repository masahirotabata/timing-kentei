import Foundation
import StoreKit

@MainActor
final class IAPManager: NSObject, ObservableObject {
    static let shared = IAPManager()

    // App Store Connect で登録する Product ID
    enum ProductID: String, CaseIterable {
        case removeAds = "remove_ads"
        case premium   = "premium"
        case skinNeon  = "skin_neon"
        case skinGold  = "skin_gold"
    }

    @Published var available: [Product] = []
    @Published var purchased: Set<String> = []

    func loadProducts() async {
        do {
            let ids = Set(ProductID.allCases.map{$0.rawValue})
            available = try await Product.products(for: ids)
            try await refreshEntitlements()
        } catch {
            print("loadProducts error:", error)
        }
    }

    func refreshEntitlements() async throws {
        purchased.removeAll()
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result {
                purchased.insert(txn.productID)
            }
        }
    }

    func buy(productId: String, completion: @escaping (Bool)->Void) {
        Task {
            do {
                guard let product = available.first(where: {$0.id == productId}) else {
                    // 最初は製品取得前の簡易フォールバック（モック成功）
                    completion(true); return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let txn) = verification {
                        await txn.finish()
                        try? await refreshEntitlements()
                        completion(true)
                    } else { completion(false) }
                default:
                    completion(false)
                }
            } catch {
                completion(false)
            }
        }
    }

    func restore(completion: @escaping (Bool)->Void) {
        Task {
            do {
                try await AppStore.sync()
                try await refreshEntitlements()
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}
