import AppKit
import Carbon

/// A persisted keyboard shortcut registered with macOS, so it works while the
/// app is in the background and the popover is closed.
@MainActor
final class GlobalShortcut: NSObject {
  static let shared = GlobalShortcut()

  private let defaultsKey = "globalPopupShortcut"
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var onPress: (() -> Void)?

  private override init() {
    super.init()
    let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let context else { return noErr }
      let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { shortcut.onPress?() }
      return noErr
    }, 1, [spec], Unmanaged.passUnretained(self).toOpaque(), &handler)
    registerSavedShortcut()
  }

  var displayName: String {
    guard let current else { return "Not set" }
    return Self.name(keyCode: current.keyCode, modifiers: current.modifiers)
  }

  var current: (keyCode: UInt32, modifiers: UInt32)? {
    guard let value = UserDefaults.standard.dictionary(forKey: defaultsKey),
      let keyCode = value["keyCode"] as? UInt32,
      let modifiers = value["modifiers"] as? UInt32 else { return nil }
    return (keyCode, modifiers)
  }

  /// The saved shortcut as an `NSMenuItem` key equivalent, so a menu can show
  /// it where macOS lists shortcuts. Nil when no shortcut is set or AppKit has
  /// no glyph for the key.
  var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
    guard let current else { return nil }
    let specialKeys: [UInt32: Int] = [
      36: 0x0D, 48: 0x09, 49: 0x20, 51: 0x08, 53: 0x1B,
      123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey,
      125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
    ]
    let key: String
    if let special = specialKeys[current.keyCode], let scalar = UnicodeScalar(special) {
      key = String(Character(scalar))
    } else {
      let name = Self.keyName(current.keyCode)
      guard name.count == 1 else { return nil }
      // An uppercase equivalent would imply Shift, so pass Shift explicitly.
      key = name.lowercased()
    }
    var flags: NSEvent.ModifierFlags = []
    if current.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if current.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if current.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    if current.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    return (key, flags)
  }

  func set(keyCode: UInt32, modifiers: UInt32) {
    unregister()
    UserDefaults.standard.set(["keyCode": keyCode, "modifiers": modifiers], forKey: defaultsKey)
    registerSavedShortcut()
  }

  func clear() {
    unregister()
    // Store an empty value rather than removing the key, so a cleared shortcut
    // is not mistaken for a first launch and replaced with the default.
    UserDefaults.standard.set([String: UInt32](), forKey: defaultsKey)
  }

  /// Seeds ⌥⌘P on first launch only, so a shortcut the user cleared stays cleared.
  func registerDefaultIfNeeded() {
    guard UserDefaults.standard.object(forKey: defaultsKey) == nil else { return }
    set(keyCode: 35, modifiers: UInt32(cmdKey | optionKey))
  }

  private func registerSavedShortcut() {
    guard let value = UserDefaults.standard.dictionary(forKey: defaultsKey),
      let keyCode = value["keyCode"] as? UInt32,
      let modifiers = value["modifiers"] as? UInt32
    else { return }
    let id = EventHotKeyID(signature: OSType(0x5454524B), id: 1)
    RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
  }

  private func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
  }

  static func name(keyCode: UInt32, modifiers: UInt32) -> String {
    // Apple's standard modifier order, matching how menus draw shortcuts.
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    result += keyName(keyCode)
    return result
  }

  static func keyName(_ keyCode: UInt32) -> String {
    // macOS virtual key codes are physical keyboard positions, not Unicode
    // values (for example, key code 35 is P).
    let keyNames: [UInt32: String] = [
      0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
      11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
      20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
      29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
      37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
      46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
      123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    if let name = keyNames[keyCode] { return name }
    return "Key \(keyCode)"
  }
}

