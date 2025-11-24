// AppMain.swift
import SwiftUI
import UIKit

@main
struct KazuLazerApp: App {

    // AppDelegate を紐付け（ATT + AdMob 初期化はそちらで実施）
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // 数レーザーのメインビュー
            ContentView_Kazulazer()
        }
    }
}
