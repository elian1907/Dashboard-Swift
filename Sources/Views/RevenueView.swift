import SwiftUI

struct RevenueView: View {
  @Environment(DashboardStore.self) private var store
  @State private var mode = 0
  var sales: [DataPoint] { store.series(store.revenue?.points() ?? []) }
  var net: [DataPoint] { store.series(store.proceeds?.points() ?? []) }
  var trialTotal: JSONValue { store.trials?.totals["Total"] ?? .null }
  var body: some View {
    LazyVStack(spacing: 18) {
      MetricRow(spacing: 16) {
        MetricTile(
          title: "Revenus de la période", value: Analytics.money(Analytics.total(sales)),
          icon: "eurosign.circle", color: Theme.revenue,
          loading: store.revenue == nil && store.busy("revenue"),
          change: store.delta(store.revenue?.points() ?? []), points: sales,
          chartLoading: store.revenue == nil && store.busy("revenue"))
        MetricTile(
          title: "MRR actuel", value: Analytics.money(store.overview?.value("mrr")),
          icon: "chart.line.uptrend.xyaxis", color: Theme.revenue,
          loading: store.overview == nil && store.busy("overview"),
          points: store.series(store.mrr?.points() ?? []),
          chartLoading: store.mrr == nil && store.busy("mrr"))
        MetricTile(
          title: "Abonnements actifs",
          value: Analytics.number(store.overview?.value("active_subscriptions")),
          icon: "creditcard", color: Theme.subscriptions,
          loading: store.overview == nil && store.busy("overview"),
          points: store.series(store.actives?.points() ?? []),
          chartLoading: store.actives == nil && store.busy("actives"))
      }
      HStack(alignment: .top, spacing: 18) {
        GlassPanel(fillsHeight: true) {
          HStack {
            DataCrossfade(value: mode == 2) {
              Text(mode == 2 ? "Évolution du MRR" : "Revenus quotidiens").font(Theme.heading(17))
            }
            Spacer()
            GlassSelector(
              title: "Revenus", selection: $mode,
              options: [(0, "Par jour"), (1, "Cumul"), (2, "MRR")])
          }
          NativeTimeChart(
            series: [
              PlotSeries(
                id: "revenue", name: mode == 2 ? "MRR" : "Revenus", color: Theme.revenue,
                points: mode == 2
                  ? store.series(store.mrr?.points() ?? [])
                  : mode == 1 ? Analytics.cumulative(sales) : sales,
                loading: mode == 2
                  ? store.mrr == nil && store.busy("mrr")
                  : store.revenue == nil && store.busy("revenue"), unit: "€")
            ], height: 270, bars: mode == 0)
          HStack {
            SmallStat(
              title: "Revenus nets estimés de la période",
              value: Analytics.money(Analytics.total(net)),
              loading: store.proceeds == nil && store.busy("proceeds"))
            SmallStat(
              title: "Revenus depuis le lancement",
              value: Analytics.money(store.revenue?.totals["Revenue"].number),
              loading: store.revenue == nil && store.busy("revenue"))
          }.padding(.top, 8)
        }.frame(maxWidth: .infinity)
        GlassPanel(title: "Répartition des essais", fillsHeight: true) {
          if store.trials == nil && store.busy("trials") {
            LoadingShimmer(height: 235)
          } else if ["Conversions", "Pending", "Expirations"].allSatisfy({
            (trialTotal[$0].number ?? -1) >= 0
          }) {
            NativeDonut(
              items: [
                DonutItem(
                  id: "converted", label: "Convertis", value: trialTotal["Conversions"].number ?? 0,
                  color: Theme.revenue),
                DonutItem(
                  id: "pending", label: "En cours", value: trialTotal["Pending"].number ?? 0,
                  color: Theme.users),
                DonutItem(
                  id: "expired", label: "Expirés", value: trialTotal["Expirations"].number ?? 0,
                  color: Theme.other),
              ], height: 180)
          } else {
            EmptyData(text: "Répartition indisponible", height: 235)
          }
          HStack {
            SmallStat(
              title: "Conversion des essais terminés",
              value: Offer.conversion(trialTotal).map {
                Analytics.number($0 * 100, digits: 1) + " %"
              } ?? "—", loading: store.trials == nil && store.busy("trials"))
            SmallStat(
              title: "Payants sous 7 jours",
              value: Analytics.number(store.paying?.totals["Paying Customers (7 days)"].number),
              loading: store.paying == nil && store.busy("paying"))
          }
        }.frame(width: 340)
      }.fixedSize(horizontal: false, vertical: true)
      GlassPanel(title: "Conversion par offre") {
        if store.trials == nil && store.busy("trials") {
          LoadingShimmer(height: 150)
        } else {
          VStack(spacing: 6) {
            MetricRow(spacing: 16) {
              heading("Offre", leading: true)
              heading("Tarif")
              heading("Essais")
              heading("Convertis")
              heading("En cours")
              heading("Conversion")
            }.padding(.horizontal, 12).padding(.bottom, 4)
            ForEach(Offer.all) { offer in
              let s = store.trials?.totals[offer.id] ?? .null
              let color = offerColor(offer.id)
              tableRow(color: color) {
                rowLabel(offer.name, color: color)
                tableValue(Analytics.money(offer.price, digits: 2))
                tableValue(Analytics.number(s["Trial Starts"].number))
                tableValue(Analytics.number(s["Conversions"].number))
                tableValue(Analytics.number(s["Pending"].number.map { max(0, $0) }))
                tableValue(
                  Offer.conversion(s).map { Analytics.number($0 * 100, digits: 1) + " %" } ?? "—")
              }
            }
          }.font(Theme.body(12)).monospacedDigit()
        }
      }
      GlassPanel(title: "Revenus par mois") {
        VStack(spacing: 6) {
          MetricRow(spacing: 16) {
            heading("Mois", leading: true)
            heading("Revenus")
            heading("Net estimé")
            heading("Évolution mensuelle")
          }.padding(.horizontal, 12).padding(.bottom, 4)
          ForEach(months, id: \.self) { month in
            let dates = store.range.labels.filter { $0.hasPrefix(month) }
            let color = monthColor(month)
            tableRow(color: color) {
              rowLabel(
                Day.parse(month + "-01").formatted(
                  .dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR"))), color: color)
              tableValue(
                Analytics.money(
                  Analytics.total(Analytics.align(store.revenue?.points() ?? [], dates: dates))),
                pending: store.revenue == nil && store.busy("revenue"))
              tableValue(
                Analytics.money(
                  Analytics.total(Analytics.align(store.proceeds?.points() ?? [], dates: dates))),
                pending: store.proceeds == nil && store.busy("proceeds"))
              tableValue(monthChange(month, dates: dates) ?? "—")
            }
          }
        }.font(Theme.body(12)).monospacedDigit().animateData(months)
      }
    }
  }
  var months: [String] { Array(Set(store.range.labels.map { String($0.prefix(7)) })).sorted(by: >) }
  func heading(_ s: String, leading: Bool = false) -> some View {
    Text(s).font(Theme.body(11)).foregroundStyle(Theme.muted).frame(
      maxWidth: .infinity, alignment: leading ? .leading : .trailing)
  }
  func tableValue(_ value: String, pending: Bool = false) -> some View {
    Group {
      if pending { LoadingShimmer(height: 15).frame(width: 65) } else { AnimatedValue(value) }
    }.frame(maxWidth: .infinity, alignment: .trailing)
  }
  private func rowLabel(_ text: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Capsule().fill(color.opacity(0.9)).frame(width: 3, height: 16)
      Text(text).lineLimit(1).minimumScaleFactor(0.85)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func tableRow<Content: View>(color: Color, @ViewBuilder content: () -> Content)
    -> some View
  {
    MetricRow(spacing: 16) { content() }
      .padding(.horizontal, 12).padding(.vertical, 9)
      .background {
        RoundedRectangle(cornerRadius: 10).fill(
          LinearGradient(
            colors: [color.opacity(0.16), color.opacity(0.07), color.opacity(0.025)],
            startPoint: .leading, endPoint: .trailing))
      }
  }
  private func offerColor(_ id: String) -> Color {
    switch id {
    case "loslo_special_offer": Theme.revenue
    case "loslo_premium_yearly": Theme.downloads
    default: Theme.users
    }
  }
  private func monthColor(_ month: String) -> Color {
    let colors = [Theme.revenue, Theme.downloads, Theme.subscriptions]
    let number = Int(month.suffix(2)) ?? 1
    return colors[max(0, number - 1) % colors.count]
  }
  func monthChange(_ month: String, dates: [String]) -> String? {
    let first = month + "-01"
    let next = Day.key(Day.calendar.date(byAdding: .month, value: 1, to: Day.parse(first))!)
    let end = Day.shift(next, -1)
    guard dates.first == first, dates.last == end else { return nil }
    let prevEnd = Day.shift(first, -1)
    let prevStart = String(prevEnd.prefix(7)) + "-01"
    return Analytics.change(
      Analytics.total(Analytics.align(store.revenue?.points() ?? [], dates: dates)),
      Analytics.total(
        Analytics.align(store.revenue?.points() ?? [], dates: Day.range(prevStart, prevEnd))))
  }
}
