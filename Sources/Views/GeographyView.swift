import SwiftUI

struct GeographyView: View {
  @Environment(DashboardStore.self) private var store
  @State private var search = ""
  var pending: Bool { store.busy("apple") && store.apple == nil }
  var body: some View {
    let report = store.geography
    let rows = report.rows.filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        || $0.code.localizedCaseInsensitiveContains(search)
    }
    let total = report.total
    let previous = report.previous
    return HStack(alignment: .top, spacing: 18) {
      GlassPanel {
        HStack {
          Text("Classement des pays").font(Theme.heading(18))
          Spacer()
          TextField("Rechercher un pays", text: $search).textFieldStyle(.roundedBorder).frame(
            width: 200)
        }
        if pending {
          LoadingShimmer(height: 580)
        } else {
          Grid(horizontalSpacing: 18, verticalSpacing: 16) {
            GridRow {
              Text("Pays").frame(maxWidth: .infinity, alignment: .leading)
              Text("Téléchargements")
              Text("Part")
              Text("Évolution")
            }.font(Theme.body(10)).foregroundStyle(Theme.muted)
            ForEach(rows) { c in
              GridRow {
                Text(c.flag + "  " + c.name).frame(maxWidth: .infinity, alignment: .leading)
                Text(Analytics.number(c.units))
                Text(
                  report.missing == 0 && total > 0
                    ? Analytics.number(c.units / total * 100, digits: 1) + " %" : "—")
                Text(report.missing == 0 ? Analytics.change(c.units, previous[c.code]) ?? "—" : "—")
              }
            }
          }.font(Theme.body(12)).monospacedDigit()
          if rows.isEmpty { EmptyData(text: "Aucun pays pour cette sélection", height: 400) }
        }
      }
      VStack(spacing: 18) {
        GlassPanel(title: "Répartition des téléchargements") {
          if pending {
            LoadingShimmer(height: 280)
          } else if report.missing == 0, report.rows.allSatisfy({ $0.units >= 0 }) {
            NativeDonut(items: distribution(report.rows), height: 170)
          } else {
            EmptyData(text: "Répartition indisponible", height: 280)
          }
        }
        GlassPanel {
          if pending {
            LoadingShimmer(height: 300)
          } else {
            NativeGlobe(countries: report.rows).frame(height: 330)
          }
        }
      }.frame(width: 390)
    }
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
struct NativeGlobe: View {
  var countries: [CountryRow]
  @State private var longitude = 0.0
  @State private var dragBase = 0.0
  @State private var hovered: CountryRow?
  private static let polygons: [[[Double]]] = {
    guard let url = Bundle.main.url(forResource: "world-polygons", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return [] }
    return (try? JSONDecoder().decode([[[Double]]].self, from: data)) ?? []
  }()
  func project(lon: Double, lat: Double, size: CGSize) -> (CGPoint, Double) {
    let r = min(size.width, size.height) * 0.45
    let l = (lon + longitude) * Double.pi / 180
    let p = lat * Double.pi / 180
    let tilt = 15 * Double.pi / 180
    let x = cos(p) * sin(l)
    let y = sin(p) * cos(tilt) - cos(p) * cos(l) * sin(tilt)
    let z = sin(p) * sin(tilt) + cos(p) * cos(l) * cos(tilt)
    return (CGPoint(x: size.width / 2 + r * x, y: size.height / 2 - r * y), z)
  }
  var body: some View {
    GeometryReader { geo in
      Canvas { context, size in
        let r = min(size.width, size.height) * 0.45
        let rect = CGRect(
          x: size.width / 2 - r, y: size.height / 2 - r, width: r * 2, height: r * 2)
        let sphere = Path(ellipseIn: rect)
        context.fill(
          sphere,
          with: .radialGradient(
            Gradient(colors: [Color(hex: 0x444950), Color(hex: 0x25272b)]),
            center: CGPoint(x: size.width * 0.4, y: size.height * 0.3), startRadius: 0,
            endRadius: r * 1.8))
        context.clip(to: sphere)
        for polygon in Self.polygons {
          var path = Path()
          var drawing = false
          for point in polygon {
            let (p, z) = project(lon: point[0], lat: point[1], size: size)
            if z > 0 {
              if drawing {
                path.addLine(to: p)
              } else {
                path.move(to: p)
                drawing = true
              }
            } else if drawing {
              path.closeSubpath()
              drawing = false
            }
          }
          if drawing { path.closeSubpath() }
          context.fill(path, with: .color(Color(hex: 0x828a97).opacity(0.55)))
        }
        let maxValue = max(1, countries.map(\.units).max() ?? 1)
        for country in countries {
          guard let c = Countries.centroid[country.code] else { continue }
          let (p, z) = project(lon: c.longitude, lat: c.latitude, size: size)
          guard z > 0 else { continue }
          let radius = 3 + sqrt(max(0, country.units) / maxValue) * 6
          context.fill(
            Path(
              ellipseIn: CGRect(
                x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Theme.downloads))
        }
      }.contentShape(Rectangle()).gesture(
        DragGesture().onChanged { longitude = dragBase + $0.translation.width * 0.5 }.onEnded { _ in
          dragBase = longitude
        }
      )
      .onContinuousHover { phase in
        switch phase {
        case .ended: hovered = nil
        case .active(let position):
          hovered = countries.first { country in
            guard let c = Countries.centroid[country.code] else { return false }
            let (p, z) = project(lon: c.longitude, lat: c.latitude, size: geo.size)
            return z > 0 && hypot(p.x - position.x, p.y - position.y) < 13
          }
        }
      }
      .overlay(alignment: .bottom) {
        if let hovered {
          Text(hovered.flag + " " + hovered.name + " · " + Analytics.number(hovered.units)).font(
            Theme.body(12)
          ).padding(10).background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
        }
      }
      .accessibilityLabel(
        "Globe des téléchargements. Les mêmes données sont disponibles dans le classement des pays."
      )
    }
  }
}
