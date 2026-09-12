import Foundation
import XCTest
import simd

@testable import LosloDashboard

final class GlobeTests: XCTestCase {
  func testBundledMeshContainsFiniteUnitCellsAndMainlandCountryPositions() throws {
    let mesh = try GlobeMesh.load()
    XCTAssertGreaterThan(mesh.cells.count, 9000)
    XCTAssertLessThan(mesh.cells.count, 11000)
    for cell in mesh.cells {
      XCTAssertEqual(simd_length(cell.center), 1, accuracy: 0.0001)
      XCTAssertTrue((5...6).contains(cell.corners.count))
      XCTAssertGreaterThan(cell.center.y, sin(-60 * .pi / 180), "Antarctica should be omitted.")
      for corner in cell.corners { XCTAssertEqual(simd_length(corner), 1, accuracy: 0.0001) }
    }
    let france = try XCTUnwrap(mesh.centroids["FR"])
    XCTAssertEqual(france[0], 2.5, accuracy: 2)
    XCTAssertEqual(
      france[1], 46.5, accuracy: 2, "Overseas territories must not displace mainland France.")
  }

  func testProjectionShowsEuropeWithoutMirroringEastAndWest() {
    let projection = GlobeProjection(size: CGSize(width: 360, height: 360), yaw: -80, pitch: 18)
    func point(longitude: Double, latitude: Double) -> SIMD3<Double> {
      let lon = longitude * .pi / 180
      let lat = latitude * .pi / 180
      return SIMD3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
    }
    let center = projection.project(point(longitude: 10, latitude: 18))
    XCTAssertEqual(center.point.x, 180, accuracy: 0.001)
    XCTAssertEqual(center.point.y, 180, accuracy: 0.001)
    XCTAssertEqual(center.depth, 1, accuracy: 0.001)
    XCTAssertLessThan(projection.project(point(longitude: 0, latitude: 18)).point.x, center.point.x)
    XCTAssertGreaterThan(
      projection.project(point(longitude: 20, latitude: 18)).point.x, center.point.x)
    XCTAssertLessThan(projection.project(point(longitude: 190, latitude: -18)).depth, 0)
  }

  func testHighlightsUseTheCurrentDownloadsAndIgnoreUnmappableOrInvalidValues() throws {
    let mesh = try GlobeMesh.load()
    let snapshot = try GlobeSnapshot(
      mesh: mesh,
      countries: [
        CountryRow(code: "FR", units: 100), CountryRow(code: "US", units: 0),
        CountryRow(code: "BE", units: -1), CountryRow(code: "CA", units: .nan),
        CountryRow(code: "ZZ", units: 5),
      ])
    XCTAssertEqual(snapshot.markers.map(\.country.code), ["FR"])
    XCTAssertEqual(snapshot.highlighted.count, mesh.cells.count)
    XCTAssertGreaterThan(snapshot.highlighted.filter { $0 }.count, 0)
    let cleared = try GlobeSnapshot(mesh: mesh, countries: [])
    XCTAssertTrue(cleared.markers.isEmpty)
    XCTAssertFalse(cleared.highlighted.contains(true), "Old period highlights must be cleared.")
  }

  func testPauseResumeAndDraggingPreserveTheDisplayedOrientation() {
    var motion = GlobeMotion()
    motion.setSpinning(true, at: 10)
    XCTAssertEqual(motion.angle(at: 42.5), -260, accuracy: 0.001)
    motion.setSpinning(false, at: 42.5)
    XCTAssertEqual(motion.angle(at: 100), -260, accuracy: 0.001)
    motion.setSpinning(true, at: 100)
    XCTAssertEqual(motion.angle(at: 100), -260, accuracy: 0.001)
    XCTAssertEqual(motion.angle(at: 101), -260 - 360 / 65.0, accuracy: 0.001)
    let angle = motion.angle(at: 101)
    motion.setSpinning(false, at: 101)
    motion.orient(yaw: angle + 30, pitch: 120, at: 101)
    XCTAssertEqual(motion.angle(at: 200), angle + 30, accuracy: 0.001)
    XCTAssertEqual(motion.pitch, 90)
    motion.orient(yaw: 725, pitch: -100, at: 200)
    XCTAssertEqual(motion.angle(at: 200), 5)
    XCTAssertEqual(motion.pitch, -90)
  }

  func testInvalidOrTruncatedMeshFailsWithoutReadingBeyondItsBuffer() {
    XCTAssertThrowsError(try GlobeMesh.decode(Data(), centroids: [:]))
    XCTAssertThrowsError(try GlobeMesh.decode(Data("LSG1".utf8), centroids: [:]))
    XCTAssertThrowsError(try GlobeMesh.decode(Data([76, 83, 71, 49, 1, 0, 0, 0]), centroids: [:]))
    XCTAssertThrowsError(
      try GlobeMesh.decode(Data([76, 83, 71, 49, 255, 255, 255, 255]), centroids: [:]))
  }
}
