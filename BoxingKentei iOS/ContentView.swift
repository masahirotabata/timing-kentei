// BoxingKentei iOS / ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        RootViewControllerWrapper()
            .ignoresSafeArea(.all, edges: .bottom)
    }
}

// HomeController(UIKit) を SwiftUI で表示する薄いラッパ
struct RootViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HomeController {
        HomeController()
    }
    func updateUIViewController(_ uiViewController: HomeController, context: Context) {}
}
