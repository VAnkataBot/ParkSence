import Foundation
import UIKit

// MARK: - Models

struct ParkingResult {
    let canPark: Bool?
    let message: String
    let notes: [String]
    let signs: [String]
}

struct UserProfile: Codable {
    let id: Int
    let email: String
    let vehicleType: String
    let isDisabled: Bool
    let hasResidentPermit: Bool
    let residentZone: String

    enum CodingKeys: String, CodingKey {
        case id, email
        case vehicleType       = "vehicle_type"
        case isDisabled        = "is_disabled"
        case hasResidentPermit = "has_resident_permit"
        case residentZone      = "resident_zone"
    }
}

// MARK: - Client

final class ApiClient {
    static let shared = ApiClient()
    private init() {}

    var serverUrl = "http://192.168.68.101:8000"
    var authToken: String?

    // MARK: Auth

    func login(email: String, password: String) async throws -> (String, UserProfile) {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await post(path: "/api/auth/login", json: body)
        return try parseAuthResponse(data)
    }

    func register(
        email: String,
        password: String,
        vehicleType: String,
        isDisabled: Bool,
        hasResidentPermit: Bool,
        residentZone: String
    ) async throws -> (String, UserProfile) {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "vehicle_type": vehicleType,
            "is_disabled": isDisabled,
            "has_resident_permit": hasResidentPermit,
            "resident_zone": residentZone,
        ]
        let data = try await post(path: "/api/auth/register", json: body, expectedCode: 201)
        return try parseAuthResponse(data)
    }

    func updateProfile(
        vehicleType: String,
        isDisabled: Bool,
        hasResidentPermit: Bool,
        residentZone: String
    ) async throws -> UserProfile {
        let body: [String: Any] = [
            "vehicle_type": vehicleType,
            "is_disabled": isDisabled,
            "has_resident_permit": hasResidentPermit,
            "resident_zone": residentZone,
        ]
        let data = try await put(path: "/api/auth/me", json: body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return try parseUserProfile(json)
    }

    // MARK: Analysis

    func analyze(image: UIImage, dayName: String, timeStr: String) async throws -> ParkingResult {
        let jpeg = resizedJpeg(image)
        let boundary = "----ParkSenseBoundary"
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        // image field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"sign.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n")

        // day field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"day\"\r\n\r\n")
        append(dayName)
        append("\r\n")

        // time field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"time\"\r\n\r\n")
        append(timeStr)
        append("\r\n")

        append("--\(boundary)--\r\n")

        let data = try await request(
            path: "/api/analyze",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            expectedCode: 200,
            timeout: 90
        )
        return try parseResult(data)
    }

    // MARK: HTTP helpers

    private func post(path: String, json: [String: Any], expectedCode: Int = 200) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        return try await request(
            path: path,
            method: "POST",
            body: body,
            contentType: "application/json",
            expectedCode: expectedCode
        )
    }

    private func put(path: String, json: [String: Any]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        return try await request(
            path: path,
            method: "PUT",
            body: body,
            contentType: "application/json",
            expectedCode: 200
        )
    }

    private func request(
        path: String,
        method: String,
        body: Data,
        contentType: String,
        expectedCode: Int,
        timeout: TimeInterval = 30
    ) async throws -> Data {
        guard let url = URL(string: "\(serverUrl)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard code == expectedCode else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw NSError(domain: "ApiClient", code: code, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return data
    }

    // MARK: Parsers

    private func parseAuthResponse(_ data: Data) throws -> (String, UserProfile) {
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let token = json["access_token"] as? String,
              let userJson = json["user"] as? [String: Any] else {
            throw NSError(domain: "ApiClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid auth response"])
        }
        return (token, try parseUserProfile(userJson))
    }

    private func parseUserProfile(_ json: [String: Any]) throws -> UserProfile {
        UserProfile(
            id: json["id"] as? Int ?? 0,
            email: json["email"] as? String ?? "",
            vehicleType: json["vehicle_type"] as? String ?? "car",
            isDisabled: json["is_disabled"] as? Bool ?? false,
            hasResidentPermit: json["has_resident_permit"] as? Bool ?? false,
            residentZone: json["resident_zone"] as? String ?? ""
        )
    }

    private func parseResult(_ data: Data) throws -> ParkingResult {
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let canPark: Bool? = json["can_park"].flatMap {
            if $0 is NSNull { return nil }
            return $0 as? Bool
        }

        func parseStringArray(_ key: String) -> [String] {
            guard let arr = json[key] as? [Any] else { return [] }
            return arr.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let obj = item as? [String: Any] {
                    let text = obj["text"] as? String ?? ""
                    let desc = obj["description"] as? String ?? ""
                    if !text.isEmpty && !desc.isEmpty { return "\(text) - \(desc)" }
                    return desc.isEmpty ? text : desc
                }
                return nil
            }.filter { !$0.isEmpty }
        }

        return ParkingResult(
            canPark: canPark,
            message: json["message"] as? String ?? "",
            notes: parseStringArray("notes"),
            signs: parseStringArray("signs")
        )
    }

    // MARK: Image helpers

    private func resizedJpeg(_ image: UIImage, maxDim: CGFloat = 1024, quality: CGFloat = 0.85) -> Data {
        let size = image.size
        let scale = min(1, maxDim / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality) ?? Data()
    }
}
