// AdRequestFactory.swift
#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// ATT 不許可時などに使うプライバシーフラグを集約
public enum AdPrivacy {
    /// 不許可なら true（= npa=1 を付ける）
    public static var useNonPersonalizedAds: Bool = false

    // 将来拡張用に置き場だけ確保（必要になったら使ってください）
    // public static var tagForUnderAgeOfConsent: Bool?
    // public static var tagForChildDirectedTreatment: Bool?
    // public static var maxAdContentRating: String? // "G"/"PG"/"T"/"MA"
}

/// AdMob のリクエスト生成を一箇所に集約
public enum AdRequestFactory {

    /// 標準の広告リクエスト（npa対応込み）
    public static func make() -> Request {
        let req = Request()

        if AdPrivacy.useNonPersonalizedAds {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            req.register(extras)
        }

        // ここに将来のパラメータ適用を追加していくと安全
        // if let rating = AdPrivacy.maxAdContentRating {
        //     RequestConfiguration.shared.maxAdContentRating = rating
        // }

        return req
    }
}

/// 既存コード互換のヘルパー（置き換えやすさ重視）
public func makeAdRequest() -> Request {
    AdRequestFactory.make()
}

#endif
