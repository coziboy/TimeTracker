import AppKit

/// The keyboard actions the popover understands, mapped from raw key events.
///
/// Keeping this as a plain enum separate from the controller means the mapping
/// is readable in one place and can be reasoned about without AppKit noise.
enum KeyCommand {
  case moveDown
  case moveUp
  case toggleSelected
  case editSelected
  case deleteSelected
  case addTask
  case closePopover
  case quit

  /// Commands that still apply while the inline editor has the keyboard.
  /// Everything else passes through to the text fields.
  var worksWhileEditing: Bool {
    switch self {
    case .addTask, .quit: true
    default: false
    }
  }

  init?(event: NSEvent) {
    let command = event.modifierFlags.contains(.command)

    // Command shortcuts first — they win over the plain-key meanings below.
    if command {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "n": self = .addTask; return
      case "q": self = .quit; return
      default: return nil
      }
    }

    // Any other modifier combination is not ours.
    guard !event.modifierFlags.contains(.option),
      !event.modifierFlags.contains(.control)
    else { return nil }

    switch event.keyCode {
    case 125: self = .moveDown       // down arrow
    case 126: self = .moveUp         // up arrow
    case 49: self = .toggleSelected  // space
    case 36, 76: self = .editSelected  // return, keypad enter
    case 51, 117: self = .deleteSelected  // delete, forward delete
    case 53: self = .closePopover    // escape
    default: return nil
    }
  }
}
