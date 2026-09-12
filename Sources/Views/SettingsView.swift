import AppKit
import CryptoKit
import SwiftUI

struct SettingsView: View {
  @Environment(DashboardStore.self) private var store
  @State private var draft = AppConfiguration()
  @State private var message: String?
  @State private var failure = false
  var body: some View {
    Form {
      if store.errors["Trousseau"] != nil {
        Section("Trousseau") {
          Button("Autoriser l’accès au Trousseau…") {
            Task {
              do {
                let config = try await Task.detached {
                  try Keychain.read(AppConfiguration.self, key: "configuration", allowPrompt: true)
                }.value
                if let config {
                  try store.setConfiguration(config)
                  draft = config
                  await store.refresh()
                }
              } catch {
                message = error.localizedDescription
                failure = true
              }
            }
          }
        }
      }
      Section("Application") {
        TextField("Nom", text: $draft.name)
        TextField("Date de lancement (AAAA-MM-JJ)", text: $draft.launchDate)
      }
      Section("RevenueCat") {
        TextField("Project ID", text: $draft.rcProject)
        SecureField("Clé secrète v2", text: $draft.rcKey)
      }
      Section("App Store Connect") {
        TextField("Issuer ID", text: $draft.issuer)
        TextField("Key ID", text: $draft.keyID)
        TextField("Vendor Number", text: $draft.vendor)
        TextField("Apple App ID", text: $draft.appID)
        HStack {
          Label(
            draft.privateKey.isEmpty ? "Clé .p8 manquante" : "Clé .p8 enregistrée",
            systemImage: draft.privateKey.isEmpty ? "key" : "checkmark.shield")
          Spacer()
          Button("Importer la clé .p8") { importKey() }
        }
      }
      Section("Supabase") {
        TextField("URL du projet", text: $draft.supabaseURL)
        SecureField("Clé du projet", text: $draft.supabaseKey)
      }
      Section("TikTok") {
        TextField("Client Key", text: $draft.tiktokClient)
        SecureField("Client Secret", text: $draft.tiktokSecret)
        Text(
          "L’historique web peut être importé. Utilise une autorisation distincte pour la synchronisation native : partager un refresh token pourrait interrompre la connexion du site."
        ).font(Theme.body(12)).foregroundStyle(Theme.muted)
        Button("Importer une connexion TikTok indépendante…") { importTikTok() }
      }
      Section("Migration") {
        Button("Importer les connexions et l’historique du dashboard web…") { importWeb() }
        Text(
          "Les fichiers d’origine sont uniquement lus. Les secrets sont conservés dans le Trousseau de ce Mac ; l’historique reste dans Application Support."
        ).font(Theme.body(12)).foregroundStyle(Theme.muted)
      }
      if !store.errors.isEmpty {
        Section("État des connexions") {
          ForEach(store.errors.keys.sorted(), id: \.self) { key in
            VStack(alignment: .leading, spacing: 5) {
              Text(sourceName(key)).bold()
              Text(store.errors[key] ?? "").font(Theme.body(12)).foregroundStyle(Theme.muted)
            }
          }
        }
      }
      if let message {
        Text(message).foregroundStyle(failure ? .red : Theme.muted).font(Theme.body(12))
      }
      HStack {
        Spacer()
        Button("Enregistrer") { save() }.buttonStyle(.glassProminent)
      }
    }.buttonStyle(.glass).buttonBorderShape(.capsule).formStyle(.grouped).frame(
      width: 660, height: 740
    ).onAppear { draft = store.config }
      .preferredColorScheme(.dark)
  }
  func sourceName(_ key: String) -> String {
    switch key {
    case "apple": "App Store Connect"
    case "users": "Supabase"
    case "tiktok": "TikTok"
    case "Trousseau": "Trousseau"
    default: "RevenueCat · " + key
    }
  }
  func result(_ work: () throws -> Void) {
    do {
      try work()
      failure = false
    } catch {
      message = error.localizedDescription
      failure = true
    }
  }
  func save() {
    result {
      guard !draft.name.isEmpty, Day.key(Day.parse(draft.launchDate)) == draft.launchDate,
        draft.launchDate <= Day.key(Date())
      else { throw DashboardError(message: "Nom ou date de lancement invalide.") }
      if !draft.supabaseURL.isEmpty { _ = try HTTP.url(draft.supabaseURL) }
      try store.setConfiguration(draft)
      message = "Connexions enregistrées dans le Trousseau."
      Task { await store.refresh(force: true) }
    }
  }
  func importKey() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    result {
      let pem = try String(contentsOf: url, encoding: .utf8)
      _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
      draft.privateKey = pem
      message = "Clé chargée. Enregistre pour l’appliquer."
    }
  }
  func importWeb() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    result {
      let c = try DashboardImporter.run(folder: folder)
      try store.setConfiguration(c)
      draft = c
      message = "Copie importée. Le dashboard web reste intact."
      Task { await store.refresh() }
    }
  }
  func importTikTok() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.message =
      "Choisis le fichier JSON d’une autorisation TikTok réservée à cette app (accounts avec open_id et refresh_token). N’utilise pas le fichier du site actif."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    result {
      struct Import: Decodable { var accounts: [NativeTikTokCredential] }
      let accounts = try JSONDecoder().decode(Import.self, from: Data(contentsOf: url)).accounts
      guard !accounts.isEmpty,
        accounts.allSatisfy({ !$0.open_id.isEmpty && !$0.refresh_token.isEmpty })
      else { throw DashboardError(message: "Connexion TikTok invalide.") }
      try Keychain.save(accounts, key: "tiktok-accounts")
      message = "Connexion native enregistrée."
      Task { await store.refresh(force: true) }
    }
  }
}
