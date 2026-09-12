import Charts
import SwiftUI

struct PlotSeries: Identifiable {
  let id: String
  let name: String
  let color: Color
  let points: [DataPoint]
  let loading: Bool
  let unit: String
  struct Datum: Identifiable {
    let date: String
    let day: Date
    let value: Double
    let segment: Int
    var id: String { date }
  }
  let values: [Datum]
  init(
    id: String, name: String, color: Color, points: [DataPoint], loading: Bool = false,
    unit: String = ""
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.points = points
    self.loading = loading
    self.unit = unit
    var segment = 0
    values = points.compactMap { p in
      guard let value = p.value, value.isFinite else {
        segment += 1
        return nil
      }
      return Datum(date: p.date, day: Day.parse(p.date), value: value, segment: segment)
    }
  }
}
struct NativeTimeChart: View {
  var series: [PlotSeries]
  var height: CGFloat = 220
  var bars = false
  var dots = false
  var compact = false
  @State private var selected: String?
  private let timeline: ChartTimeline
  var labels: [String] { timeline.labels }
  init(
    series: [PlotSeries], height: CGFloat = 220, bars: Bool = false, dots: Bool = false,
    compact: Bool = false
  ) {
    self.series = series
    self.height = height
    self.bars = bars
    self.dots = dots
    self.compact = compact
    timeline = ChartTimeline(series.flatMap { $0.points.map(\.date) })
  }
  var ready: Bool { series.contains { !$0.values.isEmpty } }
  var body: some View {
    if series.contains(where: { $0.loading }) && !ready {
      LoadingShimmer(height: height)
    } else if !ready {
      if !compact { EmptyData(height: height) } else { Color.clear.frame(height: height) }
    } else if compact {
      Sparkline(series: series, timeline: timeline).frame(height: height).accessibilityHidden(true)
    } else {
      ProgressiveContent(identity: presentationKey) {
        LoadingShimmer(height: height)
      } content: {
        chart
      }
    }
  }
  private var presentationKey: String {
    [
      String(bars), String(dots), labels.first ?? "", labels.last ?? "",
      series.map { $0.id + ":" + $0.name }.joined(separator: "|"),
    ].joined(separator: ";")
  }
  private var chart: some View {
    VStack(alignment: .leading, spacing: 12) {
      Chart {
        ForEach(series) { s in
          ForEach(s.values) { p in
            if bars {
              BarMark(x: .value("Date", p.day, unit: .day), y: .value(s.name, p.value))
                .foregroundStyle(s.color).cornerRadius(3)
            } else {
              LineMark(
                x: .value("Date", p.day), y: .value(s.name, p.value),
                series: .value("Segment", s.id + String(p.segment))
              )
              .foregroundStyle(dots ? Color(hex: 0xb9bdc4) : s.color).lineStyle(
                StrokeStyle(lineWidth: compact ? 2 : 2.5)
              ).interpolationMethod(dots ? .linear : .monotone)
              if dots {
                PointMark(x: .value("Date", p.day), y: .value(s.name, p.value))
                  .foregroundStyle(s.color).symbolSize(38)
              }
            }
          }
        }
        if let selected, !compact {
          RuleMark(x: .value("Date", Day.parse(selected))).foregroundStyle(.white.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
      }
      .chartXScale(
        domain: Day.parse(
          labels.first ?? Day.key(Date()))...Day.parse(
            bars ? Day.shift(labels.last ?? Day.key(Date()), 1) : labels.last ?? Day.key(Date()))
      )
      .chartXAxis(compact ? .hidden : .automatic).chartYAxis(compact ? .hidden : .automatic)
      .chartLegend(.hidden)
      .chartXAxis {
        if !compact {
          AxisMarks(values: .automatic(desiredCount: 5)) { value in
            AxisValueLabel(
              format: .dateTime.day().month().locale(Locale(identifier: "fr_FR")), centered: false
            ).font(Theme.body(10))
              .foregroundStyle(Theme.muted)
          }
        }
      }
      .chartYAxis {
        if !compact {
          AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5])).foregroundStyle(
              .white.opacity(0.10))
            AxisValueLabel().font(Theme.body(10)).foregroundStyle(Theme.muted)
          }
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geo in
          Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
            switch phase {
            case .active(let location):
              guard let frame = proxy.plotFrame else { return }
              let rect = geo[frame]
              guard rect.contains(location),
                let date: Date = proxy.value(atX: location.x - rect.minX)
              else {
                selected = nil
                return
              }
              let nearest = timeline.nearest(to: date)
              if nearest != selected { selected = nearest }
            case .ended: selected = nil
            }
          }
        }
      }
      .frame(height: height)
      .overlay(alignment: .topTrailing) {
        if let selected {
          ChartTooltip(series: series, selected: selected).padding(6)
        }
      }
      .accessibilityLabel(series.map(\.name).joined(separator: ", "))
      .focusable(!compact).onKeyPress(.leftArrow) {
        move(-1)
        return .handled
      }.onKeyPress(.rightArrow) {
        move(1)
        return .handled
      }.onKeyPress(.escape) {
        selected = nil
        return .handled
      }
    }
  }
  private func move(_ delta: Int) {
    guard !labels.isEmpty else { return }
    let i = selected.flatMap { labels.firstIndex(of: $0) } ?? labels.count - 1
    selected = labels[max(0, min(labels.count - 1, i + delta))]
  }
}
struct DonutItem: Identifiable {
  var id: String
  var label: String
  var value: Double
  var color: Color
}
struct NativeDonut: View {
  var items: [DonutItem]
  var height: CGFloat = 190
  @State private var selected: Double?
  @State private var hovered: String?
  var valid: [DonutItem] { items.filter { $0.value.isFinite && $0.value > 0 } }
  var total: Double { valid.reduce(0) { $0 + $1.value } }
  var active: DonutItem? {
    if let hovered { return items.first { $0.id == hovered } }
    guard let selected else { return nil }
    var sum = 0.0
    return valid.first {
      sum += $0.value
      return selected <= sum
    }
  }
  var body: some View {
    if total <= 0 {
      EmptyData(text: "Aucune répartition disponible", height: height)
    } else {
      ProgressiveContent(identity: "distribution") {
        LoadingShimmer(height: height + CGFloat(items.count) * 30)
      } content: {
        distribution
      }
    }
  }
  private var distribution: some View {
    VStack(spacing: 16) {
      Chart(valid) { item in
        SectorMark(
          angle: .value(item.label, item.value), innerRadius: .ratio(0.7), angularInset: 2
        ).foregroundStyle(item.color).cornerRadius(4).opacity(
          active == nil || active?.id == item.id ? 1 : 0.35)
      }
      .chartAngleSelection(value: $selected).chartLegend(.hidden).frame(height: height)
      .overlay {
        VStack(spacing: 4) {
          Text(Analytics.number(active?.value ?? total)).font(Theme.heading(27))
          Text(active?.label ?? "Total").font(Theme.body(11)).foregroundStyle(Theme.muted)
        }.allowsHitTesting(false)
      }
      ForEach(items) { item in legendRow(item) }
    }
  }

