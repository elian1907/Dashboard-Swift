import AppKit
import SwiftUI

/// Give each destination its own view graph. Sidebar/header transactions no longer
/// need to negotiate the layout of all the charts. Revisited pages retain their
/// charts, filters and native controls instead of constructing them again.
struct DashboardPageHost: NSViewRepresentable {
  @Binding var page: DashboardPage
  let store: DashboardStore

  func makeNSView(context: Context) -> PageContainer { PageContainer() }
  func updateNSView(_ view: PageContainer, context: Context) {
    view.show(page: page, selection: $page, store: store)
  }

  final class PageContainer: NSView {
    private var pages: [DashboardPage: NSHostingView<HostedDashboardPage>] = [:]
    private(set) var selection: DashboardPage?
    override var isFlipped: Bool { true }

    func show(page: DashboardPage, selection binding: Binding<DashboardPage>, store: DashboardStore)
    {
      guard selection != page else { return }
      selection = page
      subviews.forEach { $0.removeFromSuperview() }
      let host: NSHostingView<HostedDashboardPage>
      if let cached = pages[page] {
        host = cached
      } else {
        host = NSHostingView(
          rootView: HostedDashboardPage(page: page, selection: binding, store: store))
        // The dashboard viewport supplies a concrete size. Intrinsic-size probes
        // would recursively measure every chart just to size this container.
        host.sizingOptions = []
        pages[page] = host
      }
      host.frame = bounds
      host.autoresizingMask = [.width, .height]
      addSubview(host)
    }
  }
}

private struct HostedDashboardPage: View {
  let page: DashboardPage
  @Binding var selection: DashboardPage
  let store: DashboardStore

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressiveContent(identity: page) {
          PageLoadingView(page: $selection)
        } content: {
          content
        }.padding(.horizontal, 26).padding(.bottom, 26).frame(maxWidth: 1700)
      }
    }.scrollIndicators(.hidden)
      .transaction { $0.animation = nil }

      .environment(store)
      .environment(\.locale, Locale(identifier: "fr_FR"))
      .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
      .preferredColorScheme(.dark)
      .foregroundStyle(Theme.text)
      .allowsWindowActivationEvents()
  }

  @ViewBuilder private var content: some View {
    switch page {
    case .overview: OverviewView(page: $selection)
    case .revenue: RevenueView()
    case .downloads: AcquisitionView()
    case .users: AcquisitionView(users: true)
    case .geography: GeographyView()
    case .tiktok: TikTokView()
    }
  }
}
