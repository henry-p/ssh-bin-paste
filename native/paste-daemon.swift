#!/usr/bin/env swift
import AppKit
import Foundation

struct DaemonConfig {
    let command: String
    let host: String
    let sshCommand: String?
    let hijackPaste: Bool
    let allowlistedApps: Set<String>
}

var config: DaemonConfig!

func valueAfter(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

func flagPresent(_ name: String) -> Bool {
    CommandLine.arguments.contains(name)
}

func clipboardHasSupportedPayload() -> Bool {
    let pasteboard = NSPasteboard.general
    if pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) != nil {
        return true
    }
    if pasteboard.data(forType: NSPasteboard.PasteboardType("public.tiff")) != nil {
        return true
    }
    if NSImage(pasteboard: pasteboard) != nil {
        return true
    }
    return false
}

func frontmostAppIsAllowed() -> Bool {
    guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        return false
    }
    return config.allowlistedApps.contains(bundleId)
}

func runPasteCommand() {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if let sshCommand = config.sshCommand {
            process.arguments = [config.command, "paste", "--ssh", sshCommand]
        } else {
            process.arguments = [config.command, "paste", "--host", config.host]
        }
        try? process.run()
    }
}

func isCommandShiftV(_ event: CGEvent) -> Bool {
    let flags = event.flags
    return event.getIntegerValueField(.keyboardEventKeycode) == 9
        && flags.contains(.maskCommand)
        && flags.contains(.maskShift)
}

func isPlainPaste(_ event: CGEvent) -> Bool {
    let flags = event.flags
    return event.getIntegerValueField(.keyboardEventKeycode) == 9
        && (flags.contains(.maskCommand) || flags.contains(.maskControl))
        && !flags.contains(.maskShift)
        && !flags.contains(.maskAlternate)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let dedicatedShortcut = isCommandShiftV(event)
    let hijackedPaste = config.hijackPaste && frontmostAppIsAllowed() && isPlainPaste(event)
    if (dedicatedShortcut || hijackedPaste) && clipboardHasSupportedPayload() {
        runPasteCommand()
        return nil
    }

    return Unmanaged.passUnretained(event)
}

guard let command = valueAfter("--command") else {
    fputs("missing --command\n", stderr)
    exit(2)
}

let host = valueAfter("--host") ?? "example-vps"
let sshCommand = valueAfter("--ssh")
let apps = Set((valueAfter("--allowlisted-apps") ?? "").split(separator: ",").map(String.init))
config = DaemonConfig(command: command, host: host, sshCommand: sshCommand, hijackPaste: flagPresent("--hijack-paste"), allowlistedApps: apps)

let mask = (1 << CGEventType.keyDown.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(mask),
    callback: callback,
    userInfo: nil
) else {
    fputs("Could not create event tap. Grant Accessibility permission to your terminal app.\n", stderr)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("ssh-bin-paste daemon running. Cmd+Shift+V pastes supported clipboard payloads; paste hijack is \(config.hijackPaste ? "on" : "off").")
CFRunLoopRun()
