import AppKit
import Observation
import SwiftUI
import Synchronization
import XCTest

@testable import LosloDashboard

final class ProgressiveLoadingTests: XCTestCase {
  @MainActor func testReadyCardDoesNotWaitForSlowerCard() async {
    let store = DashboardStore(loadConfiguration: false)
    let source = ControlledCharts()
    let request = Task {
      await store.refreshPeriod(using: { try await source.fetch($0, range: $1) })
    }
    await source.waitForRequests()
    XCTAssertTrue(store.busy("trials"))
    XCTAssertTrue(store.busy("paying"))

    await source.finish("paying", value: 8)
    await waitUntil { store.paying != nil }
    XCTAssertEqual(store.paying?.values.first?.value, 8)
    XCTAssertFalse(store.busy("paying"))
    XCTAssertTrue(store.busy("trials"))
    XCTAssertNil(store.trials)

    await source.finish("trials", value: 21)
    await request.value
    XCTAssertEqual(store.trials?.values.first?.value, 21)
    XCTAssertFalse(store.busy("trials"))
  }

  @MainActor func testOldPeriodCannotReplaceNewPeriodOrRemoveItsLoadingState() async {
    let store = DashboardStore(loadConfiguration: false)
    let oldSource = ControlledCharts()
    let oldRequest = Task {
      await store.refreshPeriod(using: { try await oldSource.fetch($0, range: $1) })
    }
    await oldSource.waitForRequests()
    store.period = .week
    let newSource = ControlledCharts()
    let newRequest = Task {
      await store.refreshPeriod(using: { try await newSource.fetch($0, range: $1) })
    }
    await newSource.waitForRequests()
    await oldSource.finish("trials", value: 999)
    await oldSource.finish("paying", value: 999)
    await oldRequest.value
    XCTAssertNil(store.trials)
    XCTAssertNil(store.paying)
    XCTAssertTrue(store.busy("trials"))
    XCTAssertTrue(store.busy("paying"))
    await newSource.finish("paying", value: 3)
    await newSource.finish("trials", value: 4)
    await newRequest.value
    XCTAssertEqual(store.paying?.values.first?.value, 3)
    XCTAssertEqual(store.trials?.values.first?.value, 4)
  }

  @MainActor func testPlaceholderIsLaidOutBeforeHeavyContentIsConstructed() async {
    var contentConstructions = 0
    let host = NSHostingView(
      rootView: ProgressiveContent(identity: "destination") {
        Text("Chargement").frame(width: 240, height: 120)
      } content: {
        contentConstructions += 1
        return Text("Données").frame(width: 240, height: 120)
      })
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(
      contentConstructions, 0, "Heavy content must not be built in the destination's first layout.")
    host.displayIfNeeded()
    await waitUntil { contentConstructions > 0 }
    XCTAssertGreaterThan(
      contentConstructions, 0,
      "The real content must replace the placeholder after the first paint.")
  }

  @MainActor func testLeavingBeforeFirstPaintDoesNotConstructAbandonedPage() async {
    var constructed: [String] = []
    func destination(_ id: String) -> some View {
      ProgressiveContent(identity: id) {
        Text("Chargement").frame(width: 240, height: 120)
      } content: {
        constructed.append(id)
        return Text(id).frame(width: 240, height: 120)
      }
    }
    let host = NSHostingView(rootView: destination("ancienne"))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()
    // Replace the destination before its first frame: no obsolete chart should mount.
    host.rootView = destination("nouvelle")
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    await waitUntil { constructed.contains("nouvelle") }
    XCTAssertTrue(constructed.contains("nouvelle"))
    XCTAssertFalse(constructed.contains("ancienne"))
  }

  @MainActor func testMetricCardsKeepEqualWidthsWhenWindowResizes() async {
    var probes: [Int: NSView] = [:]
    let host = NSHostingView(
      rootView: MetricRow(spacing: 16) {
        ForEach(0..<4) { index in
          Text(index == 0 ? "Téléchargements sur la période" : "MRR")
            .frame(maxWidth: .infinity, minHeight: 100)
            .background { FrameProbe { probes[index] = $0 } }
        }
      })
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    for width in [900.0, 700.0, 1200.0] {
      window.setContentSize(NSSize(width: width, height: 200))
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      await waitUntil {
        probes.count == 4 && abs((probes[0]?.frame.width ?? 0) - (width - 48) / 4) < 1
      }
      XCTAssertEqual(probes.count, 4)
      for view in probes.values {
        XCTAssertEqual(view.frame.width, (width - 48) / 4, accuracy: 1)
      }
    }
  }

