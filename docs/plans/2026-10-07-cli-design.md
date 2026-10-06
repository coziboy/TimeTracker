# `timetracker` CLI design

A command-line alternative to the popover, bundled inside `TimeTracker.app`.

## Sync model

The CLI reads and writes `tasks.json` directly through `TimeTrackerCore`
(atomic writes). The app watches the data directory and reloads on change, so
the CLI works whether or not the app is running.

Known limitation: a UI action within milliseconds of a CLI write can lose one
of them, and committing an inline edit overwrites CLI changes to that same task.

## Core (`TimeTrackerCore`)

- `JSONFilePersistence.loadIfReadable() -> [TrackedTask]?` — `[]` when missing,
  `nil` when undecodable. Neither the CLI nor reload writes over an unreadable file.
- `TaskStore.add(title:start:) -> UUID`, `rename(_:to:)`,
  `setDuration(_:seconds:)` (running stays running), `reload()` (keeps
  selection/editor when the task still exists; cancels an edit of a deleted task).
- `resolveTask(_:in:)` — exact id, exact case-insensitive title, unique title
  prefix; ambiguity reports the candidates.

## CLI

`TimeTrackerCLI` library (parse + run, returns output and exit code, tested)
and a thin `timetracker` executable.

    timetracker list [--json]
    timetracker status [--json]
    timetracker add <title> [--start]
    timetracker start|stop|toggle <task>
    timetracker reset <task> | --all
    timetracker rename <task> <title>
    timetracker set <task> <duration>
    timetracker delete <task>

`--file <path>` or `TIMETRACKER_DATA` overrides the data file. Unreadable data
file: exit 1, file untouched.

## App

- `TasksFileWatcher` watches the `TimeTracker/` directory (atomic saves replace
  the file inode), debounces ~100 ms, calls `store.reload()` and
  `updateClockPolicy()`.
- Gear menu "Install Command Line Tool…" symlinks `~/.local/bin/timetracker` to
  the bundled binary and reports the result.

## Bundling

XcodeGen `tool` target `timetracker`, copied to
`TimeTracker.app/Contents/Helpers/` (not `MacOS/`: `timetracker` and
`TimeTracker` collide on case-insensitive volumes). `install.sh` links it into
`~/.local/bin` (or `$TIMETRACKER_BIN_DIR`) and warns when that is not on PATH.
