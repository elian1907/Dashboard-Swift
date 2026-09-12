import Foundation

enum Day {
  static let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
  }()
  static func parse(_ string: String) -> Date {
    let parts = string.prefix(10).split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return .distantPast }
    return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
  }
  static func key(_ date: Date) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
  }
  static func shift(_ date: String, _ days: Int) -> String {
    key(calendar.date(byAdding: .day, value: days, to: parse(date))!)
  }
  static func range(_ start: String, _ end: String) -> [String] {
    guard start <= end else { return [] }
    var result: [String] = []
    var date = start
    while date <= end {
      result.append(date)
      date = shift(date, 1)
    }
    return result
  }
  static func label(_ key: String) -> String {
    parse(key).formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
      .replacingOccurrences(of: ".", with: "")
  }
}
enum Period: String, CaseIterable, Identifiable {
  case week = "7"
  case month = "30"
  case quarter = "90"
  case all
  var id: String { rawValue }
  var label: String {
    switch self {
    case .week: "7 jours"
    case .month: "30 jours"
    case .quarter: "90 jours"
    case .all: "Depuis le lancement"
    }
  }
}
struct PeriodRange: Equatable {
  let start: String
  let end: String
  let labels: [String]
  let previous: [String]
  init(_ period: Period, launch: String, today: String = Day.key(Date())) {
    end = Day.shift(today, -1)
    start = period == .all ? launch : max(launch, Day.shift(end, 1 - (Int(period.rawValue) ?? 30)))
    labels = Day.range(start, end)
    previous = Day.range(Day.shift(start, -labels.count), Day.shift(start, -1))
  }
}
struct DataPoint: Codable, Identifiable, Equatable, Sendable {
  var date: String
  var value: Double?
  var incomplete: Bool = false
  var id: String { date }
}
enum Analytics {
  static func align(_ points: [DataPoint], dates: [String], coverage: ClosedRange<String>? = nil)
    -> [DataPoint]
  {
    let map = Dictionary(points.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
    return dates.map { date in
      if let point = map[date] {
        return DataPoint(
          date: date, value: point.incomplete ? nil : point.value.flatMap { $0.isFinite ? $0 : nil }
        )
      }
      return DataPoint(date: date, value: coverage?.contains(date) == true ? 0 : nil)
    }
  }
  static func total(_ points: [DataPoint], complete: Bool = true) -> Double? {
    let valid = points.compactMap(\.value).filter(\.isFinite)
    guard !valid.isEmpty, !complete || valid.count == points.count else { return nil }
    return valid.reduce(0, +)
  }
  static func cumulative(_ points: [DataPoint]) -> [DataPoint] {
    var sum = 0.0
    var missing = false
    return points.map { p in
      if let v = p.value { sum += v } else { missing = true }
      return DataPoint(date: p.date, value: missing ? nil : sum)
    }
  }
  static func change(_ current: Double?, _ previous: Double?) -> String? {
    guard let c = current, let p = previous, p > 0 else { return nil }
    return (c >= p ? "+" : "−") + number(abs((c - p) / p * 100), digits: 1) + " %"
  }
  static func number(_ value: Double?, digits: Int = 0) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(
      .number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "fr_FR")))
  }
  static func money(_ value: Double?, digits: Int = 0) -> String {
    value == nil ? "—" : number(value, digits: digits) + " €"
  }
}
struct RCMetric: Codable, Identifiable, Sendable {
  let id: String
  let value: Double
}
struct RCOverview: Codable, Sendable {
  var metrics: [RCMetric]
  func value(_ id: String) -> Double? { metrics.first { $0.id == id }?.value }
}
struct RCMeasure: Codable, Sendable {
  var display_name: String
  var unit: String?
}
struct RCValue: Codable, Sendable {
  var cohort: Double
  var measure: Int
  var value: Double?
  var incomplete: Bool?
}
enum JSONValue: Codable, Sendable {
  case number(Double)
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case null
  case bool(Bool)
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else {
      self = .string(try c.decode(String.self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .number(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  subscript(_ key: String) -> JSONValue {
    if case .object(let d) = self { return d[key] ?? .null }
    return .null
  }
  var number: Double? {
    if case .number(let n) = self { return n }
    return nil
  }
  var object: [String: JSONValue] {
    if case .object(let d) = self { return d }
    return [:]
  }
}
struct RCChart: Codable, Sendable {
  var values: [RCValue]
  var measures: [RCMeasure]?
  var summary: JSONValue?
  func points(measure: Int = 0) -> [DataPoint] {
    values.filter { $0.measure == measure }.map {
      DataPoint(
        date: Day.key(Date(timeIntervalSince1970: $0.cohort)), value: $0.value,
        incomplete: $0.incomplete ?? false)
    }.sorted { $0.date < $1.date }
  }
  var totals: JSONValue { summary?["total"] ?? .null }
}
struct UsersData: Codable, Sendable {
  var accounts: Double?
  var profiles: Double?
  var growth: [Growth]?
  var asOf: String?
  struct Growth: Codable, Sendable {
    var date: String
    var count: Double
  }
  var points: [DataPoint] { (growth ?? []).map { DataPoint(date: $0.date, value: $0.count) } }
}
struct AppDay: Codable, Sendable {
  var title: String
  var units: Double
  var countries: [String: Double]
}
struct SalesReport: Codable, Sendable {
  var checkedAt: Double
  var apps: [String: AppDay]?
}
struct SalesArchive: Codable, Sendable {
  var version = 1
  var selectedAppId: String?
  var reports: [String: SalesReport] = [:]
  func points(appID: String?, launch: String) -> [DataPoint] {
    Day.range(launch, Day.shift(Day.key(Date()), -1)).map { date in
      let apps = reports[date]?.apps
      return DataPoint(date: date, value: appID.flatMap { id in apps.map { $0[id]?.units ?? 0 } })
    }
  }
  func countries(_ dates: [String], appID: String?) -> (rows: [CountryRow], missing: Int) {
    var result: [String: Double] = [:]
    var missing = 0
    for date in dates {
      guard let apps = reports[date]?.apps, let appID else {
        missing += 1
        continue
      }
      for (code, count) in apps[appID]?.countries ?? [:] { result[code, default: 0] += count }
    }
    return (
      result.map { CountryRow(code: $0.key, units: $0.value) }.sorted { $0.units > $1.units },
      missing
    )
  }
}
struct CountryRow: Identifiable {
  let code: String
  let units: Double
  var id: String { code }
  var name: String { Locale(identifier: "fr_FR").localizedString(forRegionCode: code) ?? code }
  var flag: String {
    String(
      String.UnicodeScalarView(
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
  }
}
struct TikTokAccount: Codable, Identifiable, Sendable {
  var id: String
  var name: String
  var followers: Double
  var likes: Double
  var views: Double
  var videos: Int
}
struct TikTokVideo: Codable, Identifiable, Sendable {
  var id: String
  var accountId: String
  var account: String
  var title: String
  var date: String
  var views: Double
  var likes: Double
  var comments: Double
  var shares: Double
  var engagement: Double { views > 0 ? (likes + comments + shares) / views * 100 : 0 }
}
struct TikTokData: Codable, Sendable {
  var accounts: [TikTokAccount]
  var videos: [TikTokVideo]
  var at: Date = Date()
  var needsConnection = false
}
struct Offer: Identifiable {
  let id: String
  let name: String
  let price: Double
  static let all = [
    Offer(id: "loslo_special_offer", name: "Offre spéciale", price: 19.99),
    Offer(id: "loslo_premium_yearly", name: "Offre annuelle", price: 49.99),
    Offer(id: "loslo_premium_monthly", name: "Mensuel", price: 9.99),
  ]
  static func conversion(_ s: JSONValue) -> Double? {
    let end = (s["Conversions"].number ?? 0) + (s["Expirations"].number ?? 0)
    return end > 0 ? (s["Conversions"].number ?? 0) / end : nil
  }
  static func expected(_ totals: JSONValue) -> Double {
    all.reduce(0) {
      $0 + max(0, totals[$1.id]["Pending"].number ?? 0) * (conversion(totals[$1.id]) ?? 0)
        * $1.price
    }
  }
}
