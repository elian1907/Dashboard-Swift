import Foundation
import simd

struct GlobeMesh: Sendable {
  struct Cell: Sendable {
    let center: SIMD3<Double>
    let corners: [SIMD3<Double>]
  }
  let cells: [Cell]
  let centroids: [String: [Double]]

  static func load() throws -> GlobeMesh {
    guard let meshURL = Bundle.main.url(forResource: "globe-mesh", withExtension: "bin"),
      let centersURL = Bundle.main.url(forResource: "globe-centroids", withExtension: "json")
    else { throw GeometryError.invalidMesh }
    return try decode(
      Data(contentsOf: meshURL),
      centroids: JSONDecoder().decode([String: [Double]].self, from: Data(contentsOf: centersURL)))
  }

  static func decode(_ data: Data, centroids: [String: [Double]]) throws -> GlobeMesh {
    guard data.count >= 8, data.prefix(4) == Data("LSG1".utf8) else {
      throw GeometryError.invalidMesh
    }
    return try data.withUnsafeBytes { bytes in
      let count = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
      guard (1...36002).contains(count) else { throw GeometryError.invalidMesh }
      var offset = 8
      func vector() throws -> SIMD3<Double> {
        guard offset + 12 <= bytes.count else { throw GeometryError.invalidMesh }
        var result = SIMD3<Double>.zero
        for axis in 0..<3 {
          let bits = UInt32(
            littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
          result[axis] = Double(Float(bitPattern: bits))
          offset += 4
        }
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite,
          abs(simd_length(result) - 1) < 0.001
        else { throw GeometryError.invalidMesh }
        return result
      }
      var cells: [Cell] = []
      cells.reserveCapacity(count)
      for _ in 0..<count {
        let center = try vector()
        guard offset < bytes.count else { throw GeometryError.invalidMesh }
        let corners = Int(bytes[offset])
        offset += 1
        guard (5...6).contains(corners) else { throw GeometryError.invalidMesh }
        cells.append(Cell(center: center, corners: try (0..<corners).map { _ in try vector() }))
      }
      guard offset == bytes.count else { throw GeometryError.invalidMesh }
      return GlobeMesh(cells: cells, centroids: centroids)
    }
  }
  enum GeometryError: Error { case invalidMesh }
}

struct GlobeSnapshot: Sendable {
  struct Marker: Sendable {
    let country: CountryRow
    let position: SIMD3<Double>
    let threshold: Double
  }
  let mesh: GlobeMesh
  let countries: [CountryRow]
  let markers: [Marker]
  let highlighted: [Bool]

  init(mesh: GlobeMesh, countries: [CountryRow]) throws {
    self.mesh = mesh
    self.countries = countries
    let maximum = max(1, countries.map(\.units).filter(\.isFinite).max() ?? 1)
    markers = countries.compactMap { country in
      guard country.units.isFinite, country.units > 0,
        let coordinates = mesh.centroids[country.code], coordinates.count == 2
      else { return nil }
      let lon = coordinates[0] * .pi / 180
      let lat = coordinates[1] * .pi / 180
      return Marker(
        country: country,
        position: SIMD3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)),
        threshold: cos((1 + sqrt(country.units / maximum) * 5) * .pi / 180))
    }
    let targets = markers
    highlighted = try mesh.cells.enumerated().map { index, cell in
      if index.isMultiple(of: 256) { try Task.checkCancellation() }
      return targets.contains { simd_dot(cell.center, $0.position) > $0.threshold }
    }
  }
}

/// Geometry is bundled and prepared once off the main thread. Changing the period
/// only recomputes country highlights; it never retessellates or fetches a map.
actor GlobeMeshCache {
  static let shared = GlobeMeshCache()
  private var meshTask: Task<GlobeMesh, Error>?
  func snapshot(for countries: [CountryRow]) async throws -> GlobeSnapshot {
    if meshTask == nil {
      meshTask = Task.detached(priority: .userInitiated) { try GlobeMesh.load() }
    }
    let mesh: GlobeMesh
    do { mesh = try await meshTask!.value } catch {
      meshTask = nil
      throw error
    }
    try Task.checkCancellation()
    let preparation = Task.detached(priority: .userInitiated) {
      try GlobeSnapshot(mesh: mesh, countries: countries)
    }
    return try await withTaskCancellationHandler {
      try await preparation.value
    } onCancel: {
      preparation.cancel()
    }
  }
}

struct GlobeProjection {
  let radius: Double
  let center: CGPoint
  private let cosY: Double, sinY: Double, cosX: Double, sinX: Double
  init(size: CGSize, yaw: Double, pitch: Double) {
    radius = min(size.width, size.height) * (302 / 620.0)
    center = CGPoint(x: size.width / 2, y: size.height / 2)
    cosY = cos(yaw * .pi / 180)
    sinY = sin(yaw * .pi / 180)
    cosX = cos(pitch * .pi / 180)
    sinX = sin(pitch * .pi / 180)
  }
  func project(_ point: SIMD3<Double>) -> (point: CGPoint, depth: Double) {
    let x = point.x * cosY + point.z * sinY
    let z = -point.x * sinY + point.z * cosY
    return (
      CGPoint(x: center.x - radius * x, y: center.y - radius * (point.y * cosX - z * sinX)),
      point.y * sinX + z * cosX
    )
  }
}

struct GlobeMotion {
  private(set) var yaw = -80.0
  private(set) var pitch = 18.0
  private(set) var spinning = false
  private var started = 0.0
  func angle(at time: TimeInterval) -> Double {
    yaw - (spinning ? max(0, time - started) * 360 / 65 : 0)
  }
  mutating func setSpinning(_ value: Bool, at time: TimeInterval) {
    guard value != spinning else { return }
    yaw = angle(at: time).truncatingRemainder(dividingBy: 360)
    started = time
    spinning = value
  }
  mutating func orient(yaw: Double, pitch: Double, at time: TimeInterval) {
    self.yaw = yaw.truncatingRemainder(dividingBy: 360)
    self.pitch = min(90, max(-90, pitch))
    started = time
  }
}
