#!/usr/bin/env swift
import AppKit
import Carbon
import Foundation

@_silgen_name("RunApplicationEventLoop")
func carbonRunApplicationEventLoop() -> OSStatus

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

func isPlainPaste(_ event: CGEvent) -> Bool {
    let flags = event.flags
    return event.getIntegerValueField(.keyboardEventKeycode) == 9
        && (flags.contains(.maskCommand) || flags.contains(.maskControl))
        && !flags.contains(.maskShift)
        && !flags.contains(.maskAlternate)
}

func fourCharCode(_ value: String) -> OSType {
    var result: OSType = 0
    for scalar in value.unicodeScalars {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}

let hotKeyCallback: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr && hotKeyID.id == 1 && clipboardHasSupportedPayload() {
        runPasteCommand()
    }
    return noErr
}

func installDedicatedShortcut() {
    var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: OSType(kEventHotKeyPressed)
    )
    let installStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        hotKeyCallback,
        1,
        &eventType,
        nil,
        nil
    )
    guard installStatus == noErr else {
        fputs("Could not install hotkey handler: \(installStatus)\n", stderr)
        exit(1)
    }

    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: fourCharCode("SBP1"), id: 1)
    let registerStatus = RegisterEventHotKey(
        UInt32(kVK_ANSI_V),
        UInt32(cmdKey | shiftKey),
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &hotKeyRef
    )
    guard registerStatus == noErr else {
        fputs("Could not register Cmd+Shift+V hotkey: \(registerStatus)\n", stderr)
        exit(1)
    }
}

let hijackCallback: CGEventTapCallBack = { _, type, event, _ in
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let hijackedPaste = config.hijackPaste && frontmostAppIsAllowed() && isPlainPaste(event)
    if hijackedPaste && clipboardHasSupportedPayload() {
        runPasteCommand()
        return nil
    }

    return Unmanaged.passUnretained(event)
}

func installPasteHijackTap() {
    let mask = (1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: hijackCallback,
        userInfo: nil
    ) else {
        fputs("Could not create event tap. Grant Accessibility permission to your terminal app.\n", stderr)
        exit(1)
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}

guard let command = valueAfter("--command") else {
    fputs("missing --command\n", stderr)
    exit(2)
}

let host = valueAfter("--host") ?? "example-vps"
let sshCommand = valueAfter("--ssh")
let apps = Set((valueAfter("--allowlisted-apps") ?? "").split(separator: ",").map(String.init))
config = DaemonConfig(command: command, host: host, sshCommand: sshCommand, hijackPaste: flagPresent("--hijack-paste"), allowlistedApps: apps)

installDedicatedShortcut()
if config.hijackPaste {
    installPasteHijackTap()
}
print("ssh-bin-paste up running. Cmd+Shift+V pastes supported clipboard payloads; paste hijack is \(config.hijackPaste ? "on" : "off").")
fflush(stdout)
_ = carbonRunApplicationEventLoop()
