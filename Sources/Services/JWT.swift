import CryptoKit
import Foundation

enum JWTError: LocalizedError {
  case badKey
  var errorDescription: String? {
    switch self {
    case .badKey: return "Clé .p8 invalide (format PEM attendu)."
    }
  }
}

enum JWT {
  /// Génère un token App Store Connect (ES256, valable 15 min).
  static func appStoreConnect(issuerId: String, keyId: String, p8PEM: String) throws -> String {
    let header: [String: Any] = ["alg": "ES256", "kid": keyId, "typ": "JWT"]
    let now = Int(Date().timeIntervalSince1970)
    let payload: [String: Any] = [
      "iss": issuerId,
      "iat": now,
      "exp": now + 15 * 60,
      "aud": "appstoreconnect-v1",
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let signingInput = base64url(headerData) + "." + base64url(payloadData)

    let key: P256.Signing.PrivateKey
    do {
      key = try P256.Signing.PrivateKey(pemRepresentation: p8PEM)
    } catch {
      throw JWTError.badKey
    }

    let signature = try key.signature(for: Data(signingInput.utf8))
    return signingInput + "." + base64urlEncode(signature.rawRepresentation)
  }

  private static func base64url(_ data: Data) -> String {
    base64urlEncode(data)
  }

  private static func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