  private func legendRow(_ item: DonutItem) -> some View {
    let value = Analytics.number(item.value)
    let percent = Analytics.number(item.value / total * 100, digits: 1) + " %"
    let hint = "\(item.label) : \(value) · \(percent)"
    return HStack {
      Circle().fill(item.color).frame(width: 7, height: 7)
      Text(item.label)
      Spacer()
      Text(value)
      Text(percent).foregroundStyle(Theme.muted).frame(width: 55, alignment: .trailing)
    }
    .font(Theme.body(12))
    .contentShape(Rectangle())
    .onHover { hovered = $0 ? item.id : nil }
    .help(hint)
  }
}
struct VideoScatterChart: View {
  var videos: [TikTokVideo]
  @State private var hovered: TikTokVideo?
  var valid: [TikTokVideo] { videos.filter { $0.views > 0 } }
  var body: some View {
    ProgressiveContent(identity: "scatter") {
      LoadingShimmer(height: 260)
    } content: {
      chart
    }
  }
  private var chart: some View {
    Chart(valid) { v in
      PointMark(x: .value("Vues", v.views), y: .value("Engagement", v.engagement)).foregroundStyle(
        Theme.tiktok.opacity(0.8)
      ).symbolSize(50)
    }
    .chartXAxisLabel("Vues cumulées").chartYAxisLabel("Engagement (%)").frame(height: 260)
    .chartOverlay { proxy in
      GeometryReader { geo in
        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
          switch phase {
          case .active(let position):
            guard let frame = proxy.plotFrame else { return }
            let rect = geo[frame]
            hovered = valid.min { a, b in
              func distance(_ v: TikTokVideo) -> Double {
                guard let x = proxy.position(forX: v.views),
                  let y = proxy.position(forY: v.engagement)
                else { return .infinity }
                return pow(x + rect.minX - position.x, 2) + pow(y + rect.minY - position.y, 2)
              }
              return distance(a) < distance(b)
            }
          case .ended: hovered = nil
          }
        }
      }
    }
    .overlay(alignment: .topLeading) {
      if let hovered {
        VStack(alignment: .leading, spacing: 6) {
          Text(hovered.title).lineLimit(2)
          Text(
            "\(Analytics.number(hovered.views)) vues · \(Analytics.number(hovered.engagement,digits:1)) %"
          ).foregroundStyle(Theme.muted)
        }.font(Theme.body(12)).padding(12).frame(maxWidth: 260).background(
          Color(hex: 0x303135), in: RoundedRectangle(cornerRadius: 12)
        ).allowsHitTesting(false)
      }
    }
  }
}

