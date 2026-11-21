.pragma library

function address(value) {
    return typeof value === "string" && /^(0x)?[0-9a-f]{1,16}$/i.test(value)
        ? value.replace(/^0x/i, "").toLowerCase() : "";
}

function windowInfo(window) {
    return {
        id: address(window?.address),
        title: String(window?.title ?? "").slice(0, 160),
        app: String(window?.lastIpcObject?.class ?? "").slice(0, 128),
        pid: Number(window?.lastIpcObject?.pid ?? 0),
        workspace: window?.workspace?.name ?? "",
        monitor: window?.monitor?.name ?? ""
    };
}

function capture(hyprland) {
    const window = windowInfo(hyprland.activeToplevel);
    return {
        window: window.id ? window : null,
        output: hyprland.focusedMonitor?.name ?? window.monitor
    };
}
