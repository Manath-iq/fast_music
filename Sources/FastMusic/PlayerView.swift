// Reference-locked native app shell. SF Symbols + SwiftUI/AppKit primitives, no web registries.
// Craft review: hierarchy 5, specificity 5, restraint 5; visual approval pending.
import SwiftUI

enum Theme {
    static let background = Color(red: 18/255, green: 17/255, blue: 18/255)
    static let surface = Color(red: 37/255, green: 34/255, blue: 36/255)
    static let yellow = Color(red: 1, green: 237/255, blue: 0)
    static let text = Color(red: 245/255, green: 245/255, blue: 244/255)
    static let muted = Color(red: 180/255, green: 179/255, blue: 181/255)
    static let pink = Color(red: 0.8, green: 0.08, blue: 0.47)
}

struct Burst: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX + rect.width * 0.10, y: rect.midY - rect.height * 0.07)
        for ray in 0..<13 {
            let angle = CGFloat(ray) * .pi * 2 / 13
            let radius = min(rect.width, rect.height) * 0.5
            let tip = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
            let side = CGPoint(x: center.x + cos(angle + 0.9) * radius * 0.19, y: center.y + sin(angle + 0.9) * radius * 0.19)
            path.move(to: center); path.addLine(to: tip); path.addLine(to: side); path.closeSubpath()
        }
        return path
    }
}

