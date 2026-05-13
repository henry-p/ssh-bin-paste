#!/usr/bin/env swift
import AppKit
import ApplicationServices
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
let pasteStateQueue = DispatchQueue(label: "ssh-bin-paste.state")
var pasteInFlight = false
var lastPasteStartedAt = Date(timeIntervalSince1970: 0)

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
    if pasteboard.string(forType: .fileURL) != nil {
        return true
    }
    return false
}

func log(_ message: String) {
    print(message)
    fflush(stdout)
}

func beginPasteOperation() -> Bool {
    pasteStateQueue.sync {
        let now = Date()
        if pasteInFlight || now.timeIntervalSince(lastPasteStartedAt) < 1.5 {
            return false
        }
        pasteInFlight = true
        lastPasteStartedAt = now
        return true
    }
}

func finishPasteOperation() {
    pasteStateQueue.sync {
        pasteInFlight = false
    }
}

func frontmostAppIsAllowed() -> Bool {
    guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
        return false
    }
    return config.allowlistedApps.contains(bundleId)
}

func sendRemotePasteSignal() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyCode = CGKeyCode(kVK_ANSI_RightBracket)
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    down?.flags = .maskControl
    up?.flags = .maskControl
    down?.post(tap: .cghidEventTap)
    usleep(30_000)
    up?.post(tap: .cghidEventTap)
    usleep(150_000)
}

func runPasteCommand() {
    sendRemotePasteSignal()
    DispatchQueue.global(qos: .userInitiated).async {
        defer {
            finishPasteOperation()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if let sshCommand = config.sshCommand {
            process.arguments = [config.command, "paste", "--ssh", sshCommand]
        } else {
            process.arguments = [config.command, "paste", "--host", config.host]
        }
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("failed to run paste command: \(error.localizedDescription)\n", stderr)
        }
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
    if status == noErr && hotKeyID.id == 1 {
        if clipboardHasSupportedPayload() {
            guard beginPasteOperation() else {
                log("Cmd+Shift+V duplicate ignored; paste is already running.")
                return noErr
            }
            log("Cmd+Shift+V detected; asking remote tmux for the focused pane.")
            runPasteCommand()
        } else {
            log("Cmd+Shift+V detected, but the clipboard has no supported payload.")
        }
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

let host = valueAfter("--host") ?? "example-remote"
let sshCommand = valueAfter("--ssh")
let apps = Set((valueAfter("--allowlisted-apps") ?? "").split(separator: ",").map(String.init))
config = DaemonConfig(command: command, host: host, sshCommand: sshCommand, hijackPaste: flagPresent("--hijack-paste"), allowlistedApps: apps)

if !AXIsProcessTrusted() {
    print("warning: Accessibility permission is not granted. macOS may block sending Ctrl+] into the focused SSH terminal.")
    print("grant Accessibility permission to your terminal app, then restart ssh-bin-paste up.")
}
installDedicatedShortcut()
if config.hijackPaste {
    installPasteHijackTap()
}
print("ssh-bin-paste up running. Cmd+Shift+V sends Ctrl+] to the focused tmux pane, then pastes supported clipboard payloads; paste hijack is \(config.hijackPaste ? "on" : "off").")
fflush(stdout)
_ = carbonRunApplicationEventLoop()
