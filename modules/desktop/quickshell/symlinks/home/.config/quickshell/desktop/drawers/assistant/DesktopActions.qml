pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../audio"
import "../events"
import "../notifications"
import "../weather"
import "../../ui"
import "../../ui/DesktopContext.js" as Context
import "../../launcher/Search.js" as Search

Scope {
    id: root
    property var openDrawer: null
    property bool publishPresence: false
    property var compositor: Hyprland
    property var reminders: ReminderService
    property var calendar: CalendarService
    readonly property string presence: JSON.stringify({
        quiet: NotificationCenter.state.paused,
        recording: AudioService.otherRecording,
        timers: root.reminders.entries.filter(row => row.kind === "timer" || row.kind === "pomodoro")
    })
    onPresenceChanged: savePresence()
    Component.onCompleted: savePresence()

    function savePresence(): void {
        if (publishPresence && presenceFile.path)
            presenceFile.setText(presence);
    }
    FileView {
        id: presenceFile
        path: {
            const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
            return root.publishPresence && runtime.startsWith("/") ? runtime + "/desktop-companion-state.json" : "";
        }
        printErrors: false
    }

    function open(key, origin): var {
        return openDrawer?.(key, typeof origin?.output === "string" ? origin.output : "") ? {
            opened: true
        } : {
            error: qsTr("The desktop drawer is unavailable.")
        };
    }

    function timer(args, origin): var {
        if (args.action === "open")
            return open("weather", origin);
        if (!reminders.restored)
            return {
                error: qsTr("Timers are still loading.")
            };
        // Catch up on a deadline before resolving the requested operation.
        reminders.tick();
        const rows = reminders.entries.filter(row => ["timer", "pomodoro"].includes(row.kind));
        if (args.action === "list")
            return {
                timers: rows.map(row => Object.assign({}, row, {
                        remaining_seconds: Math.max(0, Math.ceil((row.deadline - reminders.now) / 1000))
                    }))
            };
        if (args.action === "timer") {
            if (!Number.isInteger(args.seconds) || (args.label !== undefined && typeof args.label !== "string"))
                return {
                    error: qsTr("Give a duration in seconds and an optional timer name.")
                };
            const id = reminders.addTimer(args.seconds, args.label ?? "");
            return id ? {
                started: true,
                id,
                seconds: args.seconds,
                label: args.label ?? ""
            } : {
                error: qsTr("A timer can run from one second to one day. Up to 100 reminders may be active.")
            };
        }
        if (args.action === "focus") {
            if (args.repeat !== undefined && typeof args.repeat !== "boolean")
                return {
                    error: qsTr("Set repeat to true or false.")
                };
            if (!reminders.addPomodoro(args.minutes ?? 25, args.break_minutes ?? 5, args.repeat === true))
                return {
                    error: qsTr("A focus session is already running, or the duration is invalid.")
                };
            return {
                started: true,
                focus: reminders.entries.find(row => row.kind === "pomodoro")
            };
        }
        if (args.action === "stop") {
            const label = typeof args.label === "string" ? args.label.trim().toLowerCase() : "";
            const matches = rows.filter(row => Number.isInteger(args.id) ? row.id === args.id : args.kind === "focus" ? row.kind === "pomodoro" : row.kind === "timer" && (!label || row.message.toLowerCase() === label));
            if (matches.length !== 1)
                return {
                    error: matches.length ? qsTr("Which timer should I stop?") : qsTr("That timer is not running."),
                    timers: matches
                };
            reminders.stop(matches[0].id);
            return {
                stopped: true,
                timer: matches[0]
            };
        }
        return {
            error: qsTr("Unknown timer action.")
        };
    }

    function agenda(args, origin): var {
        if (args.action === "open")
            return open("events", origin);
        if (args.action !== "today")
            return {
                error: qsTr("Unknown calendar action.")
            };
        if (!calendar.state.eventsReady)
            return {
                error: qsTr("Today's calendar is unavailable."),
                status: calendar.state.state
            };
        const today = calendar.clock();
        const events = calendar.eventsOn(today);
        return {
            date: Qt.formatDate(today, "yyyy-MM-dd"),
            local_time: Qt.formatTime(today, "HH:mm"),
            cached: calendar.state.stale === true,
            truncated: events.length > 20,
            events: events.slice(0, 20).map(event => ({
                        title: String(event.summary ?? "").slice(0, 180),
                        location: String(event.location ?? "").slice(0, 160),
                        all_day: !!event.all_day,
                        start: event.all_day ? event.date : Qt.formatDateTime(new Date(event.start), "yyyy-MM-dd HH:mm"),
                        end: event.all_day ? event.last_date : Qt.formatDateTime(new Date(event.end), "yyyy-MM-dd HH:mm")
                    }))
        };
    }

    function windowAction(args, origin): var {
        const windows = compositor.toplevels.values.map(Context.windowInfo).filter(row => row.id);
        const outputs = compositor.monitors.values.map(monitor => ({
                    id: monitor.id,
                    name: monitor.name,
                    description: monitor.description ?? ""
                }));
        const active = Context.address(compositor.activeToplevel?.address);
        if (args.action === "list")
            return {
                windows: windows.slice(0, 30),
                outputs,
                current: origin?.window ?? null
            };
        if (args.action === "observe")
            return {
                active,
                window: windows.find(row => row.id === Context.address(args.id)) ?? null
            };
        if (!compositor.usingLua || !["focus", "move"].includes(args.action))
            return {
                error: qsTr("Window actions require Hyprland Lua.")
            };

        const query = typeof args.target === "string" ? args.target.trim().toLowerCase() : "";
        let matches;
        if (query === "current") {
            const saved = origin?.window;
            matches = windows.filter(row => saved && row.id === Context.address(saved.id) && row.pid === saved.pid && row.app === saved.app);
        } else {
            const id = Context.address(query);
            const exactId = id ? windows.find(row => row.id === id) : null;
            const exact = windows.filter(row => query && [row.title, row.app].some(value => value.toLowerCase() === query));
            matches = exactId ? [exactId] : exact.length ? exact : windows.filter(row => query && [row.title, row.app].some(value => value.toLowerCase().includes(query)));
        }
        if (matches.length !== 1)
            return {
                error: matches.length ? qsTr("Several windows match. Ask which one.") : qsTr("The requested window is no longer available."),
                candidates: matches.slice(0, 12)
            };
        const target = matches[0];
        const selector = '"address:0x' + target.id + '"';
        if (args.action === "focus") {
            if (active !== target.id)
                compositor.dispatch('function() hl.dispatch(hl.dsp.focus({window = ' + selector + '})) hl.dispatch(hl.dsp.layout("center")) hl.dispatch(hl.dsp.event("desktop-layout-changed")) end');
            return {
                requested: true,
                id: target.id
            };
        }
        const name = typeof args.monitor === "string" ? args.monitor.trim().toLowerCase() : "";
        const monitors = outputs.filter(output => name === "other" ? output.name !== target.monitor : name && [output.name, output.description].some(value => value.toLowerCase() === name));
        if (monitors.length !== 1 || !Number.isInteger(monitors[0].id) || monitors[0].id < 0)
            return {
                error: qsTr("Choose a specific connected monitor."),
                outputs
            };
        const output = monitors[0];
        if (output.name !== target.monitor)
            compositor.dispatch('function() hl.dispatch(hl.dsp.window.move({window = ' + selector + ', monitor = "' + output.id + '", follow = false})) hl.dispatch(hl.dsp.event("desktop-layout-changed")) end');
        return {
            requested: true,
            id: target.id,
            monitor: output.name
        };
    }

    function app(args): var {
        const name = typeof args.name === "string" ? args.name.trim() : "";
        if (!name)
            return {
                error: qsTr("Which app should I open?")
            };
        const rows = DesktopEntries.applications.values.filter(row => !row.noDisplay);
        const exact = rows.filter(row => row.name.toLowerCase() === name.toLowerCase() || row.id.toLowerCase() === name.toLowerCase());
        const matches = exact.length ? exact : Search.matches(Search.catalogue(rows), name);
        if (matches.length !== 1)
            return {
                error: matches.length ? qsTr("Several apps match. Ask which one.") : qsTr("No installed app matches."),
                candidates: matches.slice(0, 8).map(row => ({
                            id: row.id,
                            name: row.name
                        }))
            };
        return {
            id: matches[0].id,
            name: matches[0].name
        };
    }

    function request(tool, args, origin): var {
        if (!args || typeof args !== "object" || Array.isArray(args))
            return {
                error: qsTr("Invalid desktop arguments.")
            };
        switch (tool) {
        case "timer":
            return timer(args, origin);
        case "window":
            return windowAction(args, origin);
        case "agenda":
            return agenda(args, origin);
        case "open_app":
            return app(args);
        }
        return {
            error: qsTr("Unknown desktop action.")
        };
    }
}
