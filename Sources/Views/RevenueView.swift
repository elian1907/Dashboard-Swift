import SwiftUI

struct RevenueView: View {
  @Environment(DashboardStore.self) private var store
  @State private var mode = 0
  var sales: [DataPoint] { store.series(store.revenue?.points() ?? []) }
  var net: [DataPoint] { store.series(store.proceeds?.points() ?? []) }
  var trialTotal: JSONValue { store.trials?.totals["Total"] ?? .null }
  var body: some View {
    LazyVStack(spacing: 18) {
      HStack(spacing: 16) {
        MetricTile(
          title: "Revenus de la période", value: Analytics.money(Analytics.total(sales)),
          icon: "eurosign.circle", color: Theme.revenue,
          loading: store.busy("revenue") && store.revenue == nil,
          change: store.delta(store.revenue?.points() ?? []), points: sales,
          chartLoading: store.busy("revenue") && store.revenue == nil)
        MetricTile(
          title: "MRR actuel", value: Analytics.money(store.overview?.value("mrr")),
          icon: "chart.line.uptrend.xyaxis", color: Theme.revenue,
          loading: store.busy("overview") && store.overview == nil,
          points: store.series(store.mrr?.points() ?? []),
          chartLoading: store.busy("mrr") && store.mrr == nil)
        MetricTile(
          title: "Abonnements actifs",
          value: Analytics.number(store.overview?.value("active_subscriptions")),
          icon: "creditcard", color: Theme.subscriptions,
          loading: store.busy("overview") && store.overview == nil,
          points: store.series(store.actives?.points() ?? []),
          chartLoading: store.busy("actives") && store.actives == nil)
      }
      HStack(alignment: .top, spacing: 18) {
        GlassPanel {
          HStack {
            Text(mode == 2 ? "Évolution du MRR" : "Revenus quotidiens").font(Theme.heading(17))
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
                  ? store.busy("mrr") && store.mrr == nil
                  : store.busy("revenue") && store.revenue == nil, unit: "€")
            ], height: 270, bars: mode == 0)
          HStack {
            SmallStat(
              title: "Revenus nets estimés de la période",
              value: Analytics.money(Analytics.total(net)),
              loading: store.busy("proceeds") && store.proceeds == nil)
            SmallStat(
              title: "Revenus depuis le lancement",
              value: Analytics.money(store.revenue?.totals["Revenue"].number),
              loading: store.busy("revenue") && store.revenue == nil)
          }.padding(.top, 8)
        }.frame(maxWidth: .infinity)
        GlassPanel(title: "Répartition des essais") {
          if store.busy("trials") && store.trials == nil {
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
              ], height: 148)
          } else {
            EmptyData(text: "Répartition indisponible", height: 235)
          }
          HStack {
            SmallStat(
              title: "Conversion des essais terminés",
              value: Offer.conversion(trialTotal).map {
                Analytics.number($0 * 100, digits: 1) + " %"
              } ?? "—", loading: store.busy("trials"))
            SmallStat(
              title: "Payants sous 7 jours",
              value: Analytics.number(store.paying?.totals["Paying Customers (7 days)"].number),
              loading: store.busy("paying"))
          }
        }.frame(width: 340)
      }
      GlassPanel(title: "Conversion par offre") {
        if store.busy("trials") {
          LoadingShimmer(height: 150)
        } else {
          Grid(horizontalSpacing: 25, verticalSpacing: 14) {
            GridRow {
              heading("Offre")
              heading("Tarif")
              heading("Essais")
              heading("Convertis")
              heading("En cours")
              heading("Conversion")
            }
            ForEach(Offer.all) { offer in
              let s = store.trials?.totals[offer.id] ?? .null
              GridRow {
                Text(offer.name).frame(maxWidth: .infinity, alignment: .leading)
                Text(Analytics.money(offer.price, digits: 2))
                Text(Analytics.number(s["Trial Starts"].number))
                Text(Analytics.number(s["Conversions"].number))
                Text(Analytics.number(s["Pending"].number.map { max(0, $0) }))
                Text(
                  Offer.conversion(s).map { Analytics.number($0 * 100, digits: 1) + " %" } ?? "—")
              }
            }
          }.font(Theme.body(12)).monospacedDigit()
        }
      }
      GlassPanel(title: "Revenus par mois") {
        Grid(horizontalSpacing: 35, verticalSpacing: 14) {
          GridRow {
            heading("Mois")
            heading("Revenus")
            heading("Net estimé")
            heading("Évolution mensuelle")
          }
          ForEach(months, id: \.self) { month in
            let dates = store.range.labels.filter { $0.hasPrefix(month) }
            GridRow {
              Text(
                Day.parse(month + "-01").formatted(
                  .dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR")))
              ).frame(maxWidth: .infinity, alignment: .leading)
              tableValue(
                Analytics.money(
                  Analytics.total(Analytics.align(store.revenue?.points() ?? [], dates: dates))),
                pending: store.busy("revenue") && store.revenue == nil)
              tableValue(
                Analytics.money(
                  Analytics.total(Analytics.align(store.proceeds?.points() ?? [], dates: dates))),
                pending: store.busy("proceeds") && store.proceeds == nil)
              Text(monthChange(month, dates: dates) ?? "—")
            }
          }
        }.font(Theme.body(12)).monospacedDigit()
      }
    }
  }
  var months: [String] { Array(Set(store.range.labels.map { String($0.prefix(7)) })).sorted(by: >) }
  func heading(_ s: String) -> some View {
    Text(s).font(Theme.body(11)).foregroundStyle(Theme.muted).frame(
      maxWidth: .infinity, alignment: .leading)
  }
  @ViewBuilder func tableValue(_ value: String, pending: Bool) -> some View {
    if pending { LoadingShimmer(height: 15).frame(width: 65) } else { Text(value) }
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
