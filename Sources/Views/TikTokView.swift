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
  var count: Int { max(1, Int(ceil(Double(rows.count) / 25))) }
  var pending: Bool { store.busy("tiktok") && store.tiktok == nil }
  var views: Double { all.reduce(0) { $0 + $1.views } }
  var rpm: Double? {
    guard views > 0, let revenue = store.revenue?.totals["Revenue"].number else { return nil }
    return (revenue + Offer.expected(store.allTrials?.totals ?? .null)) / views * 1000
  }
  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 14) {
        MetricTile(
          title: "Vues cumulées", value: Analytics.number(store.tiktok == nil ? nil : views),
          icon: "eye", color: Theme.tiktok, loading: pending)
        MetricTile(
          title: "J’aime",
          value: Analytics.number(store.tiktok == nil ? nil : all.reduce(0) { $0 + $1.likes }),
          icon: "heart", color: Theme.tiktok, loading: pending)
        MetricTile(
          title: "Publications",
          value: Analytics.number(store.tiktok.map { Double($0.videos.count) }),
          icon: "play.rectangle", color: Theme.tiktok, loading: pending)
        MetricTile(
          title: "Abonnés",
          value: Analytics.number(store.tiktok.map { $0.accounts.reduce(0) { $0 + $1.followers } }),
          icon: "person.2", color: Theme.tiktok, loading: pending)
        MetricTile(
          title: "RPM TikTok", value: Analytics.money(rpm, digits: 2), icon: "eurosign.circle",
          color: Theme.revenue,
          loading: pending || store.busy("revenue") && store.revenue == nil
            || store.busy("allTrials") && store.allTrials == nil)
      }
      HStack(alignment: .top, spacing: 18) {
        GlassPanel {
          HStack {
            Text("Vues des publications").font(Theme.heading(17))
            Spacer()
            Picker("Graphique", selection: $mode) {
              Text("Vues / jour").tag(0)
              Text("Engagement").tag(1)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
          }
          if pending {
            LoadingShimmer(height: 300)
          } else if mode == 1 {
            VideoScatterChart(videos: periodVideos)
          } else {
            NativeTimeChart(
              series: [
                PlotSeries(
                  id: "tiktok", name: "Vues des publications", color: Theme.tiktok, points: curve)
              ], height: 300, bars: true)
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
                  Text(account.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                  Text(Analytics.number(account.followers)).monospacedDigit()
                  Text(Analytics.number(account.views)).monospacedDigit()
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
                value: Analytics.number(Double(videos.count)) + " vidéos"
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
          Picker("Compte", selection: $account) {
            Text("Tous les comptes").tag("all")
            ForEach(store.tiktok?.accounts ?? []) { Text($0.name).tag($0.id) }
          }.frame(width: 190)
          Picker("Trier", selection: $sort) {
            Text("Vues").tag("views")
            Text("Date").tag("date")
            Text("Engagement").tag("engagement")
            Text("Partages").tag("shares")
          }.frame(width: 150)
        }
        if pending {
          LoadingShimmer(height: 220)
        } else {
          Grid(horizontalSpacing: 20, verticalSpacing: 14) {
            GridRow {
              Text("Publication").frame(maxWidth: .infinity, alignment: .leading)
              Text("Date")
              Text("Vues")
              Text("J’aime")
              Text("Commentaires")
              Text("Partages")
              Text("Engagement")
            }.font(Theme.body(10)).foregroundStyle(Theme.muted)
            ForEach(Array(rows.dropFirst(min(page, count - 1) * 25).prefix(25))) { v in
              GridRow {
                VStack(alignment: .leading, spacing: 5) {
                  Text(v.title).lineLimit(2)
                  Text(v.account).font(Theme.body(10)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(Day.label(v.date))
                Text(Analytics.number(v.views))
                Text(Analytics.number(v.likes))
                Text(Analytics.number(v.comments))
                Text(Analytics.number(v.shares))
                Text(Analytics.number(v.engagement, digits: 1) + " %")
              }
            }
          }.font(Theme.body(12)).monospacedDigit()
          if rows.isEmpty {
            EmptyData(text: "Aucune vidéo ne correspond à cette sélection", height: 100)
          }
          if count > 1 {
            HStack {
              Spacer()
              Button("Précédent") { page -= 1 }.disabled(page == 0)
              Text("\(min(page,count-1)+1) / \(count)")
              Button("Suivant") { page += 1 }.disabled(page >= count - 1)
            }.font(Theme.body(12))
          }
        }
      }
    }.onChange(of: account) { page = 0 }.onChange(of: search) { page = 0 }.onChange(
      of: store.period
    ) { page = 0 }
  }
  var months: [String] { Array(Set(periodVideos.map { String($0.date.prefix(7)) })).sorted(by: >) }
  var curve: [DataPoint] {
    let byDate = Dictionary(grouping: periodVideos, by: \.date)
    return store.range.labels.map {
      DataPoint(date: $0, value: byDate[$0]?.reduce(0) { $0 + $1.views } ?? 0)
    }
  }
}
