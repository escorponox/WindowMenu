# WindowMenu

A Windows-style taskbar living in the macOS menu bar, with one bar per monitor.

## Settings

**Global Settings**:
The settings used by every monitor that is not a Customized Monitor.
_Avoid_: Default settings, base settings

**Customized Monitor**:
A monitor that has its own complete copy of the settings and ignores the Global Settings. A monitor becomes customized the first time any of its settings is changed, and stops being customized when reset to use the Global Settings.
_Avoid_: Override, specific monitor, per-display settings

**App Preference**:
A setting about how the app behaves as a whole, not about how a bar looks. It is never part of the Global Settings and cannot be customized per monitor (e.g. launching at login, minimizing on click).
_Avoid_: Global setting

## Windows

**Minimize**:
Sending a single window to the Dock. The window stays in the taskbar of the monitor it was on, shown dimmed.
_Avoid_: Hide (hiding is an app-wide macOS action that affects all of an app's windows)
