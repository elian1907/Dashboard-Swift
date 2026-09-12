import CoreText
import SwiftUI

enum Theme {
  static let background = Color(hex: 0x202123), text = Color(hex: 0xf2f2f3),
    muted = Color(hex: 0xb8bbc1)
  static let downloads = Color(hex: 0x8aaff3), users = Color(hex: 0xe6b16b),
    revenue = Color(hex: 0xb29be7), tiktok = Color(hex: 0xdf98b2),
    subscriptions = Color(hex: 0x85c4d4), other = Color(hex: 0x969ba4)
  static let palette: [Color] = [downloads, revenue, users, tiktok, subscriptions, other]
  static func heading(_ size: CGFloat = 28) -> Font {
    .custom("Bricolage Grotesque", size: size).weight(.heavy)
  }
  static func body(_ size: CGFloat = 13) -> Font {
    .custom("Hanken Grotesk", size: size).weight(.bold)
  }
  static func registerFonts() {
    for name in ["bricolage", "hanken"] {
      if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }
    }
  }
}
extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: 1)
  }
}
/// Metric cards share a known width. Measure each at that width instead of
/// asking a flexible HStack to repeatedly negotiate their minimum/ideal sizes.
struct MetricRow: Layout {
  var spacing: CGFloat = 16
  struct Cache {
    var width: CGFloat?
    var size: CGSize = .zero
  }
  func makeCache(subviews: Subviews) -> Cache { Cache() }
  func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    guard !subviews.isEmpty else { return .zero }
    let gaps = spacing * CGFloat(subviews.count - 1)
    let width =
      proposal.width.flatMap { $0.isFinite ? $0 : nil }
      ?? (subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0) * CGFloat(subviews.count)
      + gaps
    if cache.width == width { return cache.size }
    let child = ProposedViewSize(width: max(0, width - gaps) / CGFloat(subviews.count), height: nil)
    let height = subviews.map { $0.sizeThatFits(child).height }.max() ?? 0
    cache.width = width
    cache.size = CGSize(width: width, height: height)
    return cache.size
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
  ) {
    guard !subviews.isEmpty else { return }
    let width =
      max(0, bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
    for (index, view) in subviews.enumerated() {
      view.place(
        at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
        anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
    }
  }
}

/// Keep native Button semantics, with visible feedback at mouse-down even before
/// a destination has been laid out. Release/drag-out and keyboard activation stay native.
struct DashboardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
      .transaction { $0.animation = nil }
  }
}

struct GlassPanel<Content: View>: View {
  var title: String? = nil
  var padding: CGFloat = 20
  var interactive = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title { Text(title).font(Theme.heading(17)) }
      content
    }.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
      .glassEffect(
        (reduceTransparency ? Glass.regular : .clear).interactive(interactive),
        in: .rect(cornerRadius: 24)
      )
      .contentShape(RoundedRectangle(cornerRadius: 24))
  }
}

/// Each control uses the system material and button interaction, without a second painted surface.
struct GlassSelector<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [(value: Value, label: String)]

  var body: some View {
    GlassEffectContainer(spacing: 4) {
      HStack(spacing: 6) {
        ForEach(options, id: \.value) { option in
          Button {
            guard selection != option.value else { return }
            selection = option.value
          } label: {
            Text(option.label).font(Theme.body(12)).lineLimit(1)
              .minimumScaleFactor(0.8).padding(.horizontal, 14).padding(.vertical, 9)
              .glassEffect(
                (selection == option.value ? Glass.clear : .regular).interactive(), in: .capsule)
          }
          .buttonStyle(DashboardButtonStyle())
          .foregroundStyle(selection == option.value ? Theme.text : Theme.muted)
          .accessibilityAddTraits(selection == option.value ? .isSelected : [])
        }
      }
    }.accessibilityElement(children: .contain).accessibilityLabel(title)
  }
}

struct DashboardBackdrop: View {
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color(hex: 0x17181a)
        Ellipse().fill(Color(hex: 0x76736e).opacity(0.42))
          .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.45)
          .blur(radius: 80).rotationEffect(.degrees(-28))
          .offset(x: geometry.size.width * 0.2, y: -geometry.size.height * 0.35)
        Ellipse().fill(Color(hex: 0x56595f).opacity(0.42))
          .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.4)
          .blur(radius: 95).rotationEffect(.degrees(-30))
          .offset(x: -geometry.size.width * 0.25, y: geometry.size.height * 0.15)
      }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
    }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
  }
}
struct LoadingShimmer: View {
  var height: CGFloat = 24
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
      let phase =
        reduceMotion
        ? 0.5
        : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
      RoundedRectangle(cornerRadius: 8).fill(
        LinearGradient(
          colors: [.white.opacity(0.045), .white.opacity(0.13), .white.opacity(0.045)],
          startPoint: UnitPoint(x: phase * 2 - 1, y: 0), endPoint: UnitPoint(x: phase * 2, y: 0.2)))
    }.frame(height: height).accessibilityLabel("Chargement des données")
  }
}
struct MetricTile: View {
  let title: String
  let value: String
  let icon: String
  let color: Color
  var loading = false
  var change: String? = nil
  var points: [DataPoint] = []
  var chartLoading = false
  var interactive = false
  var body: some View {
    GlassPanel(padding: 18, interactive: interactive) {
      HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
          .frame(width: 32, height: 32).background(
            color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        Text(title).font(Theme.body(12)).foregroundStyle(Theme.muted).lineLimit(2)
        Spacer(minLength: 0)
      }
      HStack(alignment: .firstTextBaseline) {
        if loading {
          LoadingShimmer(height: 25).frame(width: 95).padding(.vertical, 6)
        } else {
          Text(value).font(Theme.heading(33)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        Spacer(minLength: 2)
        if !loading, let change {
          Text(change).font(Theme.body(10)).padding(.horizontal, 7).padding(.vertical, 4)
            .background(.white.opacity(0.06), in: Capsule())
        }
      }
      if chartLoading {
        LoadingShimmer(height: 34)
      } else if !points.isEmpty {
        NativeTimeChart(
          series: [PlotSeries(id: title, name: title, color: color, points: points)], height: 38,
          compact: true)
      }
    }
  }
}
struct SmallStat: View {
  let title: String
  let value: String
  var loading = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(Theme.body(11)).foregroundStyle(Theme.muted)
      if loading {
        LoadingShimmer(height: 20).frame(width: 65)
      } else {
        Text(value).font(Theme.heading(22)).monospacedDigit()
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct EmptyData: View {
  var text = "Aucune donnée sur cette période"
  var height: CGFloat = 180
  var body: some View {
    Text(text).font(Theme.body()).foregroundStyle(Theme.muted).frame(
      maxWidth: .infinity, minHeight: height)
  }
}
