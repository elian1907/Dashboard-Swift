import Foundation

actor AppleService {
  let config: AppConfiguration
  init(_ c: AppConfiguration) { config = c }
  static func parse(_ tsv: String) throws -> [String: AppDay] {
    var lines = tsv.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
    guard !lines.isEmpty else { throw DashboardError(message: "Rapport Apple vide.") }
    let header = lines.removeFirst().replacingOccurrences(of: "\u{feff}", with: "").components(
      separatedBy: "\t")
    for name in ["Apple Identifier", "Units", "Product Type Identifier", "Country Code"]
    where !header.contains(name) {
      throw DashboardError(message: "Rapport Apple incomplet : \(name).")
    }
    var result: [String: AppDay] = [:]
    for line in lines where !line.isEmpty {
      let row = line.components(separatedBy: "\t")
      func cell(_ name: String) -> String {
        guard let i = header.firstIndex(of: name), row.indices.contains(i) else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
      }
      guard ["1", "1E", "1EP", "1EU", "1F", "1T", "F1"].contains(cell("Product Type Identifier"))
      else { continue }
      let id = cell("Apple Identifier")
      guard !id.isEmpty, let units = Double(cell("Units")), units.isFinite else {
        throw DashboardError(message: "Volume ou identifiant Apple invalide.")
      }
      var app = result[id] ?? AppDay(title: cell("Title"), units: 0, countries: [:])
      app.units += units
      app.countries[
        cell("Country Code").isEmpty ? "ZZ" : cell("Country Code").uppercased(), default: 0] +=
        units
      result[id] = app
    }
    return result
  }
  static func resolve(_ apps: [String: AppDay], configured: String?, name: String) throws -> String?
  {
    if let configured, !configured.isEmpty { return configured }
    let matching = apps.filter { $0.value.title.lowercased().hasPrefix(name.lowercased()) }.map(
      \.key)
    if matching.count == 1 { return matching[0] }
    if apps.count == 1 { return apps.keys.first }
    if apps.count > 1 {
      throw DashboardError(
        message: "Plusieurs apps détectées : précise l’identifiant Apple dans Réglages.")
    }
    return nil
  }
  func cached() -> SalesArchive? {
    guard
      var archive = NativeCache.read(SalesArchive.self, key: "apple:" + config.vendor)
        ?? NativeCache.legacy(
          SalesArchive.self, key: "appstore-v1:" + NativeCache.hash(config.vendor))
    else { return nil }
    let apps = archive.reports.values.reduce(into: [String: AppDay]()) { result, report in
      for (id, app) in report.apps ?? [:] { result[id] = app }
    }
    do {
      archive.selectedAppId = try Self.resolve(
        apps,
        configured: config.appID.isEmpty ? archive.selectedAppId : config.appID, name: config.name)
      return archive
    } catch { return nil }
  }
  func fetch(force: Bool = false) async throws -> ServiceResult<SalesArchive> {
    let cacheKey = "apple:" + config.vendor
    var archive = NativeCache.read(SalesArchive.self, key: cacheKey) ?? SalesArchive()
    let today = Day.key(Date())
    let now = Date().timeIntervalSince1970 * 1000
    let dates = Day.range(config.launchDate, Day.shift(today, -1)).reversed().filter { date in
      guard let old = archive.reports[date] else { return true }
      if force && (date >= Day.shift(today, -3) || old.apps == nil) { return true }
      let ttl: Double =
        date >= Day.shift(today, -3) ? 240000 : old.apps == nil ? 86_400_000 : .infinity
      return now - old.checkedAt >= ttl
    }
    var warning: String?
    do {
      guard config.appleReady else {
        throw DashboardError(message: "Connecte App Store Connect dans Réglages.")
      }
      if !dates.isEmpty {
        let token = try JWT.appStoreConnect(
          issuerId: config.issuer, keyId: config.keyID, p8PEM: config.privateKey)
        for offset in stride(from: 0, to: dates.count, by: 8) {
          let batch = Array(dates.dropFirst(offset).prefix(8))
          let c = config
          let results = await withTaskGroup(
            of: (String, Result<SalesReport, Error>).self,
            returning: [(String, Result<SalesReport, Error>)].self
          ) { group in
            for date in batch {
              group.addTask {
                do {
                  let url = try HTTP.url(
                    "https://api.appstoreconnect.apple.com/v1/salesReports",
                    [
                      ("filter[frequency]", "DAILY"), ("filter[reportType]", "SALES"),
                      ("filter[reportSubType]", "SUMMARY"), ("filter[vendorNumber]", c.vendor),
                      ("filter[reportDate]", date), ("filter[version]", c.salesVersion),
                    ])
                  let data = try await HTTP.data(
                    url,
                    headers: ["Authorization": "Bearer " + token, "Accept": "application/a-gzip"])
                  return (
                    date,
                    .success(
                      SalesReport(
                        checkedAt: Date().timeIntervalSince1970 * 1000,
                        apps: try Self.parse(Gzip.decode(data))))
                  )
                } catch APIError.status(404) {
                  return (
                    date,
                    .success(SalesReport(checkedAt: Date().timeIntervalSince1970 * 1000, apps: nil))
                  )
                } catch { return (date, .failure(error)) }
              }
            }
            var result: [(String, Result<SalesReport, Error>)] = []
            for await value in group { result.append(value) }
            return result
          }
          var failure: Error?
          for (date, result) in results {
            switch result {
            case .success(let report): archive.reports[date] = report
            case .failure(let e): failure = e
            }
          }
          try NativeCache.save(archive, key: cacheKey)
          if let failure { throw failure }
        }
      }
    } catch {
      guard archive.reports.values.contains(where: { $0.apps != nil }) else { throw error }
      warning = "App Store Connect hors ligne · historique sauvegardé affiché."
    }
    let all = archive.reports.values.reduce(into: [String: AppDay]()) { result, report in
      for (id, app) in report.apps ?? [:] { result[id] = app }
    }
    archive.selectedAppId = try Self.resolve(
      all, configured: config.appID.isEmpty ? archive.selectedAppId : config.appID,
      name: config.name)
    try NativeCache.save(archive, key: cacheKey)
    return .init(value: archive, warning: warning)
  }
}
