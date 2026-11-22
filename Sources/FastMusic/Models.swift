import Foundation

struct Track: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumID: String?
    let cover: String?
    let duration: Double
    let available: Bool
    var fullID: String { albumID.map { "\(id):\($0)" } ?? id }
    var coverURL: URL? { ArtworkURL.make(cover, size: 240) }

    init?(json: [String: Any]) {
        guard let id = stringID(json["id"]), let title = json["title"] as? String else { return nil }
        self.id = id
        self.title = title
        artist = (json["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        albumID = (json["albums"] as? [[String: Any]])?.first.flatMap { stringID($0["id"]) }
        cover = json["coverUri"] as? String
        // Yandex returns milliseconds, including integer JSON numbers.
        duration = ((json["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000
        available = json["available"] as? Bool ?? true
    }

    init(id: String, title: String, artist: String, albumID: String? = nil, cover: String? = nil, duration: Double = 0, available: Bool = true) {
        self.id = id; self.title = title; self.artist = artist; self.albumID = albumID
        self.cover = cover; self.duration = duration; self.available = available
    }
}

struct CatalogItem: Identifiable, Sendable {
    enum Kind: Sendable { case artist, album, playlist }
    let id: String
    let title: String
    let subtitle: String
    let cover: String?
    let kind: Kind
    let owner: String?
}

struct SearchResults: Sendable {
    var tracks: [Track] = []
    var items: [CatalogItem] = []
}

struct WaveBatch: Sendable {
    let session: String
    let batch: String
    let tracks: [Track]
}

struct Credentials: Codable, Sendable {
    let access: String
    let refresh: String?
    let expires: Date?
}

struct DeviceLogin: Sendable {
    let deviceCode: String
    let userCode: String
    let interval: Double
    let expires: Date
}

enum MusicError: LocalizedError {
    case message(String)
    case unauthorized
    case unsafeURL
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unauthorized: return "Сессия истекла. Выйдите и войдите в Яндекс заново."
        case .unsafeURL: return "Сервер вернул неподдерживаемый адрес."
        }
    }
}

func stringID(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    return (value as? NSNumber)?.stringValue
}

enum NetworkPolicy {
    static func yandex(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased(), url.port == nil || url.port == 443 else { return false }
        return ["yandex.ru", "yandex.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func artwork(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return host == "avatars.yandex.net" || host == "avatars.mds.yandex.net"
    }
}

enum ArtworkURL {
    static func make(_ uri: String?, size: Int) -> URL? {
        guard let uri, !uri.isEmpty else { return nil }
        let address = uri.replacingOccurrences(of: "%%", with: "\(size)x\(size)")
        guard let url = URL(string: address.hasPrefix("https://") ? address : "https://" + address), NetworkPolicy.artwork(url) else { return nil }
        return url
    }
}

func clock(_ seconds: Double) -> String {
    let value = seconds.isFinite ? max(0, Int(seconds)) : 0
    return String(format: "%d:%02d", value / 60, value % 60)
}
