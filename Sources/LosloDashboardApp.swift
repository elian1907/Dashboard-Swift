import AppKit
import SwiftUI

@main struct LosloDashboardApp: App {
  static var isTesting: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }
  @State private var store: DashboardStore
  init() {
    Theme.registerFonts()
    let args = ProcessInfo.processInfo.arguments
    let s = DashboardStore(
      loadConfiguration: !Self.isTesting && !args.contains("--import-dashboard"))
    if let index = args.firstIndex(of: "--import-dashboard"), args.count > index + 1 {
      do {
        let c = try DashboardImporter.run(
          folder: URL(fileURLWithPath: args[index + 1], isDirectory: true))
        try s.setConfiguration(c)
      } catch { s.errors["Migration"] = error.localizedDescription }
    }
    _store = State(initialValue: s)
  }
  var body: some Scene {
    Window("Loslo Dashboard", id: "dashboard") {
      RootView().environment(store).preferredColorScheme(.dark).tint(Theme.other).environment(
        \.locale, Locale(identifier: "fr_FR")
      ).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).frame(minWidth: 1100, minHeight: 760)
    }.defaultSize(width: 1440, height: 980)
      .commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .sidebar) {
          Button("Synchroniser les données") { Task { await store.refresh(force: true) } }
            .keyboardShortcut("r", modifiers: .command)
        }
      }
    Settings { SettingsView().environment(store) }
  }
}
enum DashboardPage: String, CaseIterable, Identifiable {
  case overview, revenue, downloads, users, geography, tiktok
  var id: String { rawValue }
  var title: String {
    switch self {
    case .overview: "Vue d’ensemble"
    case .revenue: "Revenus"
    case .downloads: "Téléchargements"
    case .users: "Utilisateurs"
    case .geography: "Géographie"
    case .tiktok: "TikTok"
    }
  }
  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .revenue: "creditcard"
    case .downloads: "arrow.down.circle"
    case .users: "person.2"
    case .geography: "globe.europe.africa"
    case .tiktok: "music.note"
    }
  }
}
struct RootView: View {
  @Environment(DashboardStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var page: DashboardPage = .overview
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    @Bindable var store = store
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 10) {
          if let url = Bundle.main.url(forResource: "loslo-logo", withExtension: "png"),
            let image = NSImage(contentsOf: url)
          {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 37, height: 37).clipShape(
              RoundedRectangle(cornerRadius: 10))
          }
          VStack(alignment: .leading, spacing: 3) {
            Text(store.config.name).font(Theme.heading(24))
            Text("Dashboard").font(Theme.body(11)).foregroundStyle(Theme.muted)
          }
        }.padding(.horizontal, 12).padding(.top, 14)
        VStack(alignment: .leading, spacing: 6) {
          Text("Analyse").font(Theme.body(10)).foregroundStyle(Theme.muted).padding(.horizontal, 14)
            .padding(.bottom, 6)
          ForEach(DashboardPage.allCases) { target in
            Button {
              withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                page = target
              }
            } label: {
              HStack(spacing: 11) {
                Image(systemName: target.symbol).font(.system(size: 15, weight: .semibold)).frame(
                  width: 19)
                Text(target.title).font(Theme.body(13))
                Spacer(minLength: 0)
              }.foregroundStyle(page == target ? Theme.text : Theme.muted).padding(.horizontal, 14)
                .frame(height: 43).background {
                  if page == target {
                    RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.04)).glassEffect(
                      .regular.interactive(), in: .rect(cornerRadius: 13))
                  }
                }
            }.buttonStyle(.plain).accessibilityAddTraits(page == target ? .isSelected : [])
          }
        }
        Spacer()
        SettingsLink {
          Label("Réglages", systemImage: "gearshape").font(Theme.body(12)).foregroundStyle(
            Theme.muted
          ).padding(12)
        }.buttonStyle(.plain)
      }.padding(12).frame(width: 205).background(Color(hex: 0x1c1d1f)).clipShape(
        RoundedRectangle(cornerRadius: 24)
      ).padding(.leading, 12).padding(.vertical, 12)
      VStack(spacing: 0) {
        HStack {
          Text(page.title).font(Theme.heading(29))
          Spacer()
          Picker("Période d’analyse", selection: $store.period) {
            ForEach(Period.allCases) { Text($0.label).tag($0) }
          }.pickerStyle(.segmented).labelsHidden().frame(width: 390)
        }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 24)
        ScrollView { content.padding(.horizontal, 26).padding(.bottom, 26).frame(maxWidth: 1700) }
          .scrollIndicators(.hidden).id(page)
      }
    }.background(Theme.background).foregroundStyle(Theme.text)
      .task {
        guard !LosloDashboardApp.isTesting else { return }
        await store.refresh()
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(300)) } catch { break }
          if scenePhase == .active { await store.refresh() }
        }
      }
      .onChange(of: store.period) { Task { await store.refreshPeriod() } }
  }
  @ViewBuilder var content: some View {
    switch page {
    case .overview: OverviewView(page: $page)
    case .revenue: RevenueView()
    case .downloads: AcquisitionView()
    case .users: AcquisitionView(users: true)
    case .geography: GeographyView()
    case .tiktok: TikTokView()
    }
  }
}
