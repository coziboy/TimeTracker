# TimeTracker

A native macOS menu bar time tracker. Several tasks, each with its own timer,
any number running at once; the menu bar shows the combined total.

A Swift/SwiftUI port of the [Omarchy time-tracker widget](https://github.com/smsanagustin/time-tracker).

## Building

Requires macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen                 # once
cd TimeTracker
xcodegen generate                     # writes TimeTracker.xcodeproj
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Debug build
```

### A note on Xcode 27 build noise

Running `xcodebuild` directly may print a long `DVTCoreDeviceCore` plug-in
load failure (`Symbol not found: ...CoreDevice...`). That is a fault in the
Xcode installation — a stale `CoreDevice.framework` in
`/Library/Developer/PrivateFrameworks/` disagreeing with the one inside
`Xcode.app` — and it concerns device discovery for iPhones and simulators.
Building a local Mac app does not use it, so the build succeeds regardless.
`install.sh` hides it; check for `** BUILD SUCCEEDED` if running xcodebuild
by hand.

### Running it without Xcode

`./install.sh` builds a Release copy, installs it to `/Applications` and
launches it. That is also what makes Launch at Login work — macOS will not
register a login item for an app running out of a build folder.

```bash
./install.sh
```

After that it behaves like any other app: Spotlight, Launchpad, or

```bash
open -a TimeTracker
```

To run a Debug build in place without installing:

```bash
open "$(xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker \
  -configuration Debug -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/TimeTracker.app"
```

Or open the project and press Run:

```bash
open TimeTracker.xcodeproj
```

`TimeTracker.xcodeproj` is generated and gitignored — after changing
`project.yml` or adding a source file, re-run `xcodegen generate`.

Run the logic tests with:

```bash
cd Packages/TimeTrackerCore && swift test
```

## Using it

The app has no Dock icon and no windows — it lives entirely in the menu bar as
a timer glyph plus the combined total, which turns red while anything is running.

Click the menu bar item to open the popover. Click a row to start or stop it.
Hovering a row (or selecting it with the keyboard) reveals four actions:
start/pause, reset, edit, delete. Reset zeroes a timer; a running task keeps
running from zero.

Editing a row replaces it with a title field and a duration field. The duration
accepts `HH:MM:SS`, `MM:SS`, plain seconds, or unit form like `1h30m`, `45m`,
`90s` — case-insensitive, spaces allowed. Input that cannot be parsed leaves the
stored time alone, so a typo never destroys tracked hours.

### Keyboard

| Key | Does |
|---|---|
| ↓ / ↑ | Select next / previous task |
| Space | Start or stop the selected task |
| R | Reset the selected task |
| Return | Edit the selected task |
| Delete | Delete the selected task |
| ⌘N | Add a task and start editing it |
| Esc | Close the popover (or cancel an edit) |
| ⌘Q | Quit |

While the editor is open the text fields take the keyboard: Return commits,
Esc cancels, and only ⌘N and ⌘Q still act as shortcuts.

## Launch at login

The gear menu has a Launch at Login toggle, backed by `SMAppService`.

`SMAppService` registers whichever bundle is running, so the login item points
at the copy you launched. Toggle it from `/Applications/TimeTracker.app` and
that is the copy macOS will start at login — turn it on from a DerivedData
build and macOS will faithfully launch the build folder instead.

If macOS asks for approval, the menu links to
System Settings › General › Login Items.

## Where the data lives

```
~/Library/Application Support/TimeTracker/tasks.json
```

Plain JSON, pretty-printed with sorted keys, rewritten atomically on every
change. Each task stores banked `seconds` separately from `startedAt` (epoch
milliseconds, `0` when stopped), so a timer left running keeps counting across
quit and relaunch. If the file is unreadable the app starts empty and leaves it
in place rather than overwriting it.

The app is not sandboxed, which is what keeps this path plain and keeps
`SMAppService` free of container issues.

## Layout

```
project.yml                     XcodeGen spec
Packages/TimeTrackerCore/       Pure logic, no UI, tested with `swift test`
  TrackedTask.swift             The model; normalized() repairs bad states
  DurationFormat.swift          format/parse durations
  Elapsed.swift                 elapsed and total seconds
  TaskStore.swift               Source of truth; saves on every mutation
  Persistence.swift             JSON file + in-memory test double
App/                            The macOS app
  TimeTrackerApp.swift          Entry point; declares no windows
  AppDelegate.swift             Builds the store, clock and status item
  StatusItemController.swift    Status item, popover, key monitor, title
  Clock.swift                   One shared 1s heartbeat
  KeyCommand.swift              NSEvent -> command mapping
  LaunchAtLogin.swift           SMAppService wrapper
  Views/                        SwiftUI: popover, rows, editor, footer
```

The model is `TrackedTask` rather than `Task` so it never collides with Swift
Concurrency's `Task`.

### Why AppKit for the shell

SwiftUI's `MenuBarExtra(.window)` cannot make its window key or close itself
programmatically, and a live SwiftUI `Text` label in the menu bar pinned the CPU
on macOS 26. So the status item and popover are `NSStatusItem`/`NSPopover`, the
menu bar title is a plain `NSAttributedString` rewritten only when it actually
changes, and keyboard handling is one local `NSEvent` monitor installed while
the popover is open. Everything visible is still SwiftUI.

The one-second tick runs only while a timer is going or the popover is open, so
the app uses no measurable CPU at rest.
