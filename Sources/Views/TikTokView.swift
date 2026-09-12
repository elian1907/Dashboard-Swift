import SwiftUI

struct TikTokView: View {
  @Environment(DashboardStore.self) private var store
  @State private var account = "all"
  @State private var search = ""
  @State private var sort = "views"
  @State private var mode = 0
  @State private var page = 0
  var all: [TikTokVideo] { store.tiktok?.videos ?? [] }
  var periodVideos: [TikTokVideo] {
    let range = store.range
    return all.filter {
      $0.date >= range.start && $0.date <= range.end
        && (account == "all" || $0.accountId == account)
    }
  }
  var rows: [TikTokVideo] {
    periodVideos.filter {
      search.isEmpty || ($0.title + " " + $0.account).localizedCaseInsensitiveContains(search)
    }.sorted { a, b in
      switch sort {
      case "date": return a.date > b.date
      case "engagement": return a.engagement > b.engagement
      case "shares": return a.shares > b.shares
      default: return a.views > b.views
      }
    }
  }
  var pending: Bool { store.tiktok == nil && store.busy("tiktok") }
  var views: Double { all.reduce(0) { $0 + $1.views } }
  var rpm: Double? {
    guard views > 0, let revenue = store.revenue?.totals["Revenue"].number else { return nil }
    return (revenue + Offer.expected(store.allTrials?.totals ?? .null)) / views * 1000
  }
  var body: some View {
    let videoRows = rows
    let accountColors = Theme.categoryColors(for: (store.tiktok?.accounts ?? []).map(\.id))
    let pageCount = max(1, (videoRows.count + 24) / 25)
    let displayedRows = Array(videoRows.dropFirst(min(page, pageCount - 1) * 25).prefix(25))
    return LazyVStack(spacing: 18) {
      MetricRow(spacing: 14) {
        MetricTile(
          title: "Vues cumulées", value: Analytics.number(store.tiktok == nil ? nil : views),
          icon: "eye", color: Theme.tiktok, loading: pending)
        MetricTile(
          title: "J’aime",
          value: Analytics.number(store.tiktok == nil ? nil : all.reduce(0) { $0 + $1.likes }),
          icon: "heart", color: Theme.coral, loading: pending)
        MetricTile(
          title: "Publications",
          value: Analytics.number(store.tiktok.map { Double($0.videos.count) }),
          icon: "play.rectangle", color: Theme.indigo, loading: pending)
        MetricTile(
          title: "Abonnés",
          value: Analytics.number(store.tiktok.map { $0.accounts.reduce(0) { $0 + $1.followers } }),
          icon: "person.2", color: Theme.subscriptions, loading: pending)
        MetricTile(
          title: "RPM TikTok", value: Analytics.money(rpm, digits: 2), icon: "eurosign.circle",
          color: Theme.revenue,
          loading: pending || store.revenue == nil && store.busy("revenue")
            || store.allTrials == nil && store.busy("allTrials"))
      }
      HStack(alignment: .top, spacing: 18) {
        GlassPanel {
          HStack {
            Text("Vues des publications").font(Theme.heading(17))
            Spacer()
            GlassSelector(
              title: "Graphique", selection: $mode,
              options: [(0, "Vues / jour"), (1, "Engagement")])
          }
          DataCrossfade(value: pending ? -1 : mode) {
            if pending {
              LoadingShimmer(height: 300)
            } else if mode == 1 {
              VideoScatterChart(
                videos: periodVideos, accounts: store.tiktok?.accounts ?? [],
                accountColors: accountColors)
            } else {
              NativeTimeChart(
                series: [
                  PlotSeries(
                    id: "tiktok", name: "Vues des publications", color: Theme.tiktok, points: curve)
                ], height: 300, bars: true)
            }
          }
        }
        GlassPanel(title: "Comptes") {
          if pending {
            LoadingShimmer(height: 310)
          } else {
            Grid(horizontalSpacing: 12, verticalSpacing: 21) {
              GridRow {
                Text("Compte").frame(maxWidth: .infinity, alignment: .leading)
                Text("Abonnés")
                Text("Vues")
              }.foregroundStyle(Theme.muted).font(Theme.body(10))
              ForEach(store.tiktok?.accounts ?? []) { account in
                GridRow {
                  HStack(spacing: 7) {
                    Circle().fill(accountColors[account.id] ?? Theme.tiktok).frame(
                      width: 6, height: 6)
                    Text(account.name).lineLimit(1)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  AnimatedValue(Analytics.number(account.followers)).monospacedDigit()
                  AnimatedValue(Analytics.number(account.views)).monospacedDigit()
                }.font(Theme.body(12))
              }
            }.frame(minHeight: 300, alignment: .top)
            if store.tiktok?.accounts.isEmpty != false {
              EmptyData(text: "Aucun compte connecté", height: 270)
            }
          }
        }.frame(width: 310)
      }
      GlassPanel(title: "Publications par mois") {
        if pending {
          LoadingShimmer(height: 100)
        } else {
          HStack(spacing: 25) {
            ForEach(months, id: \.self) { month in
              let videos = periodVideos.filter { $0.date.hasPrefix(month) }
              SmallStat(
                title: Day.parse(month + "-01").formatted(
                  .dateTime.month(.wide).locale(Locale(identifier: "fr_FR"))),
                value: Analytics.number(Double(videos.count)) + " vidéos",
                color: Theme.monthColor(month)
              ).help(Analytics.number(videos.reduce(0) { $0 + $1.views }) + " vues cumulées")
            }
          }
          if months.isEmpty { EmptyData(height: 60) }
        }
      }
      GlassPanel {
        HStack {
          Text("Vidéos").font(Theme.heading(18))
          Spacer()
          TextField("Rechercher une vidéo", text: $search).textFieldStyle(.roundedBorder).frame(
            width: 220)
          Menu {
            Picker("Compte", selection: $account) {
              Text("Tous les comptes").tag("all")
              ForEach(store.tiktok?.accounts ?? []) { Text($0.name).tag($0.id) }
            }
          } label: {
            Text(
              store.tiktok?.accounts.first(where: { $0.id == account })?.name ?? "Tous les comptes"
            )
            .lineLimit(1)
          }.menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.capsule).frame(width: 170)
            .accessibilityLabel("Compte")
          Menu {
            Picker("Trier", selection: $sort) {
              Text("Vues").tag("views")
              Text("Date").tag("date")
              Text("Engagement").tag("engagement")
              Text("Partages").tag("shares")
            }
          } label: {
            Label(
              ["views": "Vues", "date": "Date", "engagement": "Engagement", "shares": "Partages"][
                sort] ?? "Vues",
              systemImage: "arrow.up.arrow.down"
            ).lineLimit(1)
          }.menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.capsule).frame(width: 140)
            .accessibilityLabel("Trier")
        }
        if pending {
          LoadingShimmer(height: 220)
        } else {
          LazyVStack(spacing: 14) {
            HStack(spacing: 12) {
              Text("Publication").frame(maxWidth: .infinity, alignment: .leading)
              videoCell("Date", width: 64)
              videoCell("Vues", width: 72)
              videoCell("J’aime", width: 64)
              videoCell("Commentaires", width: 88)
              videoCell("Partages", width: 60)
              videoCell("Engagement", width: 82)
            }.font(Theme.body(10)).foregroundStyle(Theme.muted)
            ForEach(displayedRows) { video in
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(video.title).lineLimit(2)
                  Text(video.account).font(Theme.body(10)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                videoCell(Day.label(video.date), width: 64)
                videoCell(Analytics.number(video.views), width: 72)
                videoCell(Analytics.number(video.likes), width: 64)
                videoCell(Analytics.number(video.comments), width: 88)
                videoCell(Analytics.number(video.shares), width: 60)
                videoCell(Analytics.number(video.engagement, digits: 1) + " %", width: 82)
              }.frame(height: 50)
            }
          }.font(Theme.body(12)).monospacedDigit().animateData(displayedRows.map(\.id))
          if videoRows.isEmpty {
            EmptyData(text: "Aucune vidéo ne correspond à cette sélection", height: 100)
          }
          if pageCount > 1 {
            HStack {
              Spacer()
              Button("Précédent") { page -= 1 }.disabled(page == 0)
              AnimatedValue("\(min(page,pageCount-1)+1) / \(pageCount)")
              Button("Suivant") { page += 1 }.disabled(page >= pageCount - 1)
            }.font(Theme.body(12)).buttonStyle(.glass).buttonBorderShape(.capsule)
          }
        }
      }
    }.onChange(of: account) { page = 0 }.onChange(of: search) { page = 0 }.onChange(
      of: store.period
    ) { page = 0 }
  }
  private func videoCell(_ text: String, width: CGFloat) -> some View {
    AnimatedValue(text).lineLimit(1).minimumScaleFactor(0.85).frame(
      width: width, alignment: .trailing)
  }
  var months: [String] { Array(Set(periodVideos.map { String($0.date.prefix(7)) })).sorted(by: >) }
  var curve: [DataPoint] {
    let byDate = Dictionary(grouping: periodVideos, by: \.date)
    return store.range.labels.map {
      DataPoint(date: $0, value: byDate[$0]?.reduce(0) { $0 + $1.views } ?? 0)
    }
  }
}
