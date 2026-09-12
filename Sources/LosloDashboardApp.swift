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
      RootView().environment(store).allowsWindowActivationEvents().preferredColorScheme(.dark)
        .environment(
          \.locale, Locale(identifier: "fr_FR")
        ).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).frame(
          minWidth: 1100, minHeight: 760)
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
  @State private var periodTask: Task<Void, Never>?
  var body: some View {
    @Bindable var store = store
    HStack(spacing: 0) {
      DashboardSidebar(name: store.config.name, page: $page)
      VStack(spacing: 0) {
        HStack {
          Text(page.title).font(Theme.heading(29))
          Spacer()
          GlassSelector(
            title: "Période d’analyse", selection: $store.period,
            options: Period.allCases.map { (value: $0, label: $0.label) })
        }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 24)
        ScrollViewReader { proxy in
          ScrollView {
            GlassEffectContainer(spacing: 0) {
              VStack(spacing: 0) {
                Color.clear.frame(height: 0).id("page-top")
                ProgressiveContent(identity: page) {
                  PageLoadingView(page: $page)
                } content: {
                  content
                }.padding(.horizontal, 26).padding(.bottom, 26).frame(maxWidth: 1700)
              }
            }
          }.scrollIndicators(.hidden)
            .transaction { $0.animation = nil }
            .onChange(of: page) { proxy.scrollTo("page-top", anchor: .top) }
        }
      }
    }.background { DashboardBackdrop() }.foregroundStyle(Theme.text)
      .task {
        guard !LosloDashboardApp.isTesting else { return }
        await store.refresh()
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(300)) } catch { break }
          if scenePhase == .active { await store.refresh() }
        }
      }
      .onChange(of: store.period) {
        periodTask?.cancel()
        periodTask = Task { await store.refreshPeriod() }
      }
      .onDisappear { periodTask?.cancel() }
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

private struct DashboardSidebar: View {
  let name: String
  @Binding var page: DashboardPage
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private static let logo: NSImage? = {
    Bundle.main.url(forResource: "loslo-logo", withExtension: "png").flatMap {
      NSImage(contentsOf: $0)
    }
  }()
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 10) {
        if let image = Self.logo {
          Image(nsImage: image).resizable().scaledToFit().frame(width: 37, height: 37)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(name).font(Theme.heading(24))
          Text("Dashboard").font(Theme.body(11)).foregroundStyle(Theme.muted)
        }
      }.padding(.horizontal, 12).padding(.top, 14)
      GlassEffectContainer(spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Analyse").font(Theme.body(10)).foregroundStyle(Theme.muted).padding(.horizontal, 14)
            .padding(.bottom, 6)
          ForEach(DashboardPage.allCases) { target in
            Button {
              guard page != target else { return }
              page = target
            } label: {
              HStack(spacing: 11) {
                Image(systemName: target.symbol).font(.system(size: 15, weight: .semibold)).frame(
                  width: 19)
                Text(target.title).font(Theme.body(13))
                Spacer(minLength: 0)
              }.padding(.horizontal, 14).frame(
                maxWidth: .infinity, minHeight: 43, alignment: .leading
              )
              .glassEffect(
                Glass.clear.tint(page == target ? .white.opacity(0.16) : nil).interactive(),
                in: .rect(cornerRadius: 14)
              )
            }
            .buttonStyle(.plain)
            .foregroundStyle(page == target ? Theme.text : Theme.muted)
            .accessibilityAddTraits(page == target ? .isSelected : [])
          }
        }
      }
      Spacer()
      SettingsLink {
        Label("Réglages", systemImage: "gearshape").font(Theme.body(12)).foregroundStyle(
          Theme.muted
        ).padding(12)
      }.buttonStyle(.glass).buttonBorderShape(.capsule)
    }.padding(12).frame(width: 225)
      .background {
        RoundedRectangle(cornerRadius: 24).fill(.clear)
          .glassEffect(reduceTransparency ? .regular : .clear, in: .rect(cornerRadius: 24))
          .overlay { RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.18)) }
          .allowsHitTesting(false)
      }.padding(.leading, 12).padding(.vertical, 12)
  }
}
