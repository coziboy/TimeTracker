import Foundation

/// The outcome of finding a task from what a user typed.
public enum TaskResolution: Equatable, Sendable {
  case found(TrackedTask)
  case notFound
  /// More than one task fits; the caller should list them and ask again.
  case ambiguous([TrackedTask])
}

/// Finds the task `query` names, trying the most specific reading first:
/// 1. an exact id (`UUID` string, any case)
/// 2. an exact title, ignoring case and diacritics
/// 3. a unique title prefix, ignoring case and diacritics
/// 4. a unique title substring, like the popover's search
///
/// Several tasks with the same exact title are ambiguous rather than
/// silently picking one — the user should disambiguate by id.
public func resolveTask(_ query: String, in tasks: [TrackedTask]) -> TaskResolution {
  let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return .notFound }

  if let id = UUID(uuidString: trimmed), let task = tasks.first(where: { $0.id == id }) {
    return .found(task)
  }

  let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
  let exact = tasks.filter { $0.title.compare(trimmed, options: options) == .orderedSame }
  if let only = exact.first, exact.count == 1 { return .found(only) }
  if exact.count > 1 { return .ambiguous(exact) }

  let prefixed = tasks.filter {
    $0.title.range(of: trimmed, options: options.union(.anchored)) != nil
  }
  if let only = prefixed.first, prefixed.count == 1 { return .found(only) }
  if prefixed.count > 1 { return .ambiguous(prefixed) }

  let containing = tasks.filter { $0.title.range(of: trimmed, options: options) != nil }
  switch containing.count {
  case 0: return .notFound
  case 1: return .found(containing[0])
  default: return .ambiguous(containing)
  }
}
