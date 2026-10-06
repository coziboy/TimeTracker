import Testing
@testable import TimeTrackerCLI

private func parse(_ arguments: String...) throws -> Invocation {
  try parseInvocation(arguments)
}

@Suite("parseInvocation")
struct CommandParsingTests {
  @Test("no arguments shows status")
  func bare() throws {
    #expect(try parse().command == .status(json: false))
  }

  @Test("task words join so quotes are optional")
  func joinsWords() throws {
    #expect(try parse("start", "Client", "A").command == .start("Client A"))
  }

  @Test("flags may appear anywhere")
  func flagsAnywhere() throws {
    #expect(try parse("--json", "list").command == .list(json: true))
    #expect(try parse("add", "Write", "--start", "docs").command == .add(title: "Write docs", start: true))
  }

  @Test("--file is taken in both spellings")
  func fileOption() throws {
    #expect(try parse("--file", "/tmp/t.json", "list").dataFile == "/tmp/t.json")
    #expect(try parse("list", "--file=/tmp/t.json").dataFile == "/tmp/t.json")
  }

  @Test("after -- a word starting with a dash is text")
  func doubleDash() throws {
    #expect(try parse("add", "--", "-draft").command == .add(title: "-draft", start: false))
  }

  @Test("reset takes a task or --all")
  func reset() throws {
    #expect(try parse("reset", "A").command == .reset("A"))
    #expect(try parse("reset", "--all").command == .resetAll)
    #expect(throws: UsageError.self) { try parse("reset", "--all", "A") }
    #expect(throws: UsageError.self) { try parse("reset") }
  }

  @Test("rename's first word is the task, the rest is the title")
  func rename() throws {
    #expect(try parse("rename", "Client A", "Client", "B").command == .rename("Client A", to: "Client B"))
    #expect(throws: UsageError.self) { try parse("rename", "A") }
  }

  @Test("set's last word is the duration, the rest is the task")
  func set() throws {
    #expect(try parse("set", "Client", "A", "1h30m").command == .set("Client A", duration: "1h30m"))
    #expect(throws: UsageError.self) { try parse("set", "1h") }
  }

  @Test("aliases ls and rm work")
  func aliases() throws {
    #expect(try parse("ls").command == .list(json: false))
    #expect(try parse("rm", "A").command == .delete("A"))
  }

  @Test("help in any form")
  func help() throws {
    #expect(try parse("help").command == .help)
    #expect(try parse("-h").command == .help)
    #expect(try parse("start", "--help").command == .help)
  }

  @Test("completion needs a known shell")
  func completion() throws {
    #expect(try parse("completion", "zsh").command == .completion(.zsh))
    #expect(throws: UsageError.self) { try parse("completion", "fish") }
  }

  @Test("mistakes are usage errors")
  func mistakes() {
    #expect(throws: UsageError("unknown command 'go'")) { try parse("go") }
    #expect(throws: UsageError("start does not take --json")) { try parse("start", "A", "--json") }
    #expect(throws: UsageError("start needs a task")) { try parse("start") }
    #expect(throws: UsageError("list takes no arguments")) { try parse("list", "A") }
    #expect(throws: UsageError("--file needs a path")) { try parse("list", "--file") }
  }
}
