// Protocol reference: SpolzerMod/yamusic-rs and rnikitin/yamusic-rs (GPL-3.0).
// No upstream executables or updater are used. OAuth identifiers identify the public client,
// not a user's credentials. This is an unofficial API and may change without notice.
import Foundation
import CryptoKit

final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Authenticated requests never follow redirects; don't forward OAuth headers to a CDN.
        completionHandler(nil)
    }
}

actor YandexAPI {
    private let clientID = "23cabbbdc6cd418abb4b39c32c41195d"
    private let clientSecret = "53bc75238f0c4d08a118e51fe9203300"
    private let session: URLSession
    private var credentials: Credentials?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    func restore() throws -> Bool {
        credentials = try CredentialStore.load()
        return credentials != nil
    }

    func logout() throws { try CredentialStore.remove(); credentials = nil }

    private func form(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }

    private func oauth(_ path: String, values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth.yandex.ru" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(values)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode < 500 else { throw MusicError.message("Яндекс временно недоступен. Попробуйте ещё раз.") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicError.message("Не удалось прочитать ответ авторизации.") }
        return result
    }

    func beginLogin(deviceID: String) async throws -> DeviceLogin {
        let result = try await oauth("/device/code", values: ["client_id": clientID, "device_id": deviceID, "device_name": "Fast Music · Mac"])
        guard let code = result["device_code"] as? String, let userCode = result["user_code"] as? String else { throw MusicError.message("Яндекс не выдал код входа. Попробуйте ещё раз.") }
        return DeviceLogin(deviceCode: code, userCode: userCode, interval: max(1, result["interval"] as? Double ?? 5), expires: Date().addingTimeInterval(result["expires_in"] as? Double ?? 300))
    }

    func finishLogin(_ login: DeviceLogin) async throws {
        var interval = login.interval
        while Date() < login.expires {
            try await Task.sleep(for: .seconds(interval))
            let result = try await oauth("/token", values: ["grant_type": "device_code", "code": login.deviceCode, "client_id": clientID, "client_secret": clientSecret])
            try Task.checkCancellation()
            if let token = result["access_token"] as? String {
                try store(result, access: token)
                return
            }
            switch result["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw MusicError.message("Вход не подтверждён или код истёк. Получите новый код.")
            }
        }
        throw MusicError.message("Время действия кода истекло. Получите новый код.")
    }

    private func store(_ result: [String: Any], access: String) throws {
        let next = Credentials(access: access, refresh: result["refresh_token"] as? String ?? credentials?.refresh,
                               expires: (result["expires_in"] as? Double).map { Date().addingTimeInterval($0) })
        try CredentialStore.save(next)
        credentials = next
    }

    private func accessToken() async throws -> String {
        guard let current = credentials else { throw MusicError.unauthorized }
        if let expiry = current.expires, expiry < Date().addingTimeInterval(60), let refresh = current.refresh {
            let result = try await oauth("/token", values: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID, "client_secret": clientSecret])
            try Task.checkCancellation()
            // Logout or another successful refresh may have happened while the request was in flight.
            guard let latest = credentials else { throw MusicError.unauthorized }
            if latest.access != current.access { return latest.access }
            guard let access = result["access_token"] as? String else { throw MusicError.unauthorized }
            try store(result, access: access)
        }
        return credentials!.access
    }

    private func request(_ path: String, query: [String: String] = [:], form values: [String: String]? = nil, json: [String: Any]? = nil, desktop: Bool = false) async throws -> Any {
        var components = URLComponents(string: "https://api.music.yandex.net" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("OAuth " + (try await accessToken()), forHTTPHeaderField: "Authorization")
        request.setValue(desktop ? "YandexMusicDesktopAppWindows/5.126.1" : "YandexMusicAndroid/24023621", forHTTPHeaderField: "X-Yandex-Music-Client")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        if desktop {
            let device = UserDefaults.standard.string(forKey: "deviceID") ?? "fast-music-mac"
            let hashed = SHA256.hash(data: Data(device.utf8)).map { String(format: "%02x", $0) }.joined()
            request.setValue("manufacturer=; model=; uuid=\(device); os=win32; os_version=; device_id=\(hashed); clid=0", forHTTPHeaderField: "X-Yandex-Music-Device")
            request.setValue("1", forHTTPHeaderField: "X-Yandex-Music-Without-Invocation-Info")
        }
        if let values {
            request.httpMethod = "POST"; request.httpBody = form(values)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if let json {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else { throw MusicError.message("Яндекс не смог выполнить запрос. Попробуйте ещё раз.") }
        return object["result"] ?? object
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw MusicError.message("Нет ответа сервера.") }
        if response.statusCode == 401 { throw MusicError.unauthorized }
        if response.statusCode == 403 { throw MusicError.message("Яндекс ограничил доступ. Проверьте подписку Плюс и доступность трека.") }
        guard (200...299).contains(response.statusCode) else { throw MusicError.message("Ошибка Яндекса (\(response.statusCode)). Попробуйте ещё раз.") }
    }

    func account() async throws -> (id: String, name: String) {
        let result = try await request("/account/status") as? [String: Any]
        guard let account = result?["account"] as? [String: Any], let id = stringID(account["uid"]) else { throw MusicError.message("Не удалось загрузить аккаунт.") }
        return (id, account["displayName"] as? String ?? "Яндекс")
    }

    func search(_ text: String) async throws -> SearchResults {
        let result = try await request("/search", query: ["text": text, "type": "all", "page": "0"]) as? [String: Any] ?? [:]
        func results(_ key: String) -> [[String: Any]] { (result[key] as? [String: Any])?["results"] as? [[String: Any]] ?? [] }
        var search = SearchResults(tracks: results("tracks").compactMap(Track.init(json:)))
        search.items = results("artists").prefix(8).compactMap { value in
            guard let id = stringID(value["id"]), let name = value["name"] as? String else { return nil }
            return CatalogItem(id: id, title: name, subtitle: "Исполнитель", cover: (value["cover"] as? [String: Any])?["uri"] as? String, kind: .artist, owner: nil)
        }
        search.items += results("albums").prefix(8).compactMap { value in
            guard let id = stringID(value["id"]), let name = value["title"] as? String else { return nil }
            return CatalogItem(id: id, title: name, subtitle: "Альбом", cover: value["coverUri"] as? String, kind: .album, owner: nil)
        }
        return search
    }

    func tracks(ids: [String]) async throws -> [Track] {
        guard !ids.isEmpty else { return [] }
        let result = try await request("/tracks", form: ["track-ids": ids.joined(separator: ",")]) as? [[String: Any]] ?? []
        let found = Dictionary(result.compactMap(Track.init(json:)).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { found[$0.components(separatedBy: ":")[0]] }
    }

    func likedIDs(user: String) async throws -> [String] {
        let result = try await request("/users/\(user)/likes/tracks") as? [String: Any]
        let library = result?["library"] as? [String: Any]
        return (library?["tracks"] as? [[String: Any]] ?? []).compactMap { stringID($0["id"]) }
    }

    func like(_ track: Track, user: String, remove: Bool) async throws {
        _ = try await request("/users/\(user)/likes/tracks/\(remove ? "remove" : "add-multiple")", form: ["track-ids": track.fullID])
    }

    func playlists(user: String) async throws -> [CatalogItem] {
        let result = try await request("/users/\(user)/playlists/list") as? [[String: Any]] ?? []
        return result.compactMap { value in
            guard let id = stringID(value["kind"]), let title = value["title"] as? String else { return nil }
            let cover = value["cover"] as? [String: Any]
            return CatalogItem(id: id, title: title, subtitle: "\(value["trackCount"] as? Int ?? 0) треков", cover: cover?["uri"] as? String ?? (cover?["itemsUri"] as? [String])?.first, kind: .playlist, owner: user)
        }
    }

    func contents(_ item: CatalogItem) async throws -> [Track] {
        switch item.kind {
        case .artist:
            let result = try await request("/artists/\(item.id)/tracks", query: ["page": "0", "page-size": "100"]) as? [String: Any]
            return (result?["tracks"] as? [[String: Any]] ?? []).compactMap(Track.init(json:))
        case .album:
            let result = try await request("/albums/\(item.id)/with-tracks") as? [String: Any]
            return (result?["volumes"] as? [[[String: Any]]] ?? []).flatMap { $0 }.compactMap(Track.init(json:))
        case .playlist:
            guard let owner = item.owner else { return [] }
            let result = try await request("/users/\(owner)/playlists/\(item.id)") as? [String: Any]
            let entries = result?["tracks"] as? [[String: Any]] ?? []
            let embedded = entries.compactMap { ($0["track"] as? [String: Any]).flatMap(Track.init(json:)) }
            if !embedded.isEmpty { return embedded }
            return try await tracks(ids: entries.prefix(200).compactMap { stringID($0["id"]) })
        }
    }

    func wave(session id: String? = nil, queue: [String] = []) async throws -> WaveBatch {
        let path = id.map { "/rotor/session/\($0)/tracks" } ?? "/rotor/session/new"
        let body: [String: Any] = id == nil
            ? ["seeds": ["user:onyourwave"], "includeTracksInResponse": true, "includeWaveModel": true, "interactive": true]
            : ["queue": queue]
        let result = try await request(path, json: body, desktop: true) as? [String: Any] ?? [:]
        let tracks = (result["sequence"] as? [[String: Any]] ?? []).compactMap { ($0["track"] as? [String: Any]).flatMap(Track.init(json:)) }
        guard !tracks.isEmpty, let sessionID = result["radioSessionId"] as? String ?? id else { throw MusicError.message("Моя волна пока не вернула треки. Попробуйте ещё раз.") }
        return WaveBatch(session: sessionID, batch: result["batchId"] as? String ?? "", tracks: tracks)
    }

    func feedback(session id: String, batch: String, kind: String, track: Track?, played: Double) async throws {
        var event: [String: Any] = ["type": kind, "timestamp": ISO8601DateFormatter().string(from: Date())]
        if let track { event["trackId"] = track.id; event["totalPlayedSeconds"] = max(0, played); event["trackLengthSeconds"] = track.duration }
        let source = "desktop_win-home-play"
        if kind == "radioStarted" { event["from"] = source }
        var body: [String: Any] = ["event": event, "from": source]
        if kind != "radioStarted" { body["batchId"] = batch }
        _ = try await request("/rotor/session/\(id)/feedback/", json: body, desktop: true)
    }

    func streamURL(_ track: Track) async throws -> URL {
        let result = try await request("/tracks/\(track.id)/download-info") as? [[String: Any]] ?? []
        let candidates = result.filter { $0["codec"] as? String == "mp3" && $0["preview"] as? Bool != true }
        guard let best = candidates.max(by: { ($0["bitrateInKbps"] as? Int ?? 0) < ($1["bitrateInKbps"] as? Int ?? 0) }), let address = best["downloadInfoUrl"] as? String, let url = URL(string: address), NetworkPolicy.yandex(url) else {
            throw MusicError.message("Полный трек недоступен. Проверьте подписку Плюс или выберите другой трек.")
        }
        // CDN metadata is requested without the account token.
        let (data, response) = try await session.data(from: url)
        try validate(response)
        let reader = StreamMetadata()
        let parser = XMLParser(data: data); parser.delegate = reader
        guard parser.parse(), let host = reader.values["host"], let path = reader.values["path"], path.hasPrefix("/"), let ts = reader.values["ts"], let salt = reader.values["s"] else { throw MusicError.message("Не удалось получить адрес аудио.") }
        let digest = Insecure.MD5.hash(data: Data(("XGRlBW9FXlekgbPrRHuSiA" + path.dropFirst() + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        guard let stream = URL(string: "https://\(host)/get-mp3/\(digest)/\(ts)\(path)"), NetworkPolicy.yandex(stream) else { throw MusicError.unsafeURL }
        return stream
    }
}

private final class StreamMetadata: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var element = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { element = elementName }
    func parser(_ parser: XMLParser, foundCharacters string: String) { values[element, default: ""] += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { element = "" }
}
