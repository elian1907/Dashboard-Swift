import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct DashboardError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
enum Keychain {
  private static let service = "com.loslo.dashboard.swift"
  static func read<T: Decodable>(_ type: T.Type, key: String, allowPrompt: Bool = false) throws
    -> T?
  {
    let context = LAContext()
    context.interactionNotAllowed = !allowPrompt
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw DashboardError(
        message:
          "Trousseau verrouillé ou autorisation nécessaire (\(status)). Ouvre Réglages pour autoriser l’accès."
      )
    }
    return try JSONDecoder().decode(type, from: data)
  }
  static func save<T: Encodable>(_ item: T, key: String) throws {
    let data = try JSONEncoder().encode(item)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    var status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw DashboardError(message: "Enregistrement dans le Trousseau impossible (\(status)).")
    }
  }
}
struct AppConfiguration: Codable, Equatable, Sendable {
  var name = "Loslo"
  var launchDate = "2026-06-14"
  var rcKey = ""
  var rcProject = ""
  var issuer = ""
  var keyID = ""
  var vendor = ""
  var appID = ""
  var privateKey = ""
  var salesVersion = "1_1"
  var supabaseURL = ""
  var supabaseKey = ""
  var tiktokClient = ""
  var tiktokSecret = ""
  var tiktokRedirect = ""
  var rcReady: Bool { !rcKey.isEmpty && !rcProject.isEmpty }
  var appleReady: Bool {
    !issuer.isEmpty && !keyID.isEmpty && !vendor.isEmpty && !privateKey.isEmpty
  }
  var usersReady: Bool { !supabaseURL.isEmpty && !supabaseKey.isEmpty }
  static func load() throws -> Self { try Keychain.read(Self.self, key: "configuration") ?? Self() }
  func save() throws { try Keychain.save(self, key: "configuration") }
}
struct NativeTikTokCredential: Codable, Sendable {
  var open_id: String
  var refresh_token: String
  var saved_at: String?
  var display_name: String?
}
enum NativeCache {
  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Loslo Dashboard Swift", isDirectory: true)
  }
  static func hash(_ key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func file(_ key: String) -> URL { root.appendingPathComponent(hash(key) + ".json") }
  static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
    guard let d = try? Data(contentsOf: file(key)) else { return nil }
    return try? JSONDecoder().decode(type, from: d)
  }
  static func save<T: Encodable>(_ item: T, key: String) throws {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let url = file(key)
    try JSONEncoder().encode(item).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  static func legacy<T: Decodable>(_ type: T.Type, key: String) -> T? {
    let f = root.appendingPathComponent("Legacy").appendingPathComponent(hash(key) + ".json")
    guard let d = try? Data(contentsOf: f) else { return nil }
    return try? JSONDecoder().decode(type, from: d)
  }
}
struct Saved<Value: Codable & Sendable>: Codable, Sendable {
  var at: Double
  var data: Value
}

/// Read-only migration. TikTok refresh tokens are deliberately never copied: they rotate,
/// so sharing one between the website and native app can invalidate the website's session.
enum DashboardImporter {
  static func environment(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
      let clean = line.trimmingCharacters(in: .whitespaces)
      guard !clean.hasPrefix("#"), let split = clean.firstIndex(of: "=") else { continue }
      let key = String(clean[..<split]).replacingOccurrences(of: "export ", with: "")
        .trimmingCharacters(in: .whitespaces)
      var value = String(clean[clean.index(after: split)...]).trimmingCharacters(in: .whitespaces)
      if let first = value.first, first == "\"" || first == "'", value.last == first {
        value = String(value.dropFirst().dropLast())
      }
      result[key] = value.replacingOccurrences(of: "\\n", with: "\n")
    }
    return result
  }
  static func run(folder: URL) throws -> AppConfiguration {
    let env = environment(
      try String(contentsOf: folder.appendingPathComponent(".env.local"), encoding: .utf8))
    var c = AppConfiguration()
    c.rcKey = env["REVENUECAT_V2_SECRET_KEY"] ?? ""
    c.rcProject = env["REVENUECAT_PROJECT_ID"] ?? ""
    c.issuer = env["ASC_ISSUER_ID"] ?? ""
    c.keyID = env["ASC_KEY_ID"] ?? ""
    c.vendor = env["ASC_VENDOR_NUMBER"] ?? ""
    c.appID = env["ASC_APP_ID"] ?? ""
    c.salesVersion = env["ASC_SALES_REPORT_VERSION"] ?? "1_1"
    c.privateKey = env["ASC_PRIVATE_KEY"] ?? ""
    if c.privateKey.isEmpty, let path = env["ASC_PRIVATE_KEY_PATH"] {
      let file =
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
      c.privateKey = try String(contentsOf: file, encoding: .utf8)
    }
    c.supabaseURL = env["SUPABASE_URL"] ?? ""
    c.supabaseKey = env["SUPABASE_ANON_KEY"] ?? ""
    c.tiktokClient = env["TIKTOK_CLIENT_KEY"] ?? ""
    c.tiktokSecret = env["TIKTOK_CLIENT_SECRET"] ?? ""
    c.tiktokRedirect = env["TIKTOK_REDIRECT_URI"] ?? ""
    guard c.rcReady || c.appleReady || c.usersReady else {
      throw DashboardError(
        message: "Ce dossier ne contient aucune connexion de dashboard reconnue.")
    }
    try c.save()
    let cacheFolder = folder.appendingPathComponent("data/dashboard-cache")
    let dest = NativeCache.root.appendingPathComponent("Legacy")
    try FileManager.default.createDirectory(
      at: dest, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    // Only structured analytics snapshots; no configuration or token files.
    for url
      in (try? FileManager.default.contentsOfDirectory(
        at: cacheFolder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json"
    {
      let data = try Data(contentsOf: url)
      guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        obj["data"] != nil || obj["reports"] != nil
      else { continue }
      let target = dest.appendingPathComponent(url.lastPathComponent)
      try data.write(to: target, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    if let archive = NativeCache.legacy(
      SalesArchive.self, key: "appstore-v1:" + NativeCache.hash(c.vendor))
    {
      try NativeCache.save(archive, key: "apple:" + c.vendor)
    }
    try importTikTokHistory(folder: folder)
    return c
  }
  private static func importTikTokHistory(folder: URL) throws {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("data/tiktok-token.json")),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    var accounts: [TikTokAccount] = []
    var videos: [TikTokVideo] = []
    for account in object["accounts"] as? [[String: Any]] ?? [] {
      guard let id = account["open_id"] as? String,
        let snapshot = NativeCache.legacy(Saved<TikTokRaw>.self, key: "tiktok-account:" + id)
      else { continue }
      let name =
        snapshot.data.profile.display_name ?? account["display_name"] as? String ?? "Compte"
      let rows = snapshot.data.videos.map { $0.row(id: id, name: name) }
      videos += rows
      accounts.append(
        TikTokAccount(
          id: id, name: name, followers: snapshot.data.profile.follower_count ?? 0,
          likes: snapshot.data.profile.likes_count ?? 0, views: rows.reduce(0) { $0 + $1.views },
          videos: rows.count))
    }
    if !accounts.isEmpty {
      try NativeCache.save(
        TikTokData(accounts: accounts, videos: videos, needsConnection: true), key: "tiktok-history"
      )
    }
  }
}
