import SwiftUI

struct GeographyView: View {
  @Environment(DashboardStore.self) private var store
  @State private var search = ""
  @State private var page = 0
  private let pageSize = 15
  var pending: Bool { store.apple == nil && store.busy("apple") }
  var body: some View {
    let report = store.geography
    let rows = report.rows.filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        || $0.code.localizedCaseInsensitiveContains(search)
    }
    let pageCount = max(1, (rows.count + pageSize - 1) / pageSize)
    let currentPage = min(page, pageCount - 1)
    let displayedRows = Array(rows.dropFirst(currentPage * pageSize).prefix(pageSize))
    let total = report.total
    let previous = report.previous
    let hasDistribution = report.canShowDistribution
    return HStack(alignment: .top, spacing: 18) {
      GlassPanel {
        HStack {
          Text("Classement des pays").font(Theme.heading(18))
          Spacer()
          TextField("Rechercher un pays", text: $search).textFieldStyle(.roundedBorder).frame(
            width: 200)
        }
        if pending {
          LoadingShimmer(height: 465)
        } else {
          LazyVStack(spacing: 16) {
            HStack(spacing: 18) {
              Text("Pays").frame(maxWidth: .infinity, alignment: .leading)
              Text("Téléchargements").frame(width: 105, alignment: .trailing)
              Text("Part").frame(width: 62, alignment: .trailing)
                .help("Part des téléchargements recensés dans les rapports disponibles.")
              Text("Évolution").frame(width: 74, alignment: .trailing)
            }.font(Theme.body(10)).foregroundStyle(Theme.muted)
            ForEach(displayedRows) { c in
              HStack(spacing: 18) {
                Text(c.flag + "  " + c.name).lineLimit(1).minimumScaleFactor(0.85).frame(
                  maxWidth: .infinity, alignment: .leading)
                AnimatedValue(Analytics.number(c.units)).frame(width: 105, alignment: .trailing)
                AnimatedValue(
                  hasDistribution
                    ? Analytics.number(c.units / total * 100, digits: 1) + " %" : "—"
                )
                .frame(width: 62, alignment: .trailing)
                AnimatedValue(
                  report.missing == 0 ? Analytics.change(c.units, previous[c.code]) ?? "—" : "—"
                )
                .frame(width: 74, alignment: .trailing)
              }
            }
          }.font(Theme.body(12)).monospacedDigit().animateData(displayedRows.map(\.id))
          if rows.isEmpty { EmptyData(text: "Aucun pays pour cette sélection", height: 400) }
          if pageCount > 1 {
            HStack {
              Spacer()
              Button("Précédent") { page = currentPage - 1 }.disabled(currentPage == 0)
              AnimatedValue("\(currentPage + 1) / \(pageCount)").monospacedDigit()
              Button("Suivant") { page = currentPage + 1 }.disabled(currentPage == pageCount - 1)
            }.font(Theme.body(12)).buttonStyle(.glass).buttonBorderShape(.capsule)
              .accessibilityElement(children: .contain).accessibilityLabel(
                "Pages du classement des pays")
          }
        }
      }
      VStack(spacing: 18) {
        GlassPanel(title: "Répartition des téléchargements") {
          if pending {
            LoadingShimmer(height: 280)
          } else if hasDistribution {
            NativeDonut(
              items: distribution(report.rows), height: 170,
              totalLabel: report.missing == 0 ? "Total" : "Recensés",
              totalHelp:
                "Répartition des téléchargements recensés : \(store.range.labels.count - report.missing) jours de rapports Apple disponibles sur \(store.range.labels.count)."
            )
          } else {
            EmptyData(text: "Répartition indisponible", height: 280)
          }
        }
        NativeGlobe(countries: report.rows)
      }.frame(width: 390)
    }.onChange(of: search) { page = 0 }
      .onChange(of: store.period) { page = 0 }
  }
  func distribution(_ rows: [CountryRow]) -> [DonutItem] {
    var list = Array(rows.prefix(5).enumerated()).map { i, c in
      DonutItem(id: c.code, label: c.name, value: c.units, color: Theme.palette[i])
    }
    let rest = rows.dropFirst(5).reduce(0) { $0 + $1.units }
    if rest > 0 {
      list.append(DonutItem(id: "other", label: "Autres pays", value: rest, color: Theme.other))
    }
    return list
  }
}
