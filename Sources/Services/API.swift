import Foundation
import zlib

struct ServiceResult<T> {
  var value: T
  var warning: String? = nil
}
extension ServiceResult: Sendable where T: Sendable {}

enum HTTP {
  static func data(_ url: URL, headers: [String: String] = [:], body: Data? = nil) async throws
    -> Data
  {
    guard url.scheme == "https" else {
      throw DashboardError(message: "La connexion doit utiliser HTTPS.")
    }
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.allHTTPHeaderFields = headers
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DashboardError(message: "Réponse serveur invalide.")
    }
    guard (200...299).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
    return data
  }
  static func url(_ base: String, _ query: [(String, String)] = []) throws -> URL {
    guard var c = URLComponents(string: base), c.scheme == "https", c.host != nil else {
      throw DashboardError(message: "Adresse de connexion invalide.")
    }
    if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
    guard let url = c.url else { throw DashboardError(message: "Adresse invalide.") }
    return url
  }
}
enum APIError: LocalizedError {
  case status(Int)
  var errorDescription: String? {
    if case .status(let status) = self {
      return "Connexion refusée (HTTP \(status)). Vérifie les accès dans Réglages."
    }
    return nil
  }
}
actor RevenueService {
  let config: AppConfiguration
  init(_ config: AppConfiguration) { self.config = config }
  func cached<T: Codable & Sendable>(_ type: T.Type, path: String, latestKey: String? = nil) -> T? {
    NativeCache.read(Saved<T>.self, key: "rc:" + config.rcProject + ":" + path)?.data
      ?? latestKey.flatMap { NativeCache.read(Saved<T>.self, key: $0)?.data }
      ?? NativeCache.legacy(Saved<T>.self, key: "revenuecat:" + path)?.data
  }
  func cachedOverview() -> RCOverview? {
    cached(RCOverview.self, path: overviewPath)
  }
  private var overviewPath: String { "/projects/\(config.rcProject)/metrics/overview?currency=EUR" }
  func fetch<T: Codable & Sendable>(_ type: T.Type, path: String, force: Bool = false) async throws
    -> ServiceResult<T>
  {
    let cacheKey = "rc:" + config.rcProject + ":" + path
    let saved =
      NativeCache.read(Saved<T>.self, key: cacheKey)
      ?? NativeCache.legacy(Saved<T>.self, key: "revenuecat:" + path)
    if !force, let saved, Date().timeIntervalSince1970 * 1000 - saved.at < 240000 {
      return .init(value: saved.data)
    }
    do {
      guard config.rcReady else {
        throw DashboardError(message: "Connecte RevenueCat dans Réglages.")
      }
      let data = try await HTTP.data(
        HTTP.url("https://api.revenuecat.com/v2" + path),
        headers: ["Authorization": "Bearer " + config.rcKey])
      let value = try JSONDecoder().decode(T.self, from: data)
      try NativeCache.save(
        Saved(at: Date().timeIntervalSince1970 * 1000, data: value), key: cacheKey)
      return .init(value: value)
    } catch {
      if let saved {
        return .init(
          value: saved.data, warning: "RevenueCat hors ligne · dernière sauvegarde affichée.")
      }
      throw error
    }
  }
  func overview(force: Bool = false) async throws -> ServiceResult<RCOverview> {
    try await fetch(
      RCOverview.self, path: overviewPath,
      force: force)
  }
  func chart(
    _ chart: String, start: String? = nil, end: String? = nil, resolution: String = "day",
    revenueType: String? = nil, segment: String? = nil, force: Bool = false
  ) async throws -> ServiceResult<RCChart> {
    let path = chartPath(
      chart, start: start, end: end, resolution: resolution, revenueType: revenueType,
      segment: segment)
    let result = try await fetch(RCChart.self, path: path, force: force)
    if start == nil, end == nil {
      try? NativeCache.save(
        Saved(at: Date().timeIntervalSince1970 * 1000, data: result.value),
        key: latestChartKey(
          chart, resolution: resolution, revenueType: revenueType, segment: segment))
    }
    return result
  }
  func cachedChart(
    _ chart: String, start: String? = nil, end: String? = nil,
    resolution: String = "day", revenueType: String? = nil, segment: String? = nil
  ) -> RCChart? {
    cached(
      RCChart.self,
      path: chartPath(
        chart, start: start, end: end, resolution: resolution, revenueType: revenueType,
        segment: segment),
      latestKey: start == nil && end == nil
        ? latestChartKey(chart, resolution: resolution, revenueType: revenueType, segment: segment)
        : nil)
  }
  private func latestChartKey(
    _ chart: String, resolution: String, revenueType: String?, segment: String?
  ) -> String {
    "rc-latest:"
      + [config.rcProject, config.launchDate, chart, resolution, revenueType ?? "", segment ?? ""]
      .joined(separator: ":")
  }
  private func chartPath(
    _ chart: String, start: String?, end: String?, resolution: String,
    revenueType: String?, segment: String?
  ) -> String {
    var parts = URLComponents()
    parts.queryItems = [
      URLQueryItem(name: "resolution", value: resolution),
      URLQueryItem(name: "start_date", value: start ?? config.launchDate),
      URLQueryItem(name: "end_date", value: end ?? Day.key(Date())),
      URLQueryItem(name: "currency", value: "EUR"),
    ]
    if let revenueType {
      parts.queryItems?.append(
        URLQueryItem(name: "selectors", value: "{\"revenue_type\":\"\(revenueType)\"}"))
    }
    if let segment { parts.queryItems?.append(URLQueryItem(name: "segment", value: segment)) }
    return "/projects/\(config.rcProject)/charts/\(chart)?" + (parts.percentEncodedQuery ?? "")
  }

}
actor UsersService {
  let config: AppConfiguration
  init(_ c: AppConfiguration) { config = c }
  func cached() -> UsersData? {
    NativeCache.read(Saved<UsersData>.self, key: "users:" + config.supabaseURL)?.data
      ?? NativeCache.legacy(
        Saved<UsersData>.self, key: "supabase-users:" + NativeCache.hash(config.supabaseURL))?.data
  }
  func fetch() async throws -> ServiceResult<UsersData> {
    let key = "users:" + config.supabaseURL
    let saved =
      NativeCache.read(Saved<UsersData>.self, key: key)
      ?? NativeCache.legacy(
        Saved<UsersData>.self, key: "supabase-users:" + NativeCache.hash(config.supabaseURL))
    do {
      guard config.usersReady else {
        throw DashboardError(message: "Connecte Supabase dans Réglages.")
      }
      let url = try HTTP.url(
        config.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          + "/rest/v1/rpc/dashboard_user_counts")
      let data = try await HTTP.data(
        url,
        headers: [
          "apikey": config.supabaseKey, "Authorization": "Bearer " + config.supabaseKey,
          "Content-Type": "application/json",
        ], body: Data("{}".utf8))
      var value = try JSONDecoder().decode(UsersData.self, from: data)
      value.asOf = Day.key(Date())
      try NativeCache.save(Saved(at: Date().timeIntervalSince1970 * 1000, data: value), key: key)
      return .init(value: value)
    } catch {
      if let saved {
        return .init(
          value: saved.data, warning: "Supabase hors ligne · dernière sauvegarde affichée.")
      }
      throw error
    }
  }
}
enum Gzip {
  static func decode(_ data: Data) throws -> String {
    guard !data.isEmpty else { throw DashboardError(message: "Rapport vide.") }
    var stream = z_stream()
    guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
    else { throw DashboardError(message: "Décompression impossible.") }
    defer { inflateEnd(&stream) }
    var output = Data()
    let size = 65536
    try data.withUnsafeBytes { raw in
      stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress!)
      stream.avail_in = uInt(data.count)
      var status: Int32 = Z_OK
      repeat {
        var buffer = [UInt8](repeating: 0, count: size)
        status = buffer.withUnsafeMutableBufferPointer { ptr in
          stream.next_out = ptr.baseAddress
          stream.avail_out = uInt(size)
          return inflate(&stream, Z_NO_FLUSH)
        }
        guard status == Z_OK || status == Z_STREAM_END else {
          throw DashboardError(message: "Rapport compressé invalide.")
        }
        output.append(contentsOf: buffer.prefix(size - Int(stream.avail_out)))
        guard output.count < 64 * 1024 * 1024 else {
          throw DashboardError(message: "Rapport trop volumineux.")
        }
      } while status != Z_STREAM_END
    }
    guard let result = String(data: output, encoding: .utf8) else {
      throw DashboardError(message: "Encodage du rapport invalide.")
    }
    return result
  }
}
