import Foundation

struct TikTokRaw: Codable, Sendable {
  var profile: Profile
  var videos: [Video]
  struct Profile: Codable, Sendable {
    var display_name: String?
    var follower_count: Double?
    var likes_count: Double?
  }
  struct Video: Codable, Sendable {
    var id: String
    var title: String?
    var create_time: Double
    var view_count: Double?
    var like_count: Double?
    var comment_count: Double?
    var share_count: Double?
    func row(id accountID: String, name: String) -> TikTokVideo {
      TikTokVideo(
        id: id, accountId: accountID, account: name, title: title ?? "Sans titre",
        date: Day.key(Date(timeIntervalSince1970: create_time)), views: view_count ?? 0,
        likes: like_count ?? 0, comments: comment_count ?? 0, shares: share_count ?? 0)
    }
  }
}
actor TikTokService {
  let config: AppConfiguration
  init(_ c: AppConfiguration) { config = c }
  static func form(_ fields: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return Data(
      fields.sorted { $0.key < $1.key }.map {
        ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
          + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
      }.joined(separator: "&").utf8)
  }
  func fetch() async throws -> ServiceResult<TikTokData> {
    let saved = NativeCache.read(TikTokData.self, key: "tiktok-history")
    var credentials = try Keychain.read([NativeTikTokCredential].self, key: "tiktok-accounts") ?? []
    guard !credentials.isEmpty else {
      if var saved {
        saved.needsConnection = true
        return .init(
          value: saved,
          warning:
            "TikTok : historique importé. Une connexion indépendante est nécessaire pour synchroniser l’app."
        )
      }
      throw DashboardError(message: "Ajoute une connexion TikTok dans Réglages.")
    }
    var accounts: [TikTokAccount] = []
    var allVideos: [TikTokVideo] = []
    var failed = false
    for i in credentials.indices {
      do {
        struct Tokens: Decodable {
          var access_token: String
          var refresh_token: String
          var open_id: String
        }
        let tokenData = try await HTTP.data(
          HTTP.url("https://open.tiktokapis.com/v2/oauth/token/"),
          headers: ["Content-Type": "application/x-www-form-urlencoded"],
          body: Self.form([
            "client_key": config.tiktokClient, "client_secret": config.tiktokSecret,
            "grant_type": "refresh_token", "refresh_token": credentials[i].refresh_token,
          ]))
        let tokens = try JSONDecoder().decode(Tokens.self, from: tokenData)
        credentials[i].refresh_token = tokens.refresh_token
        credentials[i].open_id = tokens.open_id
        credentials[i].saved_at = ISO8601DateFormatter().string(from: Date())
        try Keychain.save(credentials, key: "tiktok-accounts")
        let headers = [
          "Authorization": "Bearer " + tokens.access_token, "Content-Type": "application/json",
        ]
        struct ProfileResponse: Decodable {
          var data: Body
          struct Body: Decodable { var user: TikTokRaw.Profile }
        }
        let p = try await HTTP.data(
          HTTP.url(
            "https://open.tiktokapis.com/v2/user/info/",
            [("fields", "display_name,follower_count,likes_count")]), headers: headers)
        let profile = try JSONDecoder().decode(ProfileResponse.self, from: p).data.user
        let name = profile.display_name ?? credentials[i].display_name ?? "Compte"
        var videos: [TikTokRaw.Video] = []
        var cursor: Double?
        var seen: Set<Double> = []
        while true {
          struct VideosResponse: Decodable {
            var data: Body
            struct Body: Decodable {
              var videos: [TikTokRaw.Video]?
              var has_more: Bool?
              var cursor: Double?
            }
          }
          var body: [String: Any] = ["max_count": 20]
          if let cursor { body["cursor"] = cursor }
          let data = try await HTTP.data(
            HTTP.url(
              "https://open.tiktokapis.com/v2/video/list/",
              [("fields", "id,title,create_time,view_count,like_count,comment_count,share_count")]),
            headers: headers, body: JSONSerialization.data(withJSONObject: body))
          let page = try JSONDecoder().decode(VideosResponse.self, from: data).data
          videos += page.videos ?? []
          guard page.has_more == true else { break }
          guard let next = page.cursor, seen.insert(next).inserted else {
            throw DashboardError(message: "Pagination TikTok invalide.")
          }
          cursor = next
        }
        let rows = videos.map { $0.row(id: tokens.open_id, name: name) }
        allVideos += rows
        accounts.append(
          TikTokAccount(
            id: tokens.open_id, name: name, followers: profile.follower_count ?? 0,
            likes: profile.likes_count ?? 0, views: rows.reduce(0) { $0 + $1.views },
            videos: rows.count))
      } catch {
        failed = true
        if let old = saved?.accounts.first(where: { $0.id == credentials[i].open_id }) {
          accounts.append(old)
          allVideos += saved?.videos.filter { $0.accountId == old.id } ?? []
        }
      }
    }
    guard !accounts.isEmpty else {
      throw DashboardError(message: "TikTok inaccessible. Vérifie la connexion dans Réglages.")
    }
    let result = TikTokData(accounts: accounts, videos: allVideos)
    try NativeCache.save(result, key: "tiktok-history")
    return .init(
      value: result,
      warning: failed
        ? "Un compte TikTok est hors ligne · sa dernière sauvegarde est affichée." : nil)
  }
}
