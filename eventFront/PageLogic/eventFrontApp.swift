import SwiftUI
import Stripe

@main
struct eventFrontApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    init() {
        StripeAPI.defaultPublishableKey = "pk_test_51RcVeBBU1Fa59mBKHvngFVDwq8gBiZ863TKO6okEHBj28VjLiYAUQ5OhDs0k1WEyfqXRmtziurmLYBqlQfyOOl6C007EKiWppc"

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = UIColor.systemGreen
        tabBar.unselectedItemTintColor = UIColor.systemGray
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