struct TactileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(hovered && enabled ? 0.055 : 0)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PlayerView: View {
    @ObservedObject var store: MusicStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool
    @State private var scrub: Double?
    @State private var confirmLogout = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 20)
            tabs.padding(.bottom, 24)
            nowPlaying
            transport.padding(.top, 16).padding(.bottom, 12)
            timeline
            volume.padding(.top, 6)
            divider.padding(.top, 14).padding(.bottom, 14)
            shortcuts
            if let error = store.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.yellow)
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { store.error = nil } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }.help("Скрыть сообщение")
                }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 14)
            }
            if store.demo {
                Text("ПРЕДПРОСМОТР ДИЗАЙНА · БЕЗ ВОСПРОИЗВЕДЕНИЯ")
                    .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 16)
            } else if !store.signedIn {
                divider.padding(.vertical, 16)
                loginPanel
            } else if store.section != .wave {
                divider.padding(.vertical, 14)
                libraryPanel
            }
        }
        .padding(20)
        .frame(width: 480)
        .foregroundStyle(Theme.text)
        .background {
            ZStack {
                if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
                Theme.background.opacity(reduceTransparency ? 1 : 0.94)
                LinearGradient(colors: [.white.opacity(0.035), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .buttonStyle(TactileStyle())
        .preferredColorScheme(.dark)
        .tint(Theme.yellow)
        .confirmationDialog("Выйти из Яндекса?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { store.signOut() }
        } message: { Text("Токен будет удалён из Связки ключей. Для следующего входа потребуется новый код.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Burst().fill(Theme.yellow).frame(width: 30, height: 30)
            (Text("Яндекс ").fontWeight(.medium) + Text("Музыка").fontWeight(.bold).foregroundColor(Theme.yellow))
                .font(.system(size: 18)).fixedSize()
            Spacer(minLength: 2)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.muted)
                TextField("Найти музыку", text: $store.query)
                    .font(.system(size: 12)).textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { store.rememberSearch(); store.search() }
                    .onChange(of: store.query) { _, _ in store.search(debounce: true) }
                    .accessibilityLabel("Поиск музыки")
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.help("Очистить поиск")
                }
            }
            .padding(.horizontal, 11).frame(height: 32)
            .background(.white.opacity(0.065), in: Capsule())
            .overlay(Capsule().strokeBorder(searchFocused ? Theme.yellow.opacity(0.8) : .clear, lineWidth: 1))
            Menu {
                if store.signedIn {
                    Text(store.accountName)
                    Button("Выйти из Яндекса…") { confirmLogout = true }
                    Divider()
                }
                Button("О Fast Music") { NSWorkspace.shared.open(URL(string: "https://github.com/Manath-iq/fast_music")!) }
                Button("Завершить Fast Music", role: .destructive) { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 30, height: 30)
                    .background(.white.opacity(0.065), in: Circle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Настройки")
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab("Моя волна", icon: nil, section: .wave)
            tab("Коллекция", icon: "heart", section: .collection)
            tab("Поиск", icon: "magnifyingglass", section: .search)
        }
        .padding(2).background(.white.opacity(0.065), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.055), lineWidth: 1))
    }

    private func tab(_ title: String, icon: String?, section: MusicStore.Section) -> some View {
        let active = store.section == section || (section == .collection && store.section == .favorites)
        return Button {
            store.navigate(section)
            if section == .search { searchFocused = true }
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 17, weight: .regular)) }
                else { Burst().fill(active ? Theme.yellow : Theme.muted).frame(width: 23, height: 23) }
                Text(title).font(.system(size: 13, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background {
                if active {
                    Capsule().fill(LinearGradient(colors: [Theme.yellow.opacity(0.17), Theme.yellow.opacity(0.045)], startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(Theme.yellow, lineWidth: 1)
                        .shadow(color: Theme.yellow.opacity(0.25), radius: 5)
                }
            }
            .contentShape(Capsule())
        }
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(title)
    }

    private var nowPlaying: some View {
        HStack(spacing: 16) {
            CoverArt(uri: store.current?.cover, size: 88, demo: store.demo)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.current?.title ?? "Ваша музыка. Рядом.")
                    .font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    .help(store.current?.title ?? "Выберите трек или включите Мою волну")
                Text(store.current?.artist ?? "Включите свою волну")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 88)
        .background(alignment: .trailing) {
            if store.current != nil {
                if let glow = LocalArtwork.glow {
                    Image(nsImage: glow).resizable().frame(width: 330, height: 170).opacity(0.75)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }

    private var transport: some View {
        HStack {
            iconButton("shuffle", label: "Перемешать", active: store.shuffle, background: true) { store.shuffle.toggle() }
                .disabled(store.current == nil || store.section == .wave)
            Spacer()
            iconButton("backward.end.fill", label: "Предыдущий трек") { store.previous() }.disabled(store.current == nil)
            Spacer()
            Button { store.togglePlayback() } label: {
                ZStack {
                    Circle().fill(Theme.yellow)
                    if store.loadingAudio { ProgressView().controlSize(.small).tint(Theme.background) }
                    else {
                        Image(systemName: store.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .bold)).foregroundStyle(Theme.background)
                            .offset(x: store.playing ? 0 : 2)
                    }
                }.frame(width: 56, height: 56)
            }
            .disabled(!store.signedIn && !store.demo)
            .help(store.playing ? "Пауза" : "Воспроизвести")
            .accessibilityLabel(store.playing ? "Пауза" : "Воспроизвести")
            Spacer()
            iconButton("forward.end.fill", label: "Следующий трек") { store.next() }.disabled(store.current == nil || store.loadingAudio)
            Spacer()
            iconButton(store.current.map { store.liked.contains($0.id) } == true ? "heart.fill" : "heart", label: "Любимый трек", active: store.current.map { store.liked.contains($0.id) } == true, background: true) { store.toggleLike() }
                .disabled(store.current == nil || store.likeBusy)
        }.padding(.horizontal, 16)
    }

    private var timeline: some View {
        HStack(spacing: 12) {
            Text(clock(scrub ?? store.position)).frame(width: 34, alignment: .leading)
            MusicSlider(value: Binding(get: { scrub ?? store.position }, set: { scrub = $0 }), range: 0...max(1, store.duration), color: Theme.yellow, label: "Позиция в треке") { editing in
                if !editing, let value = scrub { store.seek(value); scrub = nil }
            }.disabled(store.current == nil)
            Text(clock(store.duration)).frame(width: 34, alignment: .trailing)
        }.font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.muted)
    }

    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.1.fill").frame(width: 34, alignment: .leading)
            MusicSlider(value: $store.volume, range: 0...1, color: Theme.text, label: "Громкость") { _ in }
            Image(systemName: "speaker.wave.3.fill").frame(width: 34, alignment: .trailing)
        }.font(.system(size: 15)).foregroundStyle(Theme.muted)
    }

    private var shortcuts: some View {
        HStack(spacing: 9) {
            shortcut("Моя волна", icon: nil, section: .wave)
            shortcut("Коллекция", icon: "heart", section: .collection)
            shortcut("Любимое", icon: "heart.fill", section: .favorites)
            shortcut("Недавнее", icon: "clock", section: .recent)
        }
    }

    private func shortcut(_ title: String, icon: String?, section: MusicStore.Section) -> some View {
        let active = store.section == section
        return Button {
            store.navigate(section)
            if section == .wave { store.startWave() }
        } label: {
            VStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 23, weight: .regular))
                        .foregroundStyle(section == .favorites ? AnyShapeStyle(LinearGradient(colors: [Theme.text, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Theme.text))
                        .frame(height: 29)
                } else { Burst().fill(Theme.yellow).frame(width: 30, height: 29) }
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 70)
            .background(LinearGradient(colors: [active ? Theme.yellow.opacity(0.10) : .white.opacity(0.065), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(active ? Theme.yellow : .white.opacity(0.13), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }.help(section == .recent ? "Недавние поиски" : title)
    }

    private var loginPanel: some View {
        VStack(spacing: 12) {
            if let login = store.login {
                Text("Введите код на странице Яндекса").font(.system(size: 13, weight: .medium))
                Text(login.userCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).tracking(4).textSelection(.enabled)
                HStack(spacing: 16) {
                    Button("Открыть ya.ru/device") { NSWorkspace.shared.open(URL(string: "https://ya.ru/device")!) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.yellow)
                    Button("Отмена") { store.cancelLogin() }.foregroundStyle(Theme.muted)
                }
                Text("Ожидаем подтверждение входа…").font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Вся ваша музыка — здесь").font(.system(size: 13, weight: .semibold))
                        Text("Войдите в Яндекс с подпиской Плюс")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Button { store.signIn() } label: {
                        HStack(spacing: 6) {
                            if store.loggingIn { ProgressView().controlSize(.mini) }
                            Text(store.loggingIn ? "Входим…" : "Войти")
                        }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.background)
                            .padding(.horizontal, 18).frame(height: 34).background(Theme.yellow, in: Capsule())
                    }.disabled(store.loggingIn)
                }
                Text("Пароль остаётся у Яндекса. Токен хранится в Связке ключей Mac.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if store.detailTitle != nil {
                    Button { store.navigate(store.section) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }.help("Назад")
                }
                Text(store.detailTitle ?? sectionTitle).font(.system(size: 14, weight: .semibold))
                Spacer()
                if store.section == .recent && !store.recentSearches.isEmpty {
                    Button("Очистить") { store.clearHistory() }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if store.busy { ProgressView().controlSize(.mini) }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    if store.section == .recent || (store.section == .search && store.query.isEmpty) {
                        if store.recentSearches.isEmpty { emptyState("Здесь появятся ваши поиски", symbol: "clock") }
                        ForEach(store.recentSearches, id: \.self) { text in
                            Button { store.query = text; store.search() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock").foregroundStyle(Theme.muted)
                                    Text(text).lineLimit(1); Spacer()
                                    Image(systemName: "arrow.up.left").foregroundStyle(Theme.muted)
                                }.font(.system(size: 13)).padding(12).contentShape(Rectangle())
                            }
                        }
                    } else {
                        if store.tracks.isEmpty && store.catalog.isEmpty && !store.busy {
                            emptyState(store.section == .search ? "Ничего не найдено" : "Пока здесь пусто", symbol: store.section == .search ? "magnifyingglass" : "music.note.list")
                        }
                        if store.busy && store.tracks.isEmpty {
                            ForEach(0..<3) { _ in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 6).fill(Theme.surface).frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 7) {
                                        Capsule().fill(Theme.surface).frame(width: 180, height: 8)
                                        Capsule().fill(Theme.surface).frame(width: 110, height: 6)
                                    }; Spacer()
                                }.padding(.vertical, 6).accessibilityHidden(true)
                            }
                        }
                        ForEach(store.tracks) { track in
                            Button { store.play(track, in: store.tracks) } label: {
                                HStack(spacing: 11) {
                                    CoverArt(uri: track.cover, size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(store.current?.id == track.id ? Theme.yellow : Theme.text).lineLimit(1)
                                        Text(track.artist).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Text(clock(track.duration)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                                }.padding(7).background(store.current?.id == track.id ? .white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.disabled(!track.available).help(track.available ? "\(track.title) — \(track.artist)" : "Трек недоступен")
                        }
                        ForEach(Array(store.catalog.enumerated()), id: \.offset) { _, item in
                            Button { store.open(item) } label: {
                                HStack(spacing: 11) {
                                    CoverArt(uri: item.cover, size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }.padding(7).contentShape(Rectangle())
                            }
                        }
                        if store.hasMoreFavorites { Button("Загрузить ещё") { store.moreFavorites() }.padding(12).disabled(store.busy) }
                    }
                }
            }.frame(height: 190).scrollIndicators(.hidden)
        }
    }

    private var sectionTitle: String {
        switch store.section {
        case .wave: "Моя волна"
        case .collection: "Мои плейлисты"
        case .favorites: "Любимые треки"
        case .search: "Результаты поиска"
        case .recent: "Недавние поиски"
        }
    }

    private func emptyState(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
            Text(title).font(.system(size: 12))
        }.foregroundStyle(Theme.muted).frame(maxWidth: .infinity).frame(height: 140)
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }

    private func iconButton(_ name: String, label: String, active: Bool = false, background: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 21, weight: .medium))
                .foregroundStyle(active ? Theme.yellow : Theme.text.opacity(0.85))
                .frame(width: 44, height: 38)
                .background(background ? .white.opacity(0.065) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }.help(label).accessibilityLabel(label)
    }
}

