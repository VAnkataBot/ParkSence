import SwiftUI

@main
struct ParkSenseApp: App {
    @StateObject private var session = UserSession.shared

    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                // Phase 2 will replace this placeholder with MainView
                Text("Camera coming in Phase 3")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: "0D0D12"))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink("Profile") {
                                ProfileView()
                            }
                        }
                    }
            } else {
                LoginView()
            }
        }
    }
}
