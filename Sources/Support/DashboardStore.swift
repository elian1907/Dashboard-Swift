import Foundation
import Observation

@MainActor @Observable final class DashboardStore {
  var config = AppConfiguration() {
    didSet {
      downloadCache = nil
      geographyCache = nil
      periodResults = [:]
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
  @ObservationIgnored private var sourceStates: [String: SourceLoadState] = [:]
  @ObservationIgnored var loading: Set<String> = [] {
    didSet {
      for key in oldValue.symmetricDifference(loading) {
        sourceState(key).isLoading = loading.contains(key)
      }
    }
  }
  @ObservationIgnored private var periodResults: [String: [String: RCChart]] = [:]
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
  private func sourceState(_ key: String) -> SourceLoadState {
    if let state = sourceStates[key] { return state }
    let state = SourceLoadState()
    state.isLoading = loading.contains(key)
    sourceStates[key] = state
    return state
  }
  func busy(_ key: String) -> Bool { sourceState(key).isLoading }
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
  /// A saved snapshot is useful immediately, even while the server is slow or offline.
  /// Cache reads, decoding and requests run on their service actors.
  func load<T: Sendable>(
    _ key: String, epoch requestEpoch: UUID? = nil, current: T?,
    cached: () async -> T? = { nil }, fetch: () async throws -> ServiceResult<T>,
    assign: @MainActor (T) -> Void
  ) async {
    let epoch = requestEpoch ?? generation
    guard generation == epoch else { return }
    loading.insert(key)
    defer { if generation == epoch { loading.remove(key) } }
    if current == nil, let saved = await cached() {
      guard generation == epoch, !Task.isCancelled else { return }
      assign(saved)
      await Task.yield()
    }
    guard generation == epoch, !Task.isCancelled else { return }
    do {
      let result = try await fetch()
      guard generation == epoch, !Task.isCancelled else { return }
      assign(result.value)
      errors[key] = result.warning
    } catch {
      guard generation == epoch, !Task.isCancelled else { return }
      errors[key] = error.localizedDescription
    }
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
      "overview", epoch: epoch, current: overview, cached: { await rc.cachedOverview() },
      fetch: { try await rc.overview(force: force) },
      assign: { overview = $0 })
    async let b: Void = load(
      "revenue", epoch: epoch, current: revenue, cached: { await rc.cachedChart("revenue") },
      fetch: { try await rc.chart("revenue", force: force) },
      assign: { revenue = $0 })
    async let c: Void = load(
      "proceeds", epoch: epoch, current: proceeds,
      cached: { await rc.cachedChart("revenue", revenueType: "proceeds") },
      fetch: { try await rc.chart("revenue", revenueType: "proceeds", force: force) },
      assign: { proceeds = $0 })
    async let d: Void = load(
      "mrr", epoch: epoch, current: mrr, cached: { await rc.cachedChart("mrr") },
      fetch: { try await rc.chart("mrr", force: force) }, assign: { mrr = $0 })
    async let e: Void = load(
      "actives", epoch: epoch, current: actives, cached: { await rc.cachedChart("actives") },
      fetch: { try await rc.chart("actives", force: force) },
      assign: { actives = $0 })
    async let f: Void = load(
      "allTrials", epoch: epoch, current: allTrials,
      cached: {
        await rc.cachedChart("trial_conversion_rate", resolution: "month", segment: "product_id")
      },
      fetch: {
        try await rc.chart(
          "trial_conversion_rate", resolution: "month", segment: "product_id", force: force)
      }, assign: { allTrials = $0 })
    async let g: Void = load(
      "users", epoch: epoch, current: users, cached: { await supabase.cached() },
      fetch: { try await supabase.fetch() }, assign: { users = $0 })
    async let h: Void = load(
      "apple", epoch: epoch, current: apple, cached: { await asc.cached() },
      fetch: { try await asc.fetch(force: force) }, assign: { apple = $0 })
    async let i: Void = load(
      "tiktok", epoch: epoch, current: tiktok, cached: { await tik.cached() },
      fetch: { try await tik.fetch() }, assign: { tiktok = $0 })
    async let j: Void = refreshPeriod()
    _ = await (a, b, c, d, e, f, g, h, i, j)
    if epoch == generation { refreshing = false }
  }
  func refreshPeriod() async {
    let rc = RevenueService(config)
    await refreshPeriod(
      using: { key, range in
        if key == "trials" {
          return try await rc.chart(
            "trial_conversion_rate", start: range.start, end: range.end, segment: "product_id")
        }
        return try await rc.chart("conversion_to_paying", start: range.start, end: range.end)
      },
      cached: { key, range in
        if key == "trials" {
          return await rc.cachedChart(
            "trial_conversion_rate", start: range.start, end: range.end, segment: "product_id")
        }
        return await rc.cachedChart("conversion_to_paying", start: range.start, end: range.end)
      })
  }

  func refreshPeriod(
    using fetch: @escaping @Sendable (String, PeriodRange) async throws -> ServiceResult<RCChart>,
    cached: @escaping @Sendable (String, PeriodRange) async -> RCChart? = { _, _ in nil }
  ) async {
    let epoch = UUID()
    periodGeneration = epoch
    let configEpoch = generation
    let range = range
    let saved = periodResults[range.start + ":" + range.end]
    trials = saved?["trials"]
    paying = saved?["paying"]
    loading.formUnion(["trials", "paying"])
    async let trialRequest: Void = loadPeriod(
      "trials", epoch: epoch, configEpoch: configEpoch, range: range, cached: cached, fetch: fetch)
    async let payingRequest: Void = loadPeriod(
      "paying", epoch: epoch, configEpoch: configEpoch, range: range, cached: cached, fetch: fetch)
    _ = await (trialRequest, payingRequest)
  }

  private func loadPeriod(
    _ key: String, epoch: UUID, configEpoch: UUID, range: PeriodRange,
    cached: @Sendable (String, PeriodRange) async -> RCChart?,
    fetch: @Sendable (String, PeriodRange) async throws -> ServiceResult<RCChart>
  ) async {
    defer {
      if periodGeneration == epoch, generation == configEpoch { loading.remove(key) }
    }
    let rangeKey = range.start + ":" + range.end
    if periodResults[rangeKey]?[key] == nil, let saved = await cached(key, range) {
      guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
      periodResults[rangeKey, default: [:]][key] = saved
      if key == "trials" { trials = saved } else { paying = saved }
      await Task.yield()
    }
    guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
    do {
      let result = try await fetch(key, range)
      guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
      periodResults[rangeKey, default: [:]][key] = result.value
      if key == "trials" { trials = result.value } else { paying = result.value }
      errors[key] = result.warning
    } catch {
      guard periodGeneration == epoch, generation == configEpoch, !Task.isCancelled else { return }
      errors[key] = error.localizedDescription
    }
  }
}

/// Observe the state of one source, so an unrelated request cannot invalidate every card.
@MainActor @Observable private final class SourceLoadState {
  var isLoading = false
}
