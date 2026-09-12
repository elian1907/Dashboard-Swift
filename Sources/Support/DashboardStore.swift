import Foundation
import Observation

@MainActor @Observable final class DashboardStore {
  var config = AppConfiguration() {
    didSet {
      downloadCache = nil
      geographyCache = nil
    }
  }
  var period: Period = .month
  var overview: RCOverview?
  var revenue: RCChart?
  var proceeds: RCChart?
  var mrr: RCChart?
  var actives: RCChart?
  var trials: RCChart?
  var paying: RCChart?
  var allTrials: RCChart?
  var users: UsersData?
  var apple: SalesArchive? {
    didSet {
      downloadCache = nil
      geographyCache = nil
    }
  }
  var tiktok: TikTokData?
  var loading: Set<String> = []
  var errors: [String: String] = [:]
  private var generation = UUID()
  private var periodGeneration = UUID()
  private var refreshing = false
  @ObservationIgnored private var rangeCache: (Period, String, String, PeriodRange)?
  var range: PeriodRange {
    let today = Day.key(Date())
    let launch = config.launchDate
    let selection = period
    if let cached = rangeCache, cached.0 == selection, cached.1 == launch, cached.2 == today {
      return cached.3
    }
    let result = PeriodRange(selection, launch: launch, today: today)
    rangeCache = (selection, launch, today, result)
    return result
  }
  @ObservationIgnored private var downloadCache: (String, String, [DataPoint])?
  @ObservationIgnored private var geographyCache: (PeriodRange, GeographySnapshot)?
  var downloads: [DataPoint] {
    let archive = apple
    let launch = config.launchDate
    let today = Day.key(Date())
    if let cache = downloadCache, cache.0 == launch, cache.1 == today { return cache.2 }
    let result = archive?.points(appID: archive?.selectedAppId, launch: launch) ?? []
    downloadCache = (launch, today, result)
    return result
  }
  var geography: GeographySnapshot {
    let archive = apple
    let range = range
    if let cache = geographyCache, cache.0 == range { return cache.1 }
    let result = GeographySnapshot(archive: archive, range: range)
    geographyCache = (range, result)
    return result
  }
  var userPoints: [DataPoint] {
    Analytics.align(
      users?.points ?? [], dates: range.labels,
      coverage: users?.growth == nil ? nil : config.launchDate...(users?.asOf ?? Day.key(Date())))
  }
  func series(_ points: [DataPoint]) -> [DataPoint] { Analytics.align(points, dates: range.labels) }
  func busy(_ key: String) -> Bool { loading.contains(key) }
  func delta(_ points: [DataPoint], coverage: ClosedRange<String>? = nil) -> String? {
    Analytics.change(
      Analytics.total(Analytics.align(points, dates: range.labels, coverage: coverage)),
      Analytics.total(Analytics.align(points, dates: range.previous, coverage: coverage)))
  }
  init(loadConfiguration: Bool = true) {
    guard loadConfiguration else { return }
    do { config = try AppConfiguration.load() } catch {
      errors["Trousseau"] = error.localizedDescription
    }
  }
  func setConfiguration(_ c: AppConfiguration) throws {
    try c.save()
    config = c
    generation = UUID()
    periodGeneration = UUID()
    loading = []
    errors = [:]
    overview = nil
    revenue = nil
    proceeds = nil
    mrr = nil
    actives = nil
    trials = nil
    paying = nil
    allTrials = nil
    users = nil
    apple = nil
    tiktok = nil
    refreshing = false
  }
  private func load<T: Sendable>(
    _ key: String, epoch: UUID, fetch: () async throws -> ServiceResult<T>,
    assign: @MainActor (T) -> Void
  ) async {
    loading.insert(key)
    do {
      let result = try await fetch()
      guard generation == epoch else { return }
      assign(result.value)
      errors[key] = result.warning
    } catch {
      guard generation == epoch else { return }
      errors[key] = error.localizedDescription
    }
    loading.remove(key)
  }
  func refresh(force: Bool = false) async {
    guard !refreshing else { return }
    refreshing = true
    let epoch = generation
    let rc = RevenueService(config)
    let asc = AppleService(config)
    let supabase = UsersService(config)
    let tik = TikTokService(config)
    loading.formUnion([
      "overview", "revenue", "proceeds", "mrr", "actives", "allTrials", "users", "apple", "tiktok",
    ])
    async let a: Void = load(
      "overview", epoch: epoch, fetch: { try await rc.overview(force: force) },
      assign: { overview = $0 })
    async let b: Void = load(
      "revenue", epoch: epoch, fetch: { try await rc.chart("revenue", force: force) },
      assign: { revenue = $0 })
    async let c: Void = load(
      "proceeds", epoch: epoch,
      fetch: { try await rc.chart("revenue", revenueType: "proceeds", force: force) },
      assign: { proceeds = $0 })
    async let d: Void = load(
      "mrr", epoch: epoch, fetch: { try await rc.chart("mrr", force: force) }, assign: { mrr = $0 })
    async let e: Void = load(
      "actives", epoch: epoch, fetch: { try await rc.chart("actives", force: force) },
      assign: { actives = $0 })
    async let f: Void = load(
      "allTrials", epoch: epoch,
      fetch: {
        try await rc.chart(
          "trial_conversion_rate", resolution: "month", segment: "product_id", force: force)
      }, assign: { allTrials = $0 })
    async let g: Void = load(
      "users", epoch: epoch, fetch: { try await supabase.fetch() }, assign: { users = $0 })
    async let h: Void = load(
      "apple", epoch: epoch, fetch: { try await asc.fetch(force: force) }, assign: { apple = $0 })
    async let i: Void = load(
      "tiktok", epoch: epoch, fetch: { try await tik.fetch() }, assign: { tiktok = $0 })
    async let j: Void = refreshPeriod()
    _ = await (a, b, c, d, e, f, g, h, i, j)
    if epoch == generation { refreshing = false }
  }
  func refreshPeriod() async {
    let rc = RevenueService(config)
    await refreshPeriod { key, range in
      if key == "trials" {
        return try await rc.chart(
          "trial_conversion_rate", start: range.start, end: range.end, segment: "product_id")
      }
      return try await rc.chart("conversion_to_paying", start: range.start, end: range.end)
    }
  }

  func refreshPeriod(
    using fetch: @escaping @Sendable (String, PeriodRange) async throws -> ServiceResult<RCChart>
  ) async {
    let epoch = UUID()
    periodGeneration = epoch
    let configEpoch = generation
    let range = range
    trials = nil
    paying = nil
    loading.formUnion(["trials", "paying"])
    async let trialRequest: Void = loadPeriod(
      "trials", epoch: epoch, configEpoch: configEpoch, range: range, fetch: fetch)
    async let payingRequest: Void = loadPeriod(
      "paying", epoch: epoch, configEpoch: configEpoch, range: range, fetch: fetch)
    _ = await (trialRequest, payingRequest)
  }

  private func loadPeriod(
    _ key: String, epoch: UUID, configEpoch: UUID, range: PeriodRange,
    fetch: @Sendable (String, PeriodRange) async throws -> ServiceResult<RCChart>
  ) async {
    do {
      let result = try await fetch(key, range)
      guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
      if key == "trials" { trials = result.value } else { paying = result.value }
      errors[key] = result.warning
    } catch {
      guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
      errors[key] = error.localizedDescription
    }
    if periodGeneration == epoch, generation == configEpoch { loading.remove(key) }
  }
}
