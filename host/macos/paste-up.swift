#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon
import Foundation

@_silgen_name("RunApplicationEventLoop")
func carbonRunApplicationEventLoop() -> OSStatus

struct DaemonConfig {
    let command: String
    let shortcut: Shortcut
    let hijackPaste: Bool
    let allowlistedApps: Set<String>
}

struct Shortcut {
    let display: String
    let keyCode: UInt32
    let carbonModifiers: UInt32
}

var config: DaemonConfig!
let pasteStateQueue = DispatchQueue(label: "ssh-bin-paste.state")
var pasteInFlight = false

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
        if pasteInFlight {
            return false
        }
        pasteInFlight = true
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

func remoteArguments(commandName: String, token: String) -> [String] {
    return [config.command, commandName, "--request-token", token]
}

func runCommandSync(_ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func runPasteCommand() {
    DispatchQueue.global(qos: .userInitiated).async {
        let token = UUID().uuidString.lowercased()
        do {
            let armStatus = try runCommandSync(remoteArguments(commandName: "arm", token: token))
            guard armStatus == 0 else {
                finishPasteOperation()
                return
            }
        } catch {
            finishPasteOperation()
            fputs("failed to arm remote paste request: \(error.localizedDescription)\n", stderr)
            return
        }

        sendRemotePasteSignal()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = remoteArguments(commandName: "paste", token: token)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.terminationHandler = { _ in
            finishPasteOperation()
        }
        do {
            try process.run()
        } catch {
            finishPasteOperation()
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

func keyCode(for key: String) -> UInt32? {
    switch key.uppercased() {
    case "A": return UInt32(kVK_ANSI_A)
    case "B": return UInt32(kVK_ANSI_B)
    case "C": return UInt32(kVK_ANSI_C)
    case "D": return UInt32(kVK_ANSI_D)
    case "E": return UInt32(kVK_ANSI_E)
    case "F": return UInt32(kVK_ANSI_F)
    case "G": return UInt32(kVK_ANSI_G)
    case "H": return UInt32(kVK_ANSI_H)
    case "I": return UInt32(kVK_ANSI_I)
    case "J": return UInt32(kVK_ANSI_J)
    case "K": return UInt32(kVK_ANSI_K)
    case "L": return UInt32(kVK_ANSI_L)
    case "M": return UInt32(kVK_ANSI_M)
    case "N": return UInt32(kVK_ANSI_N)
    case "O": return UInt32(kVK_ANSI_O)
    case "P": return UInt32(kVK_ANSI_P)
    case "Q": return UInt32(kVK_ANSI_Q)
    case "R": return UInt32(kVK_ANSI_R)
    case "S": return UInt32(kVK_ANSI_S)
    case "T": return UInt32(kVK_ANSI_T)
    case "U": return UInt32(kVK_ANSI_U)
    case "V": return UInt32(kVK_ANSI_V)
    case "W": return UInt32(kVK_ANSI_W)
    case "X": return UInt32(kVK_ANSI_X)
    case "Y": return UInt32(kVK_ANSI_Y)
    case "Z": return UInt32(kVK_ANSI_Z)
    case "0": return UInt32(kVK_ANSI_0)
    case "1": return UInt32(kVK_ANSI_1)
    case "2": return UInt32(kVK_ANSI_2)
    case "3": return UInt32(kVK_ANSI_3)
    case "4": return UInt32(kVK_ANSI_4)
    case "5": return UInt32(kVK_ANSI_5)
    case "6": return UInt32(kVK_ANSI_6)
    case "7": return UInt32(kVK_ANSI_7)
    case "8": return UInt32(kVK_ANSI_8)
    case "9": return UInt32(kVK_ANSI_9)
    case "SPACE": return UInt32(kVK_Space)
    case "TAB": return UInt32(kVK_Tab)
    case "RETURN", "ENTER": return UInt32(kVK_Return)
    case "ESC", "ESCAPE": return UInt32(kVK_Escape)
    default: return nil
    }
}

func parseShortcut(_ value: String) -> Shortcut? {
    let rawParts = value.split(separator: "+").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard rawParts.count >= 2, let key = rawParts.last, let keyCode = keyCode(for: key) else {
        return nil
    }

    var carbonModifiers: UInt32 = 0
    var displayParts: [String] = []
    for part in rawParts.dropLast() {
        switch part.lowercased() {
        case "cmd", "command":
            carbonModifiers |= UInt32(cmdKey)
            displayParts.append("CMD")
        case "shift":
            carbonModifiers |= UInt32(shiftKey)
            displayParts.append("SHIFT")
        case "option", "opt", "alt":
            carbonModifiers |= UInt32(optionKey)
            displayParts.append("OPTION")
        case "ctrl", "control":
            carbonModifiers |= UInt32(controlKey)
            displayParts.append("CTRL")
        default:
            return nil
        }
    }
    guard carbonModifiers & UInt32(cmdKey) != 0 else {
        return nil
    }

    displayParts.append(key.uppercased())
    return Shortcut(display: displayParts.joined(separator: "+"), keyCode: keyCode, carbonModifiers: carbonModifiers)
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
                log("\(config.shortcut.display) duplicate ignored; paste is already running.")
                return noErr
            }
            log("\(config.shortcut.display) detected; asking remote tmux for the focused pane.")
            runPasteCommand()
        } else {
            log("\(config.shortcut.display) detected, but the clipboard has no supported payload.")
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
        config.shortcut.keyCode,
        config.shortcut.carbonModifiers,
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &hotKeyRef
    )
    guard registerStatus == noErr else {
        fputs("Could not register \(config.shortcut.display) hotkey: \(registerStatus)\n", stderr)
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

let shortcutText = valueAfter("--shortcut") ?? "Cmd+Shift+V"
guard let shortcut = parseShortcut(shortcutText) else {
    fputs("Invalid paste shortcut: \(shortcutText)\n", stderr)
    exit(2)
}
let apps = Set((valueAfter("--allowlisted-apps") ?? "").split(separator: ",").map(String.init))
config = DaemonConfig(command: command, shortcut: shortcut, hijackPaste: flagPresent("--hijack-paste"), allowlistedApps: apps)

if !AXIsProcessTrusted() {
    print("warning: Accessibility permission is not granted. macOS may block sending Ctrl+] into the focused SSH terminal.")
    print("grant Accessibility permission to your terminal app, then restart ssh-bin-paste up.")
}
installDedicatedShortcut()
if config.hijackPaste {
    installPasteHijackTap()
}
_ = carbonRunApplicationEventLoop()
