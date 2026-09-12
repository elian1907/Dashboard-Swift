import AppKit
import SwiftUI

/// Paint the lightweight destination before constructing its charts and tables.
/// There is no timer or dependency on a network request in this presentation boundary.
struct ProgressiveContent<Identity: Hashable, Placeholder: View, Content: View>: View {
  let identity: Identity
  @ViewBuilder let placeholder: () -> Placeholder
  @ViewBuilder let content: () -> Content
  @State private var presented: Identity?

  var body: some View {
    if presented == identity {
      content()
    } else {
      placeholder().background(alignment: .topLeading) {
        FirstPaint { presented = identity }
          .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
          .accessibilityHidden(true)
          .id(identity)
      }
    }
  }
}

private struct FirstPaint: NSViewRepresentable {
  let completion: () -> Void
  func makeNSView(context: Context) -> Observer {
    let view = Observer()
    view.completion = completion
    return view
  }
  func updateNSView(_ view: Observer, context: Context) { view.completion = completion }
  static func dismantleNSView(_ view: Observer, coordinator: ()) { view.completion = nil }

  final class Observer: NSView {
    var completion: (() -> Void)?
    private var scheduled = false
    private var attachment = 0
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // Cached pages can detach between draw and its deferred callback.
      // A new attachment must get another opportunity to finish its first paint.
      attachment += 1
      scheduled = false
      if window != nil { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      guard !scheduled else { return }
      scheduled = true
      let drawnAttachment = attachment
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window != nil, self.attachment == drawnAttachment else { return }
        self.completion?()
      }
    }
  }
}

struct PageLoadingView: View {
  @Binding var page: DashboardPage
  private var metrics: [(String, String, Color)] {
    switch page {
    case .overview:
      [
        ("MRR actuel", "chart.line.uptrend.xyaxis", Theme.revenue),
        ("Revenus de la période", "eurosign.circle", Theme.revenue),
        ("Téléchargements", "arrow.down.circle", Theme.downloads),
        ("Inscriptions", "person.2", Theme.users),
      ]
    case .revenue:
      [
        ("Revenus de la période", "eurosign.circle", Theme.revenue),
        ("MRR actuel", "chart.line.uptrend.xyaxis", Theme.revenue),
        ("Abonnements actifs", "creditcard", Theme.subscriptions),
      ]
    case .downloads, .users:
      [
        (
          page == .users ? "Inscriptions sur la période" : "Téléchargements sur la période",
          page.symbol, page == .users ? Theme.users : Theme.downloads
        ),
        ("Moyenne / jour", "chart.bar", Theme.other),
        ("Meilleur jour disponible", "trophy", Theme.other),
        ("Dernier jour disponible", "calendar", Theme.other),
      ]
    case .tiktok:
      [
        ("Vues cumulées", "eye", Theme.tiktok), ("J’aime", "heart", Theme.tiktok),
        ("Publications", "play.rectangle", Theme.tiktok), ("Abonnés", "person.2", Theme.tiktok),
        ("RPM TikTok", "eurosign.circle", Theme.revenue),
      ]
    case .geography: []
    }
  }
  private var chartTitle: String {
    switch page {
    case .overview: "Évolution de l’activité"
    case .revenue: "Revenus quotidiens"
    case .downloads: "Téléchargements par jour"
    case .users: "Inscriptions par jour"
    case .geography: "Classement des pays"
    case .tiktok: "Vues des publications"
    }
  }
  var body: some View {
    VStack(spacing: 18) {
      if !metrics.isEmpty {
        MetricRow(spacing: 16) {
          ForEach(metrics.indices, id: \.self) { index in
            let metric = metrics[index]
            if page == .overview {
              Button {
                page = index < 2 ? .revenue : index == 2 ? .downloads : .users
              } label: {
                MetricTile(
                  title: metric.0, value: "", icon: metric.1, color: metric.2,
                  loading: true, chartLoading: true, interactive: true)
              }.buttonStyle(DashboardButtonStyle())
            } else {
              MetricTile(
                title: metric.0, value: "", icon: metric.1, color: metric.2,
                loading: true, chartLoading: page == .revenue)
            }
          }
        }
      }
      GlassPanel(title: chartTitle) { LoadingShimmer(height: page == .overview ? 440 : 360) }
    }.accessibilityLabel("Chargement de la page " + page.title)
  }
}
