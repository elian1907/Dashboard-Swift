import AppKit
import SwiftUI

struct NativeGlobe: View {
  let countries: [CountryRow]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var snapshot: GlobeSnapshot?
  @State private var failed = false
  @State private var paused = false
  @State private var visible = false
  @State private var hovering = false
  @State private var hovered: CountryRow?
  @State private var motion = GlobeMotion()
  @State private var dragOrigin: (yaw: Double, pitch: Double)?
  private var shouldSpin: Bool {
    visible && snapshot != nil && !paused && !reduceMotion && !hovering && dragOrigin == nil
  }
  private var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Spacer()
        Button(paused ? "Reprendre la rotation" : "Mettre en pause") { paused.toggle() }
          .font(Theme.body(11)).buttonStyle(.glass).buttonBorderShape(.capsule)
          .disabled(reduceMotion || snapshot == nil)
      }
      GeometryReader { geometry in
        ZStack {
          if let snapshot {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !motion.spinning)) {
              timeline in
              let yaw = motion.angle(at: timeline.date.timeIntervalSinceReferenceDate)
              let pitch = motion.pitch
              DataCrossfade(value: snapshot.countries) {
                Canvas(rendersAsynchronously: true) { context, size in
                  context.withCGContext { cg in
                    GlobeRenderer.draw(snapshot, in: cg, size: size, yaw: yaw, pitch: pitch)
                  }
                }
              }
            }
          } else if failed {
            EmptyData(text: "Globe indisponible", height: 300)
          } else {
            LoadingShimmer(height: 300).clipShape(Circle()).padding(10)
          }
        }
        .contentShape(Circle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              if dragOrigin == nil {
                dragOrigin = (motion.angle(at: now), motion.pitch)
                motion.setSpinning(false, at: now)
              }
              guard let origin = dragOrigin else { return }
              hovered = nil
              motion.orient(
                yaw: origin.yaw - value.translation.width * 0.35,
                pitch: origin.pitch + value.translation.height * 0.35, at: now)
            }
            .onEnded { _ in dragOrigin = nil }
        )
        .onContinuousHover { phase in
          switch phase {
          case .ended:
            hovering = false
            hovered = nil
          case .active(let location):
            hovering = true
            guard dragOrigin == nil, let snapshot else { return }
            let projection = GlobeProjection(
              size: geometry.size, yaw: motion.angle(at: now), pitch: motion.pitch)
            var nearest: CountryRow?
            var nearestDistance = 15.0
            for marker in snapshot.markers {
              let point = projection.project(marker.position)
              guard point.depth > 0.03 else { continue }
              let distance = hypot(point.point.x - location.x, point.point.y - location.y)
              if distance < nearestDistance {
                nearest = marker.country
                nearestDistance = distance
              }
            }
            if hovered?.id != nearest?.id { hovered = nearest }
          }
        }
        .overlay(alignment: .bottom) {
          if let hovered {
            VStack(spacing: 4) {
              Text(hovered.flag + " " + hovered.name)
              Text(Analytics.number(hovered.units) + " téléchargements").foregroundStyle(
                Theme.muted)
            }.font(Theme.body(12)).padding(12)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
              .allowsHitTesting(false)
          }
        }
        .background { GlobeVisibility { visible = $0 }.allowsHitTesting(false) }
        .focusable()
        .onKeyPress(.leftArrow) {
          turn(horizontal: 5)
          return .handled
        }
        .onKeyPress(.rightArrow) {
          turn(horizontal: -5)
          return .handled
        }
        .onKeyPress(.upArrow) {
          turn(vertical: 5)
          return .handled
        }
        .onKeyPress(.downArrow) {
          turn(vertical: -5)
          return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Globe des téléchargements")
        .accessibilityHint(
          "Fais glisser ou utilise les flèches pour tourner. Les chiffres sont disponibles dans le classement des pays."
        )
      }.frame(height: 330)
    }
    .onChange(of: shouldSpin, initial: true) { _, value in motion.setSpinning(value, at: now) }
    .task(id: countries) {
      do {
        let prepared = try await GlobeMeshCache.shared.snapshot(for: countries)
        try Task.checkCancellation()
        snapshot = prepared
        failed = false
        hovered = nil
      } catch is CancellationError {
      } catch { failed = true }
    }
  }
  private func turn(horizontal: Double = 0, vertical: Double = 0) {
    let yaw = motion.angle(at: now)
    paused = true
    motion.setSpinning(false, at: now)
    motion.orient(yaw: yaw + horizontal, pitch: motion.pitch + vertical, at: now)
    hovered = nil
  }
}

/// Two batched paths reproduce the web globe's land cells and highlighted areas.
/// Only the projection changes each frame; no geometry or data work runs here.
private enum GlobeRenderer {
  static let sphereGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x6b7079), color(0x393d44), color(0x393d44)] as CFArray,
    locations: [0, 0.55, 1])!
  static let limbGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1a1c20, alpha: 0), color(0x1a1c20, alpha: 0.22)] as CFArray,
    locations: [0, 1])!
  static let landColor = color(0x969da8), markerColor = color(0xaccbff)
  static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
      red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
      blue: CGFloat(hex & 255) / 255, alpha: alpha)
  }
  static func draw(
    _ snapshot: GlobeSnapshot, in context: CGContext, size: CGSize, yaw: Double, pitch: Double
  ) {
    let projection = GlobeProjection(size: size, yaw: yaw, pitch: pitch)
    let radius = projection.radius
    let center = projection.center
    context.saveGState()
    defer { context.restoreGState() }
    context.addEllipse(
      in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.clip()
    context.drawRadialGradient(
      sphereGradient,
      startCenter: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
      startRadius: radius * 0.08,
      endCenter: center, endRadius: radius * 1.08,
      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let land = CGMutablePath()
    let highlights = CGMutablePath()
    for (index, cell) in snapshot.mesh.cells.enumerated() {
      guard projection.project(cell.center).depth > 0.03 else { continue }
      let path = snapshot.highlighted[index] ? highlights : land
      for (corner, vertex) in cell.corners.enumerated() {
        let point = projection.project(vertex).point
        if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
    }
    context.setFillColor(landColor)
    context.addPath(land)
    context.fillPath()
    context.setFillColor(markerColor)
    context.addPath(highlights)
    context.fillPath()
    context.drawRadialGradient(
      limbGradient, startCenter: center, startRadius: radius * 0.72,
      endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
  }
}

/// Cached page hosts detach without destroying their SwiftUI state. Stop the
/// animation when detached, hidden, minimized, or when the app loses focus.
private struct GlobeVisibility: NSViewRepresentable {
  let changed: (Bool) -> Void
  func makeNSView(context: Context) -> Observer {
    let view = Observer()
    view.changed = changed
    return view
  }
  func updateNSView(_ view: Observer, context: Context) { view.changed = changed }
  static func dismantleNSView(_ view: Observer, coordinator: ()) { view.changed = nil }
  final class Observer: NSView {
    var changed: ((Bool) -> Void)?
    private var notifications: [NSObjectProtocol] = []
    override init(frame: NSRect) {
      super.init(frame: frame)
      for name in [
        NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
        NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
      ] {
        notifications.append(
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] _ in self?.publish()
          })
      }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { notifications.forEach { NotificationCenter.default.removeObserver($0) } }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      publish()
    }
    override func viewDidHide() {
      super.viewDidHide()
      publish()
    }
    override func viewDidUnhide() {
      super.viewDidUnhide()
      publish()
    }
    private func publish() {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.changed?(
          self.window?.isVisible == true && !self.isHiddenOrHasHiddenAncestor && NSApp.isActive)
      }
    }
  }
}
