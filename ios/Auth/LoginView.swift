import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: UserSession

    @State private var email    = ""
    @State private var password = ""
    @State private var error    = ""
    @State private var loading  = false
    @State private var goRegister = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0D12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {

                        // Logo
                        VStack(spacing: 8) {
                            Text("🅿")
                                .font(.system(size: 64))
                            Text("ParkSence")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Text("Know before you park")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 60)

                        // Form card
                        VStack(spacing: 16) {
                            PSTextField(placeholder: "Email", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            PSTextField(placeholder: "Password", text: $password, isSecure: true)

                            if !error.isEmpty {
                                Text(error)
                                    .foregroundColor(Color(hex: "F44336"))
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            PSButton(title: "Sign In", loading: loading) {
                                doLogin()
                            }
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)

                        // Register link
                        Button {
                            goRegister = true
                        } label: {
                            Text("Don't have an account? ")
                                .foregroundColor(.white.opacity(0.5))
                            + Text("Register")
                                .foregroundColor(Color(hex: "4CAF50"))
                        }
                        .font(.subheadline)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationDestination(isPresented: $goRegister) {
                RegisterView()
            }
        }
    }

    private func doLogin() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !password.isEmpty else {
            error = "Please fill in all fields"; return
        }
        loading = true
        error = ""

        Task {
            do {
                let (token, profile) = try await ApiClient.shared.login(email: trimmed, password: password)
                await MainActor.run { session.save(token: token, profile: profile) }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}
