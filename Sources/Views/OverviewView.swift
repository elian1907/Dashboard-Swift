import SwiftUI

struct OverviewView: View {
  @Environment(DashboardStore.self) private var store
  @Binding var page: DashboardPage
  @State private var selected: Set<String> = ["downloads", "users", "revenue"]
  var downloads: [DataPoint] { store.series(store.downloads) }
  var revenue: [DataPoint] { store.series(store.revenue?.points() ?? []) }
  var body: some View {
    LazyVStack(spacing: 18) {
      MetricRow(spacing: 16) {
        Button {
          page = .revenue
        } label: {
          MetricTile(
            title: "MRR actuel", value: Analytics.money(store.overview?.value("mrr")),
            icon: "chart.line.uptrend.xyaxis", color: Theme.revenue,
            loading: store.overview == nil && store.busy("overview"),
            points: store.series(store.mrr?.points() ?? []),
            chartLoading: store.mrr == nil && store.busy("mrr"), interactive: true)
        }
        Button {
          page = .revenue
        } label: {
          MetricTile(
            title: "Revenus de la période", value: Analytics.money(Analytics.total(revenue)),
            icon: "eurosign.circle", color: Theme.revenue,
            loading: store.revenue == nil && store.busy("revenue"),
            change: store.delta(store.revenue?.points() ?? []), points: revenue,
            chartLoading: store.revenue == nil && store.busy("revenue"), interactive: true)
        }
        Button {
          page = .downloads
        } label: {
          MetricTile(
            title: "Téléchargements",
            value: Analytics.number(Analytics.total(downloads, complete: false)),
            icon: "arrow.down.circle", color: Theme.downloads,
            loading: store.apple == nil && store.busy("apple"),
            change: store.delta(store.downloads), points: downloads,
            chartLoading: store.apple == nil && store.busy("apple"), interactive: true)
        }
        Button {
          page = .users
        } label: {
          MetricTile(
            title: "Inscriptions", value: Analytics.number(Analytics.total(store.userPoints)),
            icon: "person.2", color: Theme.users,
            loading: store.users == nil && store.busy("users"), points: store.userPoints,
            chartLoading: store.users == nil && store.busy("users"), interactive: true)
        }
      }.buttonStyle(DashboardButtonStyle())
      GlassPanel(title: "Évolution de l’activité") {
        HStack(spacing: 10) {
          chip("downloads", "Téléchargements", Theme.downloads)
          chip("users", "Inscriptions", Theme.users)
          chip("revenue", "Revenus", Theme.revenue)
        }
        VStack(spacing: 18) {
          if selected.contains("downloads") || selected.contains("users") {
            HStack {
              Text("Activité quotidienne").font(Theme.heading(16))
              Spacer()
              Text("Nombre / jour").font(Theme.body(11)).foregroundStyle(Theme.muted)
            }
            NativeTimeChart(series: activity, height: selected.contains("revenue") ? 220 : 440)
          }
          if selected.contains("revenue") {
            HStack {
              Text("Revenus quotidiens").font(Theme.heading(16))
              Spacer()
              Text("€ / jour").font(Theme.body(11)).foregroundStyle(Theme.muted)
            }
            NativeTimeChart(
              series: [
                PlotSeries(
                  id: "revenue", name: "Revenus", color: Theme.revenue, points: revenue,
                  loading: store.revenue == nil && store.busy("revenue"), unit: "€")
              ], height: selected.count == 1 ? 440 : 200, bars: true)
          }
          if selected.isEmpty { EmptyData(text: "Sélectionne un indicateur", height: 420) }
        }.animateData(selected)
      }
    }
  }
  private var activity: [PlotSeries] {
    var result: [PlotSeries] = []
    if selected.contains("downloads") {
      result.append(
        PlotSeries(
          id: "downloads", name: "Téléchargements", color: Theme.downloads, points: downloads,
          loading: store.apple == nil && store.busy("apple")))
    }
    if selected.contains("users") {
      result.append(
        PlotSeries(
          id: "users", name: "Inscriptions", color: Theme.users, points: store.userPoints,
          loading: store.users == nil && store.busy("users")))
    }
    return result
  }
  private func chip(_ id: String, _ name: String, _ color: Color) -> some View {
    Button {
      if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    } label: {
      HStack(spacing: 6) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text(name)
        if selected.contains(id) {
          Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
        }
      }.font(Theme.body(12)).padding(.horizontal, 13).padding(.vertical, 9)
        .glassEffect(
          (selected.contains(id) ? Glass.clear.tint(color.opacity(0.2)) : .regular).interactive(),
          in: .capsule)
    }.buttonStyle(DashboardButtonStyle())
      .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
  }
}
struct AcquisitionView: View {
  var users = false
  @Environment(DashboardStore.self) private var store
  @State private var cumulative = false
  var points: [DataPoint] { users ? store.userPoints : store.series(store.downloads) }
  var color: Color { users ? Theme.users : Theme.downloads }
  var name: String { users ? "Inscriptions" : "Téléchargements" }
  var pending: Bool {
    users ? store.users == nil && store.busy("users") : store.apple == nil && store.busy("apple")
  }
  var body: some View {
    let total = Analytics.total(points, complete: users)
    let valid = points.filter { $0.value != nil }
    LazyVStack(spacing: 18) {
      MetricRow(spacing: 16) {
        MetricTile(
          title: name + " sur la période", value: Analytics.number(total),
          icon: users ? "person.2" : "arrow.down.circle", color: color, loading: pending)
        MetricTile(
          title: "Moyenne / jour",
          value: Analytics.number(total.map { $0 / Double(max(1, valid.count)) }, digits: 1),
          icon: "chart.bar", color: color, loading: pending)
        MetricTile(
          title: "Meilleur jour disponible",
          value: Analytics.number(valid.compactMap(\.value).max()), icon: "trophy", color: color,
          loading: pending)
        MetricTile(
          title: "Dernier jour disponible", value: Analytics.number(valid.last?.value),
          icon: "calendar", color: color, loading: pending)
      }
      GlassPanel {
        HStack {
          DataCrossfade(value: cumulative) {
            Text(name + (cumulative ? (users ? " cumulées" : " cumulés") : " par jour")).font(
              Theme.heading(18))
          }
          Spacer()
          GlassSelector(
            title: "Affichage", selection: $cumulative,
            options: [(false, "Par jour"), (true, "Cumul de la période")])
        }
        NativeTimeChart(
          series: [
            PlotSeries(
              id: name, name: name, color: color,
              points: cumulative ? Analytics.cumulative(points) : points, loading: pending)
          ], height: 480, bars: !users && !cumulative, dots: users && !cumulative)
      }
    }
  }
}
