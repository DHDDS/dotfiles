import Quickshell
import "companion"

// The companion runs as its own app, started from the launcher or
// `desktop-companion`, so it never starts with the session or the shell.
ShellRoot {
    Companion {}
}