  @MainActor func testRevisitedPagesReuseTheirHostAndOnlySelectedPageIsAttached() {
    let store = DashboardStore(loadConfiguration: false)
    let container = DashboardPageHost.PageContainer(
      frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let binding = Binding.constant(DashboardPage.downloads)
    container.show(page: .downloads, selection: binding, store: store)
    let downloads = container.subviews.first!
    container.show(page: .revenue, selection: binding, store: store)
    let revenue = container.subviews.first!
    XCTAssertFalse(downloads === revenue)
    XCTAssertNil(downloads.superview, "Off-screen pages must not participate in window layout.")
    container.show(page: .downloads, selection: binding, store: store)
    XCTAssertTrue(
      container.subviews.first === downloads,
      "Returning must retain the prepared native view graph.")
    XCTAssertNil(revenue.superview)
    XCTAssertEqual(container.subviews.count, 1)
    container.setFrameSize(NSSize(width: 1200, height: 800))
    XCTAssertEqual(downloads.frame, container.bounds)
    // Header/store changes must not replace the active page or reset local filters.
    store.period = .week
    container.show(page: .downloads, selection: binding, store: store)
    XCTAssertTrue(container.subviews.first === downloads)
  }

  @MainActor func testAllDestinationsCanBeSelectedWhileEverySourceIsLoading() {
    let store = DashboardStore(loadConfiguration: false)
    store.loading = ["overview", "revenue", "mrr", "trials", "apple", "users", "tiktok"]
    let container = DashboardPageHost.PageContainer(
      frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    for page in DashboardPage.allCases {
      container.show(page: page, selection: .constant(page), store: store)
      XCTAssertEqual(container.selection, page)
      XCTAssertEqual(container.subviews.count, 1)
      XCTAssertEqual(container.subviews.first?.frame, container.bounds)
    }
    XCTAssertNil(store.apple)
    XCTAssertNil(store.revenue)
    XCTAssertTrue(store.busy("tiktok"))
  }

  @MainActor func testCachedPageResumesFirstPaintAfterBeingDetachedDuringLoading() async {
    var constructed = false
    let host = NSHostingView(
      rootView: ProgressiveContent(identity: "cached") {
        Text("Chargement").frame(width: 240, height: 120)
      } content: {
        constructed = true
        return Text("Données").frame(width: 240, height: 120)
      })
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    XCTAssertFalse(constructed)
    window.contentView = nil
    for _ in 0..<10 { await Task.yield() }
    XCTAssertFalse(constructed, "Detached pages must not mount charts in the background.")
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    await waitUntil { constructed }
    XCTAssertTrue(
      constructed, "Returning must resume loading even if the first paint was interrupted.")
  }

  @MainActor func testSavedValuesAppearBeforeTheNetworkRequestCompletes() async {
    let store = DashboardStore(loadConfiguration: false)
    let source = ControlledCharts()
    let cached = RCChart(
      values: [RCValue(cohort: 0, measure: 0, value: 12)], measures: nil, summary: nil)
    let task = Task {
      await store.load(
        "revenue", current: store.revenue, cached: { cached },
        fetch: { try await source.fetch("revenue", range: store.range) },
        assign: { store.revenue = $0 })
    }
    await source.waitForRequests(1)
    XCTAssertEqual(store.revenue?.values.first?.value, 12)
    XCTAssertTrue(
      store.busy("revenue"), "The source should keep refreshing after its saved value is visible.")
    await source.finish("revenue", value: 25)
    await task.value
    XCTAssertEqual(store.revenue?.values.first?.value, 25)
    XCTAssertFalse(store.busy("revenue"))
  }

  @MainActor func testNetworkFailureKeepsSavedValuesVisible() async {
    let store = DashboardStore(loadConfiguration: false)
    let cached = RCOverview(metrics: [RCMetric(id: "mrr", value: 12)])
    await store.load(
      "overview", current: store.overview, cached: { cached },
      fetch: { throw DashboardError(message: "Offline test") }, assign: { store.overview = $0 })
    XCTAssertEqual(store.overview?.value("mrr"), 12)
    XCTAssertFalse(store.busy("overview"))
    XCTAssertNotNil(store.errors["overview"])
  }

  @MainActor func testRefreshKeepsCurrentValuesAndDoesNotReadOlderCache() async {
    let store = DashboardStore(loadConfiguration: false)
    store.overview = RCOverview(metrics: [RCMetric(id: "mrr", value: 25)])
    var cacheRead = false
    await store.load(
      "overview", current: store.overview,
      cached: {
        cacheRead = true
        return RCOverview(metrics: [RCMetric(id: "mrr", value: 1)])
      }, fetch: { throw DashboardError(message: "Offline test") }, assign: { store.overview = $0 })
    XCTAssertFalse(cacheRead)
    XCTAssertEqual(store.overview?.value("mrr"), 25)
  }

  @MainActor func testLoadingChangesOnlyInvalidateTheirOwnSource() {
    let store = DashboardStore(loadConfiguration: false)
    let appleInvalidations = Mutex(0)
    withObservationTracking {
      _ = store.busy("apple")
    } onChange: {
      appleInvalidations.withLock { $0 += 1 }
    }
    store.loading.insert("tiktok")
    store.loading.remove("tiktok")
    XCTAssertEqual(appleInvalidations.withLock { $0 }, 0)
    store.loading.insert("apple")
    XCTAssertEqual(appleInvalidations.withLock { $0 }, 1)
    XCTAssertTrue(store.busy("apple"))
  }

  @MainActor func testReturningToPeriodRestoresOnlyItsOwnValuesDuringRefresh() async {
    let store = DashboardStore(loadConfiguration: false)
    store.config.launchDate = Day.shift(Day.key(Date()), -100)
    store.period = .week
    let week = ControlledCharts()
    let initial = Task { await store.refreshPeriod(using: { try await week.fetch($0, range: $1) }) }
    await week.waitForRequests()
    await week.finish("trials", value: 7)
    await week.finish("paying", value: 8)
    await initial.value
    store.period = .month
    let month = ControlledCharts()
    let next = Task { await store.refreshPeriod(using: { try await month.fetch($0, range: $1) }) }
    await month.waitForRequests()
    XCTAssertNil(store.trials, "Values from another period must never be shown.")
    XCTAssertNil(store.paying)
    await month.finish("trials", value: 30)
    await month.finish("paying", value: 31)
    await next.value
    store.period = .week
    let again = ControlledCharts()
    let revisit = Task {
      await store.refreshPeriod(using: { try await again.fetch($0, range: $1) })
    }
    await again.waitForRequests()
    XCTAssertEqual(store.trials?.values.first?.value, 7)
    XCTAssertEqual(store.paying?.values.first?.value, 8)
    XCTAssertTrue(store.busy("trials"))
    await again.finish("trials", value: 9)
    await again.finish("paying", value: 10)
    await revisit.value
    XCTAssertEqual(store.trials?.values.first?.value, 9)
  }

  @MainActor private func waitUntil(_ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(3)
    while !condition(), Date() < deadline { await Task.yield() }
  }
}

private actor ControlledCharts {
  private var requests: [String: CheckedContinuation<ServiceResult<RCChart>, Error>] = [:]
  private var waiter: CheckedContinuation<Void, Never>?
  private var expectedCount = 2
  func fetch(_ key: String, range: PeriodRange) async throws -> ServiceResult<RCChart> {
    try await withCheckedThrowingContinuation { continuation in
      requests[key] = continuation
      if requests.count >= expectedCount {
        waiter?.resume()
        waiter = nil
      }
    }
  }
  func waitForRequests(_ count: Int = 2) async {
    expectedCount = count
    if requests.count >= count { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func finish(_ key: String, value: Double) {
    requests.removeValue(forKey: key)?.resume(
      returning: ServiceResult(
        value:
          RCChart(
            values: [RCValue(cohort: 0, measure: 0, value: value)], measures: nil, summary: nil)))
  }
}

private struct FrameProbe: NSViewRepresentable {
  let register: (NSView) -> Void
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    register(view)
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}