/// Card previews use lightweight paths and preserve hover without chart selection gestures.
private struct Sparkline: View {
  let series: [PlotSeries]
  let timeline: ChartTimeline
  @State private var selected: String?
  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let values = series.flatMap(\.values)
        guard let first = timeline.dates.first, let last = timeline.dates.last,
          let minimum = values.map(\.value).min(), let maximum = values.map(\.value).max()
        else { return }
        let duration = max(1, last.timeIntervalSince(first))
        let span = max(1, maximum - minimum)
        for series in series {
          var path = Path()
          var segment: Int?
          for datum in series.values {
            let point = CGPoint(
              x: datum.day.timeIntervalSince(first) / duration * size.width,
              y: maximum == minimum
                ? size.height / 2
                : 3 + (1 - (datum.value - minimum) / span) * max(0, size.height - 6)
            )
            if segment != datum.segment { path.move(to: point) } else { path.addLine(to: point) }
            segment = datum.segment
          }
          context.stroke(
            path, with: .color(series.color),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
      }
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case .ended: selected = nil
        case .active(let position):
          guard let first = timeline.dates.first, let last = timeline.dates.last else { return }
          let fraction = min(1, max(0, position.x / max(1, geometry.size.width)))
          let day = first.addingTimeInterval(last.timeIntervalSince(first) * fraction)
          let nearest = timeline.nearest(to: day)
          if nearest != selected { selected = nearest }
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if let selected {
          ChartTooltip(series: series, selected: selected).offset(y: -geometry.size.height - 6)
        }
      }
    }
  }
}

private struct ChartTooltip: View {
  let series: [PlotSeries]
  let selected: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(Day.label(selected)).font(Theme.body(12))
      ForEach(series) { s in
        HStack {
          Circle().fill(s.color).frame(width: 6, height: 6)
          Text(s.name)
          Spacer()
          if s.loading {
            LoadingShimmer(height: 12).frame(width: 40)
          } else {
            Text(
              s.points.first { $0.date == selected }?.value.map {
                Analytics.number($0, digits: 2) + (s.unit.isEmpty ? "" : " " + s.unit)
              } ?? "Indisponible"
            ).monospacedDigit()
          }
        }
      }
    }.font(Theme.body(11)).padding(12).frame(width: 240).background(
      Color(hex: 0x303135), in: RoundedRectangle(cornerRadius: 13)
    ).allowsHitTesting(false)
  }
}