@MainActor
final class ShortcutRecorderView: NSView {
  private let heading = NSTextField(labelWithString: "Toggle Popup")
  private let instructions = NSTextField(labelWithString: "Set a shortcut to show or hide the TimeTracker popup.")
  private let keys = NSStackView()
  private let keyWell = NSView()
  private let recordButton = NSButton(title: "Record Shortcut", target: nil, action: nil)
  private let clearButton = NSButton()
  private let status = NSTextField(labelWithString: "Click Record to change this shortcut.")
  private var listening = false
  private var keyMonitor: Any?
  private var savedShortcut: (keyCode: UInt32, modifiers: UInt32)?
  private var liveModifiers: UInt32 = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    keys.orientation = .horizontal
    keys.alignment = .centerY
    keys.spacing = 6
    keys.translatesAutoresizingMaskIntoConstraints = false
    heading.font = .systemFont(ofSize: 13, weight: .semibold)
    instructions.font = .systemFont(ofSize: 11)
    instructions.textColor = .secondaryLabelColor
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    status.alignment = .center
    keyWell.wantsLayer = true
    keyWell.layer?.cornerRadius = 9
    keyWell.layer?.borderWidth = 1
    keyWell.layer?.borderColor = NSColor.separatorColor.cgColor
    keyWell.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
    keyWell.addSubview(keys)
    clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear Shortcut")
    clearButton.isBordered = false
    clearButton.imagePosition = .imageOnly
    clearButton.contentTintColor = .tertiaryLabelColor
    clearButton.toolTip = "Clear Shortcut"
    clearButton.target = self
    clearButton.action = #selector(clearShortcut)
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    keyWell.addSubview(clearButton)
    recordButton.bezelStyle = .rounded
    recordButton.controlSize = .regular
    recordButton.target = self
    recordButton.action = #selector(toggleListening)
    heading.translatesAutoresizingMaskIntoConstraints = false
    instructions.translatesAutoresizingMaskIntoConstraints = false
    status.translatesAutoresizingMaskIntoConstraints = false
    keyWell.translatesAutoresizingMaskIntoConstraints = false
    recordButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(heading)
    addSubview(instructions)
    addSubview(keyWell)
    addSubview(recordButton)
    addSubview(status)
    NSLayoutConstraint.activate([
      heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      heading.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      instructions.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      instructions.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
      keyWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      keyWell.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      keyWell.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
      keyWell.heightAnchor.constraint(equalToConstant: 38),
      recordButton.centerXAnchor.constraint(equalTo: centerXAnchor),
      recordButton.topAnchor.constraint(equalTo: keyWell.bottomAnchor, constant: 9),
      recordButton.widthAnchor.constraint(equalToConstant: 140),
      recordButton.heightAnchor.constraint(equalToConstant: 28),
      status.centerXAnchor.constraint(equalTo: centerXAnchor),
      status.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 7),
      keys.leadingAnchor.constraint(greaterThanOrEqualTo: keyWell.leadingAnchor, constant: 8),
      keys.trailingAnchor.constraint(lessThanOrEqualTo: keyWell.trailingAnchor, constant: -8),
      keys.centerYAnchor.constraint(equalTo: keyWell.centerYAnchor),
      keys.centerXAnchor.constraint(equalTo: keyWell.centerXAnchor),
      clearButton.trailingAnchor.constraint(equalTo: keyWell.trailingAnchor, constant: -10),
      clearButton.centerYAnchor.constraint(equalTo: keyWell.centerYAnchor),
    ])
    if let current = GlobalShortcut.shared.current {
      showKeys(keyCode: current.keyCode, modifiers: current.modifiers)
    } else {
      showKeys(keyCode: nil, modifiers: 0)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var acceptsFirstResponder: Bool { true }
  @objc private func toggleListening() {
    if listening { cancelRecording() } else { beginRecording() }
  }

  @objc private func clearShortcut() {
    GlobalShortcut.shared.clear()
    showKeys(keyCode: nil, modifiers: 0)
    status.stringValue = "Shortcut cleared."
  }
  func cancelRecording() {
    guard listening else { return }
    stopListening()
    if let savedShortcut {
      showKeys(keyCode: savedShortcut.keyCode, modifiers: savedShortcut.modifiers)
    } else {
      showKeys(keyCode: nil, modifiers: 0)
    }
    status.stringValue = "Recording cancelled."
  }

  func refreshFromSavedShortcut() {
    guard !listening else { return }
    if let current = GlobalShortcut.shared.current {
      showKeys(keyCode: current.keyCode, modifiers: current.modifiers)
    } else {
      showKeys(keyCode: nil, modifiers: 0)
    }
    status.stringValue = "Click Record to change this shortcut."
  }

  private func beginRecording() {
    listening = true
    savedShortcut = GlobalShortcut.shared.current
    liveModifiers = 0
    keyWell.layer?.borderColor = NSColor.controlAccentColor.cgColor
    keyWell.layer?.borderWidth = 2
    keyWell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
    recordButton.title = "Cancel"
    status.stringValue = "Press modifiers, then a key. Esc cancels."
    showKeys(keyCode: nil, modifiers: 0)
    window?.makeFirstResponder(self)
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      guard let self else { return event }
      // NSEvent is not Sendable, so extract only scalar data before using the
      // main actor to update the recorder.
      let code = UInt32(event.keyCode)
      let flags = event.modifierFlags
      let carbon = Self.carbonModifiers(flags)
      let isFlagsChanged = event.type == .flagsChanged
      let isKeyDown = event.type == .keyDown
      let isEscape = isKeyDown && event.keyCode == 53
      let consume = MainActor.assumeIsolated {
        guard self.listening else { return false }
        if isEscape {
          self.cancelRecording()
          return true
        }
        if isFlagsChanged {
          self.liveModifiers = carbon
          self.showKeys(keyCode: nil, modifiers: carbon, recording: true)
          return true
        }
        guard isKeyDown else { return false }
        // Modifier keys arrive as flagsChanged events. Keep listening until a
        // non-modifier key completes the chord.
        guard ![54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code) else { return true }
        let combinedModifiers = carbon == 0 ? self.liveModifiers : carbon
        // A global shortcut without ⌘, ⌥ or ⌃ would swallow that key in every
        // app, so keep listening until the chord includes one.
        guard combinedModifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
          self.status.stringValue = "Include ⌘, ⌥ or ⌃. Esc cancels."
          return true
        }
        GlobalShortcut.shared.set(keyCode: code, modifiers: combinedModifiers)
        self.stopListening()
        self.showKeys(keyCode: code, modifiers: combinedModifiers)
        self.status.stringValue = "Shortcut saved."
        return true
      }
      return consume ? nil : event
    }
  }

  nonisolated private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = flags.intersection([.command, .control, .option, .shift])
    var carbon: UInt32 = 0
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.option) { carbon |= UInt32(optionKey) }
    if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
    return carbon
  }

  private func stopListening() {
    listening = false
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    recordButton.title = "Record Shortcut"
    keyWell.layer?.borderColor = NSColor.separatorColor.cgColor
    keyWell.layer?.borderWidth = 1
    keyWell.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
  }

  private func showKeys(keyCode: UInt32?, modifiers: UInt32, recording: Bool = false) {
    keys.setViews([], in: .leading)
    // Nothing to clear while recording or when no shortcut is saved.
    clearButton.isHidden = recording || listening || keyCode == nil
    let values: [(UInt32, String)] = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
    for (flag, title) in values where modifiers & flag != 0 { keys.addArrangedSubview(keyCap(title)) }
    if let keyCode {
      keys.addArrangedSubview(keyCap(GlobalShortcut.keyName(keyCode)))
    } else {
      let waiting = NSTextField(labelWithString: recording ? "Add a key" : "Not set")
      waiting.textColor = recording ? .secondaryLabelColor : .tertiaryLabelColor
      keys.addArrangedSubview(waiting)
    }
  }

  private func keyCap(_ title: String) -> NSView {
    let badge = NSView()
    badge.wantsLayer = true
    badge.layer?.cornerRadius = 5
    badge.layer?.borderWidth = 1
    badge.layer?.borderColor = NSColor.separatorColor.cgColor
    badge.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    badge.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
      badge.heightAnchor.constraint(equalToConstant: 27),
      badge.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 16),
    ])
    return badge
  }
}

@MainActor
final class ShortcutRecorderWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var recorder: ShortcutRecorderView?

  func show() {
    if let window {
      recorder?.refreshFromSavedShortcut()
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(recorder)
      return
    }

    let recorder = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 330, height: 158))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 330, height: 158),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = "Popup Shortcut"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = recorder
    self.recorder = recorder
    self.window = window
    window.center()
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(recorder)
  }

  func windowWillClose(_ notification: Notification) {
    recorder?.cancelRecording()
    window?.delegate = nil
    window = nil
    recorder = nil
  }
}
