import AppKit
import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class MusicStore: ObservableObject {
    enum Section: String { case wave, collection, favorites, search, recent }
    let api = YandexAPI()
    let demo: Bool
    @Published var section: Section = .wave
    @Published var signedIn = false
    @Published var accountName = ""
    @Published var login: DeviceLogin?
    @Published var loggingIn = false
    @Published var error: String?
    @Published var busy = false
    @Published var loadingAudio = false
    @Published var current: Track?
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.65 { didSet { player?.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "volume") } }
    @Published var shuffle = false
    @Published var query = ""
    @Published var tracks: [Track] = []
    @Published var catalog: [CatalogItem] = []
    @Published var liked: Set<String> = []
    @Published var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    @Published var detailTitle: String?
    @Published var hasMoreFavorites = false
    @Published var likeBusy = false
    private var favoriteIDs: [String] = []
    private var userID = ""
    private var queue: [Track] = []
    private var index = 0
    private var wave: WaveBatch?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var endedObserver: NSObjectProtocol?
    private var loginTask: Task<Void, Never>?
    private var contentTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var visible = false
    private var requestID = UUID()
    private var playbackID = UUID()
    private var accountEpoch = UUID()
    private var contentUnloaded = false
    private var likeLoadTask: Task<Void, Never>?

    init(demo: Bool = false) {
        self.demo = demo
        if let stored = UserDefaults.standard.object(forKey: "volume") as? Double { volume = stored }
        if demo {
            current = Track(id: "preview", title: "Pepel Nahudi — не я", artist: "Pepel Nahudi", duration: 197)
            position = 84; duration = 197; liked = ["preview"]
        } else {
            installRemoteCommands()
            Task {
                do { if try await api.restore() { try await loadAccount() } }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    func signIn() {
        guard !demo else { return }
        loginTask?.cancel(); error = nil; loggingIn = true
        var device = UserDefaults.standard.string(forKey: "deviceID")
        if device == nil { device = UUID().uuidString.replacingOccurrences(of: "-", with: ""); UserDefaults.standard.set(device, forKey: "deviceID") }
        let deviceID = device!
        loginTask = Task {
            do {
                let code = try await api.beginLogin(deviceID: deviceID)
                try Task.checkCancellation()
                login = code
                try await api.finishLogin(code)
                try await loadAccount()
                login = nil; loggingIn = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; loggingIn = false; login = nil }
        }
    }

    func cancelLogin() { loginTask?.cancel(); loginTask = nil; login = nil; loggingIn = false }

    private func loadAccount() async throws {
        let account = try await api.account()
        try Task.checkCancellation()
        userID = account.id; accountName = account.name; signedIn = true
        let epoch = accountEpoch
        likeLoadTask = Task {
            do {
                let ids = try await api.likedIDs(user: account.id)
                guard epoch == accountEpoch else { return }
                favoriteIDs = ids; liked = Set(ids)
            } catch { /* Likes can still be refreshed explicitly from the Favorites tab. */ }
        }
    }

    func signOut() {
        cancelLogin(); contentTask?.cancel(); playTask?.cancel(); idleTask?.cancel(); likeLoadTask?.cancel()
        requestID = UUID(); playbackID = UUID(); accountEpoch = UUID()
        pause(); releasePlayer()
        current = nil; queue = []; tracks = []; catalog = []; liked = []; favoriteIDs = []; wave = nil
        signedIn = false; userID = ""; accountName = ""; detailTitle = nil; busy = false; loadingAudio = false; likeBusy = false
        query = ""; recentSearches = []; UserDefaults.standard.removeObject(forKey: "recentSearches")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        Task { do { try await api.logout() } catch { self.error = error.localizedDescription } }
    }

    func navigate(_ next: Section) {
        section = next; detailTitle = nil; contentTask?.cancel(); requestID = UUID(); busy = false
        tracks = []; catalog = []; hasMoreFavorites = false; error = nil
        guard signedIn else { return }
        switch next {
        case .wave: break
        case .search: if !query.isEmpty { search() }
        case .recent: break
        case .collection:
            loadContent { [self] in ([], try await api.playlists(user: userID)) }
        case .favorites:
            loadContent { [self] in
                let ids = try await api.likedIDs(user: userID)
                try Task.checkCancellation()
                favoriteIDs = ids; liked = Set(ids)
                let result = try await api.tracks(ids: Array(ids.prefix(100)))
                try Task.checkCancellation()
                hasMoreFavorites = ids.count > 100
                return (result, [])
            }
        }
    }

    func moreFavorites() {
        guard !busy else { return }
        let previous = tracks
        loadContent { [self] in
            let more = try await api.tracks(ids: Array(favoriteIDs.dropFirst(previous.count).prefix(100)))
            try Task.checkCancellation()
            hasMoreFavorites = !more.isEmpty && previous.count + more.count < favoriteIDs.count
            return (previous + more, [])
        }
    }

    func search(debounce: Bool = false) {
        section = .search; detailTitle = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { contentTask?.cancel(); requestID = UUID(); busy = false; tracks = []; catalog = []; return }
        guard signedIn else { return }
        loadContent { [self] in
            if debounce { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await api.search(text)
            return (result.tracks, result.items)
        }
    }

    func rememberSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        recentSearches.insert(text, at: 0); recentSearches = Array(recentSearches.prefix(20))
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }

    func clearHistory() { recentSearches = []; UserDefaults.standard.removeObject(forKey: "recentSearches") }

    func open(_ item: CatalogItem) {
        if section == .search { rememberSearch() }
        detailTitle = item.title
        loadContent { [self] in (try await api.contents(item), []) }
    }

    private func loadContent(_ operation: @escaping @MainActor () async throws -> ([Track], [CatalogItem])) {
        contentTask?.cancel()
        let id = UUID(); requestID = id; busy = true; error = nil
        contentTask = Task {
            do {
                let (newTracks, items) = try await operation()
                try Task.checkCancellation()
                guard id == requestID else { return }
                tracks = newTracks; catalog = items; busy = false
            } catch {
                guard id == requestID, !Task.isCancelled else { return }
                self.error = error.localizedDescription; busy = false
            }
        }
    }

    func startWave() {
        guard signedIn, !loadingAudio else { return }
        playTask?.cancel(); loadingAudio = true; error = nil
        let id = UUID(); playbackID = id
        playTask = Task {
            do {
                let batch = try await api.wave()
                try Task.checkCancellation()
                guard id == playbackID else { return }
                report("skip")
                wave = batch; queue = batch.tracks; index = 0
                report("radioStarted", track: nil)
                await prepare(queue[0], id: id)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loadingAudio = false } }
        }
    }

    func startFavorites() {
        guard signedIn, !loadingAudio else {
            if !signedIn { error = "Сначала войдите в Яндекс, чтобы включить любимые треки." }
            return
        }
        contentTask?.cancel(); requestID = UUID(); busy = false
        playTask?.cancel(); loadingAudio = true; error = nil
        let id = UUID(); playbackID = id
        playTask = Task {
            do {
                let ids = try await api.likedIDs(user: userID)
                let selected = shuffle ? Array(ids.shuffled().prefix(100)) : Array(ids.prefix(100))
                let favorites = try await api.tracks(ids: selected).filter(\.available)
                try Task.checkCancellation()
                guard id == playbackID else { return }
                guard let first = favorites.first else { throw MusicError.message("В любимом пока нет доступных треков.") }
                report("skip"); wave = nil; queue = favorites; index = 0
                liked = Set(ids); favoriteIDs = selected; hasMoreFavorites = false; section = .favorites
                tracks = favorites; catalog = []; detailTitle = nil
                await prepare(first, id: id)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loadingAudio = false } }
        }
    }

    func play(_ track: Track, in list: [Track]) {
        guard track.available, signedIn else { return }
        if section == .search { rememberSearch() }
        report("skip")
        wave = nil; queue = list.filter(\.available); index = queue.firstIndex(where: { $0.id == track.id }) ?? 0
        playTask?.cancel(); let id = UUID(); playbackID = id
        playTask = Task { await prepare(track, id: id) }
    }

    private func prepare(_ track: Track, id: UUID, resume: Double = 0) async {
        idleTask?.cancel(); pause(scheduleRelease: false)
        loadingAudio = true; error = nil
        do {
            let url = try await api.streamURL(track)
            try Task.checkCancellation()
            guard playbackID == id else { return }
            releasePlayer()
            current = track; duration = track.duration; position = resume
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 12
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.volume = Float(volume)
            player = newPlayer
            itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor in
                    guard let self, self.playbackID == id else { return }
                    if failed { self.error = "Не удалось воспроизвести трек. Попробуйте следующий."; self.loadingAudio = false; self.pause() }
                }
            }
            statusObserver = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let running = player.timeControlStatus == .playing
                let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                Task { @MainActor in
                    guard let self, self.playbackID == id else { return }
                    self.playing = running; self.loadingAudio = waiting
                    self.syncProgressObserver(); self.updateNowPlaying()
                }
            }
            endedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.next(finished: true) }
            }
            if resume > 0 { await newPlayer.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
            guard playbackID == id, !Task.isCancelled else { return }
            newPlayer.play(); loadingAudio = false
            report("trackStarted")
            updateNowPlaying()
        } catch {
            guard playbackID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription; loadingAudio = false
        }
    }

    func togglePlayback() {
        guard !demo else { return }
        if playing || loadingAudio { pause(); return }
        if let player { idleTask?.cancel(); player.play(); return }
        if let current {
            let id = UUID(); playbackID = id; let resume = position
            playTask = Task { await prepare(current, id: id, resume: resume) }
        } else { startWave() }
    }

    func pause(scheduleRelease: Bool = true) {
        if scheduleRelease { playTask?.cancel(); loadingAudio = false }
        if let player { let t = player.currentTime().seconds; if t.isFinite { position = t }; player.pause() }
        playing = false; syncProgressObserver(); updateNowPlaying()
        if scheduleRelease { scheduleIdleRelease() }
    }

    func next(finished: Bool = false) {
        guard !queue.isEmpty, !loadingAudio else { return }
        report(finished ? "trackFinished" : "skip")
        let nextIndex = shuffle && wave == nil ? queue.indices.filter { $0 != index }.randomElement() ?? index : index + 1
        if nextIndex < queue.count {
            index = nextIndex; playTask?.cancel(); let id = UUID(); playbackID = id
            let track = queue[index]; playTask = Task { await prepare(track, id: id) }
        } else if let wave {
            playTask?.cancel(); loadingAudio = true; let id = UUID(); playbackID = id
            playTask = Task {
                do {
                    let batch = try await api.wave(session: wave.session, queue: current.map { [$0.id] } ?? [])
                    try Task.checkCancellation()
                    self.wave = batch; queue = batch.tracks; index = 0
                    await prepare(queue[0], id: id)
                } catch { if !Task.isCancelled { self.error = error.localizedDescription; loadingAudio = false; pause() } }
            }
        } else { pause(); position = duration }
    }

    func previous() {
        guard !demo else { return }
        if position > 3 { seek(0); return }
        guard index > 0 else { seek(0); return }
        report("skip"); index -= 1
        playTask?.cancel(); let id = UUID(); playbackID = id; let track = queue[index]
        playTask = Task { await prepare(track, id: id) }
    }

    func seek(_ time: Double) {
        position = min(max(0, time), duration)
        player?.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func toggleLike() {
        guard let track = current, signedIn, !likeBusy else { return }
        let remove = liked.contains(track.id); let epoch = accountEpoch; let user = userID
        likeBusy = true
        Task {
            defer { if epoch == accountEpoch { likeBusy = false } }
            do {
                try await api.like(track, user: user, remove: remove)
                guard epoch == accountEpoch else { return }
                if remove { liked.remove(track.id) } else { liked.insert(track.id) }
            } catch { if epoch == accountEpoch { self.error = error.localizedDescription } }
        }
    }

    private func report(_ kind: String, track: Track? = nil) {
        guard let wave else { return }
        let item = kind == "radioStarted" ? nil : (track ?? current)
        let played = player?.currentTime().seconds ?? position
        Task { try? await api.feedback(session: wave.session, batch: wave.batch, kind: kind, track: item, played: played.isFinite ? played : 0) }
    }

    func setVisible(_ value: Bool) {
        visible = value; syncProgressObserver()
        if value {
            idleTask?.cancel()
            if let player { let time = player.currentTime().seconds; if time.isFinite { position = time } }
            if contentUnloaded { contentUnloaded = false; navigate(section) }
        } else if !playing && !loadingAudio { scheduleIdleRelease() }
    }

    private func syncProgressObserver() {
        if let observer = timeObserver { player?.removeTimeObserver(observer); timeObserver = nil }
        guard visible, playing, let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, time.seconds.isFinite else { return }
                self.position = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
    }

    private func scheduleIdleRelease() {
        idleTask?.cancel()
        guard !visible, !demo else { return }
        idleTask = Task {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard !playing, !loadingAudio, !visible else { return }
            releasePlayer(); tracks = []; catalog = []; contentUnloaded = true; ArtworkCache.shared.clear()
        }
    }

    private func releasePlayer() {
        if let observer = timeObserver { player?.removeTimeObserver(observer); timeObserver = nil }
        statusObserver = nil; itemObserver = nil
        if let observer = endedObserver { NotificationCenter.default.removeObserver(observer); endedObserver = nil }
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
    }

    private func updateNowPlaying() {
        guard !demo, let track = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayback() }; return .success }
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.playing == false { self?.togglePlayback() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime; Task { @MainActor in self?.seek(time) }; return .success
        }
    }
}
