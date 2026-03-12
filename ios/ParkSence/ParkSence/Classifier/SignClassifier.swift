import Foundation

// MARK: - Models

struct SignData {
    let text: String
    let detectorLabel: String
    var signClass: String = "unknown"
}

// MARK: - Classifier

enum SignClassifier {

    // MARK: Normalisation

    static func norm(_ text: String) -> String {
        var t = text.uppercased()
        t = t.replacing(#/[|\\]/#, with: "")
        t = t.replacing(#/[~_]/#, with: "-")
        t = t.replacing(#/[^\wÅÄÖåäö\s:()\-–.,/]/#, with: "")
        return t.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: OCR rules

    private struct OcrRule {
        let patterns: [String]
        let cls: String
    }

    private static let ocrRules: [OcrRule] = [
        OcrRule(patterns: ["STOPFÖRBUD"],                       cls: "no_stopping"),
        OcrRule(patterns: ["STOP FÖRBUD"],                      cls: "no_stopping"),
        OcrRule(patterns: ["PARKERING FÖRBJUDEN"],              cls: "no_parking"),
        OcrRule(patterns: ["PARKERINGSFÖRBUD"],                 cls: "no_parking"),
        OcrRule(patterns: ["LASTPLATS"],                        cls: "loading_zone"),
        OcrRule(patterns: ["LAST PLATS"],                       cls: "loading_zone"),
        OcrRule(patterns: ["ÖVRIG TID"],                        cls: "parking_ovrig"),
        OcrRule(patterns: ["OVRIG TID"],                        cls: "parking_ovrig"),
        OcrRule(patterns: ["SNEDPARKERING"],                    cls: "diagonal_parking"),
        OcrRule(patterns: ["PARALLELLPARKERING"],               cls: "parallel_parking"),
        OcrRule(patterns: ["PARALELLPARKERING"],                cls: "parallel_parking"),
        OcrRule(patterns: ["BOENDE"],                           cls: "residents"),
        OcrRule(patterns: ["TILLSTÅND"],                        cls: "residents"),
        OcrRule(patterns: ["TILLSTAND"],                        cls: "residents"),
        OcrRule(patterns: ["BETALA DIGITALT"],                  cls: "payment_info"),
        OcrRule(patterns: ["PARKERING.STOCKHOLM"],              cls: "payment_info"),
        OcrRule(patterns: ["P-SKIVA"],                          cls: "parking_disc"),
        OcrRule(patterns: ["PSKIVA"],                           cls: "parking_disc"),
        OcrRule(patterns: ["P SKIVA"],                          cls: "parking_disc"),
        OcrRule(patterns: [#"0\s*[-–]\s*\d+\s*M\b"#],          cls: "distance_plate"),
        OcrRule(patterns: ["TORS",  #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["FRED",  #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["MÅN",   #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["TIS",   #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["ONS",   #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["LÖR",   #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["SÖN",   #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["AVGIFT",#"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
        OcrRule(patterns: ["TAXA",  #"\d+\s*[-–]\s*\d+"#],     cls: "exception_plate"),
    ]

    // MARK: Label fallback

    private static let labelMap: [(keyword: String, cls: String)] = [
        ("no stopping",         "no_stopping"),
        ("no parking",          "no_parking"),
        ("loading zone",        "loading_zone"),
        ("lastplats",           "loading_zone"),
        ("handicap",            "handicap"),
        ("wheelchair",          "handicap"),
        ("electric vehicle",    "ev_charging"),
        ("charging",            "ev_charging"),
        ("motorcycle",          "motorcycle"),
        ("diagonal",            "diagonal_parking"),
        ("parallel",            "parallel_parking"),
        ("truck",               "truck"),
        ("trailer parking sign","trailer"),
        ("parking disc",        "parking_disc"),
        ("arrow",               "arrow_plate"),
        ("residents",           "residents"),
        ("blue parking sign",   "parking"),
        ("parking sign",        "parking"),
        ("parking",             "parking"),
    ]

    private static let vehicleKeywords: Set<String> = [
        "handicap", "wheelchair", "electric vehicle", "charging",
        "motorcycle", "truck", "trailer", "residents",
    ]

    // MARK: Public API

    static func classify(_ sign: SignData) -> String {
        let text  = norm(sign.text)
        let label = sign.detectorLabel.lowercased()

        // 1. OCR rules — all patterns must match
        for rule in ocrRules {
            let allMatch = rule.patterns.allSatisfy { pattern in
                (try? NSRegularExpression(pattern: pattern))
                    .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
                    ?? text.contains(pattern)
            }
            if allMatch { return rule.cls }
        }

        // 2. Bare time plate (short text with digit–digit)
        if matches(text, pattern: #"^\s*\d{1,2}\s*[-–]\s*\d{1,2}"#), text.count < 25 {
            return "exception_plate"
        }

        // 3. Detector label fallback
        if (label.contains("parking sign") || label.contains("parking")), !text.isEmpty {
            for kw in vehicleKeywords where label.contains(kw) { return "parking" }
        }
        for (kw, cls) in labelMap where label.contains(kw) { return cls }

        // 4. Any digit–digit in OCR
        if matches(text, pattern: #"\d+\s*[-–]\s*\d+"#) { return "exception_plate" }

        return "unknown"
    }

    static func classifyAll(_ signs: [SignData]) -> [SignData] {
        signs.map { var s = $0; s.signClass = classify(s); return s }
    }

    // MARK: Helpers

    private static func matches(_ text: String, pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }
}
