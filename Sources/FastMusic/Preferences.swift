import AppKit
import SwiftUI
import Carbon
import ServiceManagement

enum ShortcutAction: String, CaseIterable, Codable {
    case panel, wave, favorites
    var title: String {
        switch self { case .panel: "Открыть плеер"; case .wave: "Включить Мою волну"; case .favorites: "Включить любимое" }
    }
}

struct KeyBinding: Codable, Equatable {
    let code: UInt32
    let modifiers: UInt32
    let key: String
    var label: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + key
    }
    static func from(_ event: NSEvent) -> KeyBinding? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let key = event.charactersIgnoringModifiers, !key.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return KeyBinding(code: UInt32(event.keyCode), modifiers: modifiers, key: key.uppercased())
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var bindings: [ShortcutAction: KeyBinding] = [:]
    @Published var error: String?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    var onAction: ((ShortcutAction) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var started = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "shortcuts"), let saved = try? JSONDecoder().decode([ShortcutAction: KeyBinding].self, from: data) { bindings = saved }
        else {
            let modifiers = UInt32(cmdKey | shiftKey)
            bindings = [.panel: KeyBinding(code: 46, modifiers: modifiers, key: "M"),
                        .wave: KeyBinding(code: 13, modifiers: modifiers, key: "W"),
                        .favorites: KeyBinding(code: 37, modifiers: modifiers, key: "L")]
        }
        refreshLogin()
    }

    func start() {
        guard !started else { return }; started = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let number = Int(id.id)
            Task { @MainActor in
                guard ShortcutAction.allCases.indices.contains(number) else { return }
                Preferences.shared.onAction?(ShortcutAction.allCases[number])
            }
            return noErr
        }, 1, &type, nil, &handler)
        register()
    }

    func set(_ binding: KeyBinding?, for action: ShortcutAction) {
        if let binding, bindings.contains(where: { $0.key != action && $0.value.code == binding.code && $0.value.modifiers == binding.modifiers }) {
            register(); error = "Это сочетание уже назначено другому действию."; return
        }
        bindings[action] = binding
        UserDefaults.standard.set(try? JSONEncoder().encode(bindings), forKey: "shortcuts")
        register()
    }

    func suspendShortcuts() { refs.forEach { UnregisterEventHotKey($0) }; refs = [] }
    func resumeShortcuts() { register() }

    private func register() {
        refs.forEach { UnregisterEventHotKey($0) }; refs = []; error = nil
        guard started else { return }
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let binding = bindings[action] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.code, binding.modifiers, EventHotKeyID(signature: 0x464D5553, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { error = "Не удалось назначить \(binding.label). Возможно, сочетание занято другой программой." }
        }
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch { self.error = "Не удалось изменить автозапуск: \(error.localizedDescription)"; refreshLogin() }
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var recording: ShortcutAction?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Запускать при входе в macOS", isOn: Binding(get: { preferences.loginEnabled }, set: preferences.setLogin))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            if preferences.loginNeedsApproval {
                Button("Разрешить в настройках macOS") { SMAppService.openSystemSettingsLoginItems() }.font(.system(size: 11))
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            Text("Горячие клавиши").font(.system(size: 12, weight: .semibold))
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title).font(.system(size: 12))
                    Spacer()
                    ShortcutRecorder(recording: recording == action, label: preferences.bindings[action]?.label ?? "Не задано", begin: { preferences.suspendShortcuts(); recording = action }, finish: { binding in
                        recording = nil
                        if let binding { preferences.set(binding, for: action) }
                        else { preferences.resumeShortcuts() }
                    }).frame(width: 110, height: 28)
                    Button { preferences.set(nil, for: action) } label: { Image(systemName: "xmark.circle").foregroundStyle(Theme.muted) }.help("Убрать сочетание")
                }
            }
            Text("Работают из любого приложения. Нажмите сочетание, чтобы изменить. Esc — отмена. Поиск в плеере — ⌘F.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let error = preferences.error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.yellow).fixedSize(horizontal: false, vertical: true) }
        }.onAppear { preferences.refreshLogin() }
        .onDisappear { recording = nil; preferences.resumeShortcuts() }
        .onReceive(NotificationCenter.default.publisher(for: .fastMusicPanelClosed)) { _ in recording = nil; preferences.resumeShortcuts() }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let recording: Bool
    let label: String
    let begin: () -> Void
    let finish: (KeyBinding?) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.begin = begin; view.finish = finish; view.recording = recording
        view.title = recording ? "Нажмите клавиши…" : label
        if recording { view.window?.makeFirstResponder(view) }
    }
}

final class RecorderButton: NSButton {
    var begin: (() -> Void)?
    var finish: ((KeyBinding?) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() { super.init(frame: .zero); bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 11, weight: .medium); target = self; action = #selector(record) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func record() { begin?(); window?.makeFirstResponder(self) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish?(nil); return }
        if let binding = KeyBinding.from(event) { finish?(binding) }
    }
}
