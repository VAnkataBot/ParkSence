import Foundation

// MARK: - Output

struct ParkingVerdict {
    let canPark: Bool?
    let message: String
    let notes: [String]
}

// MARK: - Parser

enum ParkingParser {

    // MARK: Class sets

    private static let anchorAllow:    Set<String> = ["parking", "parking_ovrig", "diagonal_parking", "parallel_parking"]
    private static let anchorProhibit: Set<String> = ["no_parking", "no_stopping"]
    private static let anchorLoading:  Set<String> = ["loading_zone"]
    private static var anchorClasses:  Set<String> { anchorAllow.union(anchorProhibit).union(anchorLoading) }

    private static let modifierNotes: [String: String] = [
        "handicap":     "Disabled permit holders only.",
        "ev_charging":  "Electric vehicles (with charging) only.",
        "truck":        "Heavy vehicles (>3.5 t) only.",
        "motorcycle":   "Motorcycles / mopeds only.",
        "trailer":      "Trailers only.",
        "parking_disc": "Parking disc required — set to next half-hour on arrival.",
        "residents":    "Residents/permit holders only.",
    ]

    // MARK: Day map

    private static let dayMap: [String: Int] = [
        "MÅN": 0, "MON": 0,
        "TIS": 1, "TUE": 1,
        "ONS": 2, "WED": 2,
        "TOR": 3, "TORS": 3, "THU": 3,
        "FRE": 4, "FRED": 4, "FRI": 4,
        "LÖR": 5, "SAT": 5,
        "SÖN": 6, "SÖ": 6, "SUN": 6,
    ]
    private static let dayNames: [Int: String] = [
        0: "Mån", 1: "Tis", 2: "Ons", 3: "Tor", 4: "Fre", 5: "Lör", 6: "Sön",
    ]

    // MARK: Regex patterns

    private static let timePattern = #"(\d{1,2}[.:,]?\d{0,2})\s*[-–]\s*(\d{1,2}[.:,]?\d{0,2})"#
    private static let distPattern = #"0\s*[-–]\s*(\d+)\s*M+\b"#
    private static var dayAltPattern: String {
        dayMap.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    // MARK: Normalisation

    private static func norm(_ text: String) -> String {
        SignClassifier.norm(text)
    }

    // MARK: Time parsing

    private static func parseMins(_ s: String) -> Int {
        let clean = s.replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: ",", with: ":")
        let parts = clean.split(separator: ":").map { String($0) }
        let h = Int(parts[0]) ?? 0
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return h * 60 + m
    }

