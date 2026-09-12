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
struct GlassPanel<Content: View>: View {
  var title: String? = nil
  var padding: CGFloat = 20
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title { Text(title).font(Theme.heading(17)) }
      content
    }.padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(
      Color.white.opacity(0.015)
    ).glassEffect(.regular, in: .rect(cornerRadius: 22))
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
  var body: some View {
    GlassPanel(padding: 18) {
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
