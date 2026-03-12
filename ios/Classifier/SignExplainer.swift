import Foundation

struct SignInfo {
    let icon: String
    let name: String
    let description: String
}

enum SignExplainer {

    private static let explanations: [String: SignInfo] = [
        "parking": SignInfo(
            icon: "🅿️", name: "Parking sign",
            description: "Blue P sign — marks where parking is allowed. Any time/day plates below it define when."
        ),
        "parking_ovrig": SignInfo(
            icon: "🅿️", name: "Parking — övrig tid",
            description: "Blue P with 'övrig tid' (other times) — parking is allowed during hours NOT covered by other restrictions on the same pole."
        ),
        "diagonal_parking": SignInfo(
            icon: "🅿️", name: "Diagonal parking",
            description: "Park at an angle (roughly 45°) to the kerb, not parallel. Usually means more cars fit in the space."
        ),
        "parallel_parking": SignInfo(
            icon: "🅿️", name: "Parallel parking",
            description: "Park parallel to the kerb, bumper-to-bumper with other cars."
        ),
        "no_parking": SignInfo(
            icon: "🚫", name: "No parking",
            description: "Parking is forbidden. You may stop briefly to drop off passengers or load/unload, but you cannot leave the vehicle."
        ),
        "no_stopping": SignInfo(
            icon: "⛔", name: "No stopping",
            description: "You cannot stop here at all — not even briefly. Stricter than no parking."
        ),
        "loading_zone": SignInfo(
            icon: "🟡", name: "Loading zone (Lastplats)",
            description: "This space is reserved for loading and unloading only. Parking is not allowed. Usually time-limited."
        ),
        "exception_plate": SignInfo(
            icon: "🕐", name: "Time/day plate",
            description: "Specifies when the rule above it applies. E.g. '7–19' means Mon–Fri 07:00–19:00. Times in parentheses '(11–17)' apply on Saturdays."
        ),
        "distance_plate": SignInfo(
            icon: "📏", name: "Zone extent plate",
            description: "Shows how far the rule above applies, e.g. '0–15 m' means from this sign up to 15 metres ahead."
        ),
        "handicap": SignInfo(
            icon: "♿", name: "Disabled parking",
            description: "Reserved for vehicles displaying a valid disabled parking permit (blue badge)."
        ),
        "ev_charging": SignInfo(
            icon: "⚡", name: "Electric vehicle charging",
            description: "Reserved for electric vehicles that are actively charging. Regular vehicles cannot park here."
        ),
        "motorcycle": SignInfo(
            icon: "🏍️", name: "Motorcycle parking",
            description: "Reserved for motorcycles and mopeds only."
        ),
        "truck": SignInfo(
            icon: "🚛", name: "Heavy vehicle parking",
            description: "Reserved for heavy vehicles (over 3.5 tonnes). Regular cars cannot park here."
        ),
        "trailer": SignInfo(
            icon: "🚌", name: "Trailer parking",
            description: "Reserved for vehicles towing trailers or caravans."
        ),
        "parking_disc": SignInfo(
            icon: "🕐", name: "Parking disc required",
            description: "You must place a parking disc (P-skiva) on your dashboard set to the next half-hour when you arrive. Available free at most Swedish petrol stations."
        ),
        "residents": SignInfo(
            icon: "🏠", name: "Residents only",
            description: "Reserved for local residents or permit holders (boende/tillstånd). You need a valid area permit to park here."
        ),
        "payment_info": SignInfo(
            icon: "💳", name: "Payment information",
            description: "Shows how to pay for parking — usually refers to the Stockholm parking app or parkering.stockholm.se. No physical meter."
        ),
        "arrow_plate": SignInfo(
            icon: "➡️", name: "Direction arrow",
            description: "Shows which direction the rule above applies — left, right, or both ways from this sign."
        ),
        "unknown": SignInfo(
            icon: "❓", name: "Unrecognised sign",
            description: "Could not determine what this sign means. Check it manually."
        ),
    ]

    static func explain(_ signClass: String) -> SignInfo {
        explanations[signClass] ?? SignInfo(icon: "❓", name: signClass, description: "Unknown sign type.")
    }
}
