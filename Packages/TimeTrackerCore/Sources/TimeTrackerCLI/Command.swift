import Foundation

/// One parsed `timetracker` invocation.
///
/// Task arguments are free text: every remaining word joins into one query,
/// so `timetracker start Client A` works without quotes. `rename` is the one
/// command with two free-text parts, so its task must be a single (quoted) word.
public enum Command: Equatable, Sendable {
  case list(json: Bool)
  case status(json: Bool)
  case add(title: String, start: Bool)
  case start(String)
  case stop(String)
  case toggle(String)
  case reset(String)
  case resetAll
  case rename(String, to: String)
  case set(String, duration: String)
  case delete(String)
  case completion(Shell)
  /// Hidden: prints task titles one per line for shell completion scripts.
  case completeTasks
  case help
}

public enum Shell: String, Sendable, CaseIterable {
  case zsh, bash
}

/// A command plus the options that apply to every command.
public struct Invocation: Equatable, Sendable {
  public var command: Command
  /// `--file <path>`: use this data file instead of the app's.
  public var dataFile: String?
}

/// A mistake in how the command was typed. Exits with status 2.
public struct UsageError: Error, Equatable, CustomStringConvertible {
  public let description: String
  init(_ description: String) { self.description = description }
}

/// Parses arguments (without the program name).
public func parseInvocation(_ arguments: [String]) throws(UsageError) -> Invocation {
  var dataFile: String?
  var words: [String] = []
  var flags: Set<String> = []

  var iterator = arguments.makeIterator()
  var literal = false
  while let argument = iterator.next() {
    if literal {
      words.append(argument)
    } else if argument == "--" {
      // Everything after `--` is text, so a title may start with a dash.
      literal = true
    } else if argument == "--file" {
      guard let path = iterator.next() else { throw UsageError("--file needs a path") }
      dataFile = path
    } else if argument.hasPrefix("--file=") {
      dataFile = String(argument.dropFirst("--file=".count))
    } else if argument.hasPrefix("-") && argument.count > 1 {
      flags.insert(argument)
    } else {
      words.append(argument)
    }
  }

  if flags.contains("-h") || flags.contains("--help") {
    return Invocation(command: .help, dataFile: dataFile)
  }
  guard let name = words.first else {
    // Bare `timetracker` shows where things stand, like the menu bar does.
    try rejectFlags(flags, allowed: [], for: "timetracker")
    return Invocation(command: .status(json: false), dataFile: dataFile)
  }
  let rest = Array(words.dropFirst())
  let text = rest.joined(separator: " ")

  func requireText(_ what: String) throws(UsageError) -> String {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw UsageError("\(name) needs \(what)")
    }
    return text
  }

  let command: Command
  switch name {
  case "list", "ls":
    try rejectFlags(flags, allowed: ["--json"], for: name)
    try rejectArguments(rest, for: name)
    command = .list(json: flags.contains("--json"))
  case "status":
    try rejectFlags(flags, allowed: ["--json"], for: name)
    try rejectArguments(rest, for: name)
    command = .status(json: flags.contains("--json"))
  case "add":
    try rejectFlags(flags, allowed: ["--start"], for: name)
    command = .add(title: try requireText("a title"), start: flags.contains("--start"))
  case "start":
    try rejectFlags(flags, allowed: [], for: name)
    command = .start(try requireText("a task"))
  case "stop":
    try rejectFlags(flags, allowed: [], for: name)
    command = .stop(try requireText("a task"))
  case "toggle":
    try rejectFlags(flags, allowed: [], for: name)
    command = .toggle(try requireText("a task"))
  case "reset":
    try rejectFlags(flags, allowed: ["--all"], for: name)
    if flags.contains("--all") {
      try rejectArguments(rest, for: "reset --all")
      command = .resetAll
    } else {
      command = .reset(try requireText("a task, or --all"))
    }
  case "rename":
    try rejectFlags(flags, allowed: [], for: name)
    guard rest.count >= 2 else { throw UsageError("rename needs a task and a new title") }
    command = .rename(rest[0], to: rest.dropFirst().joined(separator: " "))
  case "set":
    try rejectFlags(flags, allowed: [], for: name)
    // The duration is the last word, so the task can be several words.
    guard rest.count >= 2, let duration = rest.last else {
      throw UsageError("set needs a task and a duration")
    }
    command = .set(rest.dropLast().joined(separator: " "), duration: duration)
  case "delete", "rm":
    try rejectFlags(flags, allowed: [], for: name)
    command = .delete(try requireText("a task"))
  case "completion":
    try rejectFlags(flags, allowed: [], for: name)
    guard rest.count == 1, let shell = Shell(rawValue: rest[0]) else {
      throw UsageError("completion needs a shell: zsh or bash")
    }
    command = .completion(shell)
  case "__complete-tasks":
    command = .completeTasks
  case "help":
    command = .help
  default:
    throw UsageError("unknown command '\(name)'")
  }
  return Invocation(command: command, dataFile: dataFile)
}

private func rejectFlags(_ flags: Set<String>, allowed: Set<String>, for name: String)
  throws(UsageError)
{
  if let unknown = flags.subtracting(allowed).sorted().first {
    throw UsageError("\(name) does not take \(unknown)")
  }
}

private func rejectArguments(_ arguments: [String], for name: String) throws(UsageError) {
  if !arguments.isEmpty {
    throw UsageError("\(name) takes no arguments")
  }
}

public let helpText = """
  timetracker — control TimeTracker from the command line

  Usage:
    timetracker                         Total time and how many timers run
    timetracker list [--json]           Every task with its time
    timetracker status [--json]         Total time and how many timers run
    timetracker add <title> [--start]   Add a task, optionally starting it
    timetracker start <task>            Start a task's timer
    timetracker stop <task>             Stop a task's timer
    timetracker toggle <task>           Start or stop, like clicking the row
    timetracker reset <task>            Zero one task (running stays running)
    timetracker reset --all             Zero every task
    timetracker rename <task> <title>   Rename (quote a multi-word task)
    timetracker set <task> <duration>   Set time: 1:30:00, 90m, 1h30m, 5400
    timetracker delete <task>           Delete a task
    timetracker completion zsh|bash     Print a shell completion script

  <task> is an id, a title, or any unique part of a title, ignoring case.
  Words after the command join up, so quotes are optional: start Client A

  Options:
    --file <path>   Use this data file (default: the app's tasks.json,
                    or $TIMETRACKER_DATA when set)
    -h, --help      Show this help

  Shell completion (zsh): add to ~/.zshrc
    eval "$(timetracker completion zsh)"
  """
