import SwiftUI

@main
struct ParkSenceApp: App {
    @StateObject private var session = UserSession.shared

    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                MainView()
                    .environmentObject(session)
            } else {
                LoginView()
                    .environmentObject(session)
            }
        }
    }
}
