import Foundation

/// Renders a second count as `HH:MM:SS`.
///
/// Hours deliberately are *not* capped at 24 — a task tracked across several
/// days shows `48:10:05`, matching the original Omarchy widget.
public func formatDuration(_ totalSeconds: Int) -> String {
  let clamped = max(0, totalSeconds)
  let hours = clamped / 3600
  let minutes = (clamped % 3600) / 60
  let seconds = clamped % 60
  return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

/// Parses user-typed durations into seconds, or `nil` when the text makes no sense.
///
/// Two shapes are accepted, both case-insensitive and tolerant of spaces:
/// - clock form: `HH:MM:SS`, `MM:SS`, or bare `SS`
/// - unit form: any combination of `1h`, `30m`, `90s` (e.g. `1h30m`)
///
/// Callers treat `nil` as "leave the stored time alone".
public func parseDuration(_ text: String) -> Int? {
  let trimmed = text.replacingOccurrences(of: " ", with: "").lowercased()
  guard !trimmed.isEmpty else { return nil }

  if trimmed.contains(":") {
    return parseClockForm(trimmed)
  }
  // A string of pure digits is a bare second count.
  if trimmed.allSatisfy(\.isNumber) {
    return Int(trimmed)
  }
  return parseUnitForm(trimmed)
}

/// `HH:MM:SS`, `MM:SS`. More than three components, or any non-numeric
/// component, is rejected.
private func parseClockForm(_ text: String) -> Int? {
  let parts = text.split(separator: ":", omittingEmptySubsequences: false)
  guard (2...3).contains(parts.count) else { return nil }

  var values: [Int] = []
  for part in parts {
    guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
    values.append(value)
  }

  // Pad to [hours, minutes, seconds] so `MM:SS` and `HH:MM:SS` share one path.
  while values.count < 3 { values.insert(0, at: 0) }
  return values[0] * 3600 + values[1] * 60 + values[2]
}

/// `1h30m`, `45m`, `90s`, `2h`, `1h30m15s`. Every character must belong to a
/// number/unit pair, so a stray `1h2x` fails rather than silently parsing `1h`.
private func parseUnitForm(_ text: String) -> Int? {
  var total = 0
  var digits = ""
  var sawAnyUnit = false

  for character in text {
    if character.isNumber {
      digits.append(character)
      continue
    }
    // A unit must follow at least one digit.
    guard let value = Int(digits) else { return nil }
    switch character {
    case "h": total += value * 3600
    case "m": total += value * 60
    case "s": total += value
    default: return nil
    }
    digits = ""
    sawAnyUnit = true
  }

  // Trailing digits with no unit (e.g. `1h30`) are ambiguous — reject them.
  guard digits.isEmpty, sawAnyUnit else { return nil }
  return total
}
