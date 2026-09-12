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