// Native NSSlider keeps keyboard, VoiceOver and mouse tracking. Only the cell's drawing changes.
struct MusicSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let label: String
    var editing: (Bool) -> Void

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        let cell = SlimSliderCell()
        cell.onTracking = { active in context.coordinator.parent.editing(active) }
        slider.cell = cell
        slider.target = context.coordinator; slider.action = #selector(Coordinator.changed(_:))
        slider.isContinuous = true; slider.focusRingType = .exterior
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.doubleValue = value
        (slider.cell as? SlimSliderCell)?.tint = NSColor(color)
        slider.isEnabled = context.environment.isEnabled
        slider.needsDisplay = true
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: MusicSlider
        init(_ parent: MusicSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
            if NSApp.currentEvent?.type == .keyDown { parent.editing(false) }
        }
    }
}

final class SlimSliderCell: NSSliderCell {
    var tint = NSColor.yellow
    var onTracking: ((Bool) -> Void)?
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor.white.withAlphaComponent(0.23).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        let fraction = (doubleValue - minValue) / max(1e-9, maxValue - minValue)
        tint.withAlphaComponent(isEnabled ? 1 : 0.3).setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * fraction, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func knobRect(flipped: Bool) -> NSRect {
        let rect = super.knobRect(flipped: flipped)
        return NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12)
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        NSBezierPath(ovalIn: knobRect.offsetBy(dx: 0, dy: 1)).fill()
        tint.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        onTracking?(true)
        return super.startTracking(at: startPoint, in: controlView)
    }
    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        onTracking?(false)
    }
}
