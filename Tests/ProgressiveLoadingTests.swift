import AppKit
import SwiftUI
import XCTest

@testable import LosloDashboard

final class ProgressiveLoadingTests: XCTestCase {
  @MainActor func testReadyCardDoesNotWaitForSlowerCard() async {
    let store = DashboardStore(loadConfiguration: false)
    let source = ControlledCharts()
    let request = Task { await store.refreshPeriod(using: source.fetch) }
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
    let oldRequest = Task { await store.refreshPeriod(using: oldSource.fetch) }
    await oldSource.waitForRequests()
    store.period = .week
    let newSource = ControlledCharts()
    let newRequest = Task { await store.refreshPeriod(using: newSource.fetch) }
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

  @MainActor private func waitUntil(_ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(3)
    while !condition(), Date() < deadline { await Task.yield() }
  }
}

private actor ControlledCharts {
  private var requests: [String: CheckedContinuation<ServiceResult<RCChart>, Error>] = [:]
  private var waiter: CheckedContinuation<Void, Never>?
  func fetch(_ key: String, range: PeriodRange) async throws -> ServiceResult<RCChart> {
    try await withCheckedThrowingContinuation { continuation in
      requests[key] = continuation
      if requests.count == 2 {
        waiter?.resume()
        waiter = nil
      }
    }
  }
  func waitForRequests() async {
    if requests.count == 2 { return }
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
