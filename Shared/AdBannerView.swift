import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct AdBannerView: UIViewRepresentable {
    let adUnitID: String
    func makeUIView(context: Context) -> GADBannerView {
        let v = GADBannerView(adSize: GADAdSizeBanner)
        v.adUnitID = adUnitID
        v.rootViewController = UIApplication.shared.windows.first?.rootViewController
        v.load(GADRequest())
        return v
    }
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
#else
struct AdBannerView: View {
    let adUnitID: String
    var body: some View { EmptyView() } // SDKが無いターゲットでは何も表示しない
}
#endif