    private static func fmt(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Weekday time range — ignores parenthesised Saturday times and day-specific times.
    private static func weekdayTime(_ text: String) -> (Int, Int)? {
        var t = replacing(text, pattern: distPattern, with: "")
        t = replacing(t, pattern: #"\([^)]*\)"#, with: "")
        t = replacing(t, pattern: #"\b(?:\#(dayAltPattern))\b\s*\d{1,2}[.:,]?\d{0,2}\s*[-–]\s*\d{1,2}[.:,]?\d{0,2}"#, with: "")
        guard let m = firstMatch(t, pattern: timePattern) else { return nil }
        return (parseMins(m[1]), parseMins(m[2]))
    }

    /// Saturday time range — the one in parentheses.
    private static func saturdayTime(_ text: String) -> (Int, Int)? {
        guard let m = firstMatch(text, pattern: #"\(\s*\#(timePattern)\s*\)"#) else { return nil }
        return (parseMins(m[1]), parseMins(m[2]))
    }

    private static func singleDay(_ text: String) -> Int? {
        for (name, idx) in dayMap.sorted(by: { $0.key.count > $1.key.count }) {
            if matches(text, pattern: #"\b\#(NSRegularExpression.escapedPattern(for: name))\b"#) { return idx }
        }
        return nil
    }

    private static func zoneMetres(_ text: String) -> Int? {
        firstMatch(text, pattern: distPattern).flatMap { Int($0[1]) }
    }

    private static func isOvrigTid(_ text: String) -> Bool {
        text.contains("ÖVRIG TID") || text.contains("OVRIG TID")
    }

    // MARK: Interval helpers

    private static func intervalsForAnchor(_ modText: String, weekday: Int, anchorCls: String) -> [(Int, Int)] {
        if let day = singleDay(modText) {
            let pat = #"\b(?:\#(dayAltPattern))\b\s*\#(timePattern)"#
            if let m = firstMatch(modText, pattern: pat), weekday == day, !anchorAllow.contains(anchorCls) {
                return [(parseMins(m[1]), parseMins(m[2]))]
            }
        }
        let tWd  = weekdayTime(modText)
        let tSat = saturdayTime(modText)
        if tWd == nil && tSat == nil { return [] }
        if weekday == 6 { return [] }
        if weekday == 5 { return tSat.map { [$0] } ?? [] }
        return tWd.map { [$0] } ?? []
    }

    private static func dayProhibitionIntervals(_ modText: String, weekday: Int) -> [(Int, Int)] {
        guard let day = singleDay(modText), day == weekday else { return [] }
        let pat = #"\b(?:\#(dayAltPattern))\b\s*\#(timePattern)"#
        guard let m = firstMatch(modText, pattern: pat) else { return [] }
        return [(parseMins(m[1]), parseMins(m[2]))]
    }

    private static func inAny(_ intervals: [(Int, Int)], _ minutes: Int) -> Bool {
        intervals.contains { $0.0 <= minutes && minutes < $0.1 }
    }

    private static func complement(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
        guard !intervals.isEmpty else { return [] }
        let merged = intervals.sorted { $0.0 < $1.0 }
        var result: [(Int, Int)] = []
        var cursor = 0
        for (s, e) in merged {
            if cursor < s { result.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if cursor < 1440 { result.append((cursor, 1440)) }
        return result
    }

    // MARK: Grouping

    private struct AnchorGroup {
        let anchorCls: String
        let anchorText: String
        let modText: String
        let mods: [SignData]
    }

    private static func groupSigns(_ signs: [SignData]) -> [AnchorGroup] {
        var groups: [AnchorGroup] = []
        var currentMods: [SignData] = []

        for sign in signs {
            if anchorClasses.contains(sign.signClass) {
                groups.append(AnchorGroup(
                    anchorCls:  sign.signClass,
                    anchorText: norm(sign.text),
                    modText:    currentMods.map { norm($0.text) }.joined(separator: " "),
                    mods:       currentMods
                ))
                currentMods = []
            } else {
                currentMods.append(sign)
            }
        }

        if !currentMods.isEmpty, !groups.isEmpty {
            let last = groups.removeLast()
            let extra = currentMods.map { norm($0.text) }.joined(separator: " ")
            groups.append(AnchorGroup(
                anchorCls:  last.anchorCls,
                anchorText: last.anchorText,
                modText:    [last.modText, extra].filter { !$0.isEmpty }.joined(separator: " "),
                mods:       last.mods + currentMods
            ))
        }
        return groups
    }

    private static func buildNotes(_ group: AnchorGroup) -> [String] {
        var notes: [String] = []
        let combined = group.anchorText + " " + group.modText

        if let n = modifierNotes[group.anchorCls] { notes.append(n) }
        for mod in group.mods {
            if let n = modifierNotes[mod.signClass], !notes.contains(n) { notes.append(n) }
        }
        if let m = zoneMetres(combined)  { notes.append("Reserved zone: 0–\(m) m.") }
        if combined.contains("AVGIFT") || combined.contains("TAXA") {
            notes.append("Paid parking — check meter/app for tariff.")
        }
        if combined.contains("PARKERING.STOCKHOLM") || combined.contains("BETALA DIGITALT") {
            notes.append("Pay digitally — parkering.stockholm.se or Stockholm parking app.")
        }
        if combined.contains("BOENDE") || combined.contains("TILLSTÅND") || combined.contains("TILLSTAND") {
            let day = singleDay(combined)
            notes.append(day == 6 ? "Sunday: residents/permit holders only." : "Residents/permit holders only.")
        }
        if combined.contains("P-SKIVA") || combined.contains("PSKIVA") {
            notes.append("Parking disc required.")
        }
        return notes
    }

    // MARK: Public API

    /// Parse a list of signs (bottom-to-top order) into a parking verdict.
    static func parse(_ signs: [SignData], now: Date = Date()) -> ParkingVerdict {
        guard !signs.isEmpty else {
            return ParkingVerdict(canPark: nil, message: "No signs detected.", notes: [])
        }

        let cal     = Calendar.current
        let weekday = (cal.component(.weekday, from: now) + 5) % 7  // Mon=0 … Sun=6
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        var groups = groupSigns(signs)

        if groups.isEmpty {
            let vehicleMods:  Set<String> = ["handicap", "ev_charging", "motorcycle", "truck", "trailer", "residents", "parking_disc"]
            let modifierOnly: Set<String> = ["exception_plate", "distance_plate", "arrow_plate", "payment_info", "parking_disc", "unknown"]
            if signs.contains(where: { vehicleMods.contains($0.signClass) || modifierOnly.contains($0.signClass) }) {
                groups = [AnchorGroup(
                    anchorCls:  "parking",
                    anchorText: "",
                    modText:    signs.map { norm($0.text) }.joined(separator: " "),
                    mods:       signs
                )]
            } else {
                return ParkingVerdict(canPark: nil, message: "No anchor sign found.", notes: [])
            }
        }

        // Collect restricted intervals (needed for övrig tid complement)
        var allRestricted: [(Int, Int)] = []
        struct Evaluated {
            let cls: String; let modText: String; let anchorText: String
            let notes: [String]; let ovrig: Bool; let intervals: [(Int, Int)]
        }
        let evaluated: [Evaluated] = groups.map { g in
            let ovrig     = g.anchorCls == "parking_ovrig" || isOvrigTid(g.anchorText + " " + g.modText)
            let intervals = intervalsForAnchor(g.modText, weekday: weekday, anchorCls: g.anchorCls)
            if !ovrig && (anchorProhibit.contains(g.anchorCls) || anchorLoading.contains(g.anchorCls)) {
                allRestricted += intervals.isEmpty ? [(0, 1440)] : intervals
            }
            return Evaluated(cls: g.anchorCls, modText: g.modText, anchorText: g.anchorText,
                             notes: buildNotes(g), ovrig: ovrig, intervals: intervals)
        }

        var verdict: Bool? = nil
        var verdictMsg = ""
        var allNotes: [String] = []

        for g in evaluated {
            allNotes += g.notes

            // Övrig tid
            if g.ovrig && anchorAllow.contains(g.cls) {
                let free = complement(allRestricted)
                if allRestricted.isEmpty {
                    verdict = true; verdictMsg = "Parking allowed (no restrictions)."
                } else if inAny(free, minutes) {
                    verdict = true; verdictMsg = "Parking allowed — övrig tid (outside restricted hours)."
                } else {
                    verdict = false; verdictMsg = "No parking now — restriction active."
                }
                continue
            }

            // Loading zone
            if anchorLoading.contains(g.cls) {
                if g.intervals.isEmpty || inAny(g.intervals, minutes) {
                    verdict = false; verdictMsg = "Loading zone — no parking now."
                } else if verdict != true {
                    verdict = true; verdictMsg = "Outside loading zone hours — parking allowed."
                }
                continue
            }

            // Prohibit
            if anchorProhibit.contains(g.cls) {
                if g.intervals.isEmpty {
                    verdict = false; verdictMsg = "No stopping/parking at all times."
                } else if inAny(g.intervals, minutes) {
                    let day = singleDay(g.modText)
                    if let day, let name = dayNames[day] {
                        verdictMsg = "No parking — street cleaning \(name) \(fmt(g.intervals[0].0))–\(fmt(g.intervals[0].1))."
                    } else {
                        verdictMsg = "Parking prohibited \(fmt(g.intervals[0].0))–\(fmt(g.intervals[0].1))."
                    }
                    verdict = false
                } else if verdict != true {
                    verdict = true; verdictMsg = "Outside restricted hours — parking allowed."
                }
                continue
            }

            // Allow
            if anchorAllow.contains(g.cls) && !g.ovrig {
                let prohib = dayProhibitionIntervals(g.modText, weekday: weekday)
                if !prohib.isEmpty && inAny(prohib, minutes) {
                    let name = dayNames[weekday] ?? ""
                    verdict = false
                    verdictMsg = "No parking — street cleaning \(name) \(fmt(prohib[0].0))–\(fmt(prohib[0].1))."
                    continue
                }
                let tWd  = weekdayTime(g.modText)
                let tSat = saturdayTime(g.modText)
                if g.intervals.isEmpty && tWd == nil && tSat == nil {
                    if verdict == nil { verdict = true; verdictMsg = "Parking allowed (no time restriction)." }
                } else if inAny(g.intervals, minutes) {
                    if verdict != false {
                        let lbl = g.intervals.first.map { "\(fmt($0.0))–\(fmt($0.1))" } ?? ""
                        verdict = true; verdictMsg = "Parking allowed\(lbl.isEmpty ? "" : " — \(lbl)")."
                    }
                } else {
                    if verdict != false { verdict = false; verdictMsg = "Outside allowed parking hours." }
                }
            }
        }

        if verdict == nil { verdictMsg = "Could not determine parking rules — check signs manually." }
        return ParkingVerdict(
            canPark: verdict,
            message: verdictMsg,
            notes: Array(NSOrderedSet(array: allNotes)) as! [String]
        )
    }

    // MARK: Regex helpers

    private static func matches(_ text: String, pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }

    /// Returns capture groups [0: full match, 1: group1, 2: group2, ...] or nil.
    private static func firstMatch(_ text: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0 ..< m.numberOfRanges).map { i -> String in
            guard let r = Range(m.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
