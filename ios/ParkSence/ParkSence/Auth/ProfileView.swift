import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVehicle = "car"
    @State private var isDisabled      = false
    @State private var hasResident     = false
    @State private var residentZone    = ""
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

                    // Account card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account")
                            .font(.footnote.uppercaseSmallCaps())
                            .foregroundColor(.white.opacity(0.5))
                        Text(session.profile?.email ?? "")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Vehicle card
                    VStack(alignment: .leading, spacing: 12) {
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

                        Toggle(isOn: $isDisabled) {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.roll")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Disability permit").foregroundColor(.white).font(.subheadline)
                            }
                        }.tint(Color(hex: "ff4b4b"))

                        Toggle(isOn: $hasResident) {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Resident permit").foregroundColor(.white).font(.subheadline)
                            }
                        }.tint(Color(hex: "ff4b4b"))

                        if hasResident {
                            PSTextField(placeholder: "Zone (e.g. A, B4, Östermalm)", text: $residentZone)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .animation(.easeInOut(duration: 0.2), value: hasResident)

                    // Save button
                    PSButton(title: "Save Changes", loading: loading) {
                        doSave()
                    }

                    // Sign out
                    Button {
                        session.logout()
                    } label: {
                        Text("Sign Out")
                            .foregroundColor(Color(hex: "F44336"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFromSession() }
    }

    private func loadFromSession() {
        guard let p = session.profile else { return }
        selectedVehicle = p.vehicleType
        isDisabled      = p.isDisabled
        hasResident     = p.hasResidentPermit
        residentZone    = p.residentZone
    }

    private func doSave() {
        loading = true
        Task {
            do {
                let updated = try await ApiClient.shared.updateProfile(
                    vehicleType: selectedVehicle,
                    isDisabled: isDisabled,
                    hasResidentPermit: hasResident,
                    residentZone: residentZone.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run {
                    session.updateProfile(updated)
                    loading = false
                    dismiss()
                }
            } catch {
                await MainActor.run { loading = false }
            }
        }
    }
}

// MARK: - Sub-components

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
