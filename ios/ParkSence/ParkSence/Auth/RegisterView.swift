import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var session: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var email           = ""
    @State private var password        = ""
    @State private var selectedVehicle = "car"
    @State private var isDisabled      = false
    @State private var hasResident     = false
    @State private var residentZone    = ""
    @State private var error           = ""
    @State private var loading         = false

    private let vehicles: [(id: String, label: String, icon: String)] = [
        ("car",        "Car",   "car.fill"),
        ("motorcycle", "Moto",  "motorcycle"),
        ("ev",         "EV",    "bolt.car.fill"),
        ("truck",      "Truck", "truck.box.fill"),
    ]

    var body: some View {
        ZStack {
            Color(hex: "1a1c24").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create account")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Set up your vehicle profile for accurate verdicts")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // Account card
                    SectionCard {
                        PSTextField(placeholder: "Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        PSTextField(placeholder: "Password (min. 6 characters)", text: $password, isSecure: true)
                    }

                    // Vehicle card
                    SectionCard {
                        Text("Vehicle type")
                            .font(.footnote.uppercaseSmallCaps())
                            .foregroundColor(.white.opacity(0.5))

                        HStack(spacing: 8) {
                            ForEach(vehicles, id: \.id) { v in
                                VehicleButton(
                                    icon: v.icon,
                                    label: v.label,
                                    selected: selectedVehicle == v.id
                                ) { selectedVehicle = v.id }
                            }
                        }

                        Divider().background(Color.white.opacity(0.1))

                        PermitToggle(icon: "figure.roll", label: "Disability permit", isOn: $isDisabled)

                        PermitToggle(icon: "house.fill", label: "Resident permit", isOn: $hasResident)

                        if hasResident {
                            PSTextField(placeholder: "Zone (e.g. A, B4, Östermalm)", text: $residentZone)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: hasResident)

                    if !error.isEmpty {
                        Text(error)
                            .foregroundColor(Color(hex: "F44336"))
                            .font(.footnote)
                    }

                    PSButton(title: "Create Account", loading: loading) {
                        doRegister()
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func doRegister() {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { error = "Email is required"; return }
        guard password.count >= 6 else { error = "Password must be at least 6 characters"; return }

        loading = true
        error = ""

        Task {
            do {
                let (token, profile) = try await ApiClient.shared.register(
                    email: trimmed,
                    password: password,
                    vehicleType: selectedVehicle,
                    isDisabled: isDisabled,
                    hasResidentPermit: hasResident,
                    residentZone: residentZone.trimmingCharacters(in: .whitespaces)
                )
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

// MARK: - Sub-components

private struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct VehicleButton: View {
    let icon: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color(hex: "ff4b4b") : Color.white.opacity(0.08))
            .foregroundColor(selected ? .white : .white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct PermitToggle: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(.white.opacity(0.7))
                Text(label).foregroundColor(.white).font(.subheadline)
            }
        }
        .tint(Color(hex: "ff4b4b"))
    }
}
