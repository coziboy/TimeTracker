import Foundation
import TimeTrackerCLI

// Top-level code runs on the main actor, which TaskStore requires.
let result = runCLI(arguments: Array(CommandLine.arguments.dropFirst()))
if !result.output.isEmpty {
  print(result.output)
}
if !result.error.isEmpty {
  FileHandle.standardError.write(Data((result.error + "\n").utf8))
}
exit(result.exitCode)
