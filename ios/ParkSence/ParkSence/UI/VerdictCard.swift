import SwiftUI

struct VerdictCard: View {
    let result: ParkingResult
    let onScanAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Verdict banner
                VStack(spacing: 8) {
                    Text(verdictIcon)
                        .font(.system(size: 44))
                    Text(verdictTitle)
                        .font(.title3.bold())
                        .foregroundColor(verdictColor)
                    Text(result.message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(verdictColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(verdictColor.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Notes
                if !result.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONDITIONS")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            HStack(alignment: .top, spacing: 10) {
                                Text("ℹ️").font(.footnote)
                                Text(note)
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Signs
                if !result.signs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DETECTED SIGNS")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(result.signs.enumerated()), id: \.offset) { _, sign in
                            Text(sign)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Scan again button
                PSButton(title: "Scan Again") { onScanAgain() }
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(hex: "0D0D12").ignoresSafeArea())
    }

    private var verdictIcon: String {
        switch result.canPark {
        case true:  return "✅"
        case false: return "🚫"
        case nil:   return "⚠️"
        }
    }
    private var verdictTitle: String {
        switch result.canPark {
        case true:  return "You can park here"
        case false: return "No parking here"
        case nil:   return "Could not determine"
        }
    }
    private var verdictColor: Color {
        switch result.canPark {
        case true:  return Color(hex: "4CAF50")
        case false: return Color(hex: "F44336")
        case nil:   return Color(hex: "FF9800")
        }
    }
}
