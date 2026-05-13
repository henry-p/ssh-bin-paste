#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation

var defaultShortcut = "CMD+SHIFT+V"
if let index = CommandLine.arguments.firstIndex(of: "--default"), index + 1 < CommandLine.arguments.count {
    defaultShortcut = CommandLine.arguments[index + 1]
}

var selectedShortcut: String?
var exitStatus: Int32 = 0
var originalTerminal: termios?

func configureTerminalForRecording() {
    var term = termios()
    guard tcgetattr(STDIN_FILENO, &term) == 0 else {
        return
    }
    originalTerminal = term
    term.c_lflag &= ~tcflag_t(ECHO | ICANON)
    withUnsafeMutableBytes(of: &term.c_cc) { bytes in
        bytes[Int(VMIN)] = 0
        bytes[Int(VTIME)] = 0
    }
    tcflush(STDIN_FILENO, TCIFLUSH)
    tcsetattr(STDIN_FILENO, TCSANOW, &term)
}

func restoreTerminal() {
    tcflush(STDIN_FILENO, TCIFLUSH)
    if var original = originalTerminal {
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
    }
}

func keyName(for code: CGKeyCode) -> String? {
    switch Int(code) {
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_Space: return "Space"
    case kVK_Tab: return "Tab"
    case kVK_Return, kVK_ANSI_KeypadEnter: return "Return"
    case kVK_Escape: return "Escape"
    default: return nil
    }
}

func modifierNames(_ flags: CGEventFlags) -> [String] {
    var names: [String] = []
    if flags.contains(.maskCommand) {
        names.append("CMD")
    }
    if flags.contains(.maskControl) {
        names.append("CTRL")
    }
    if flags.contains(.maskAlternate) {
        names.append("OPTION")
    }
    if flags.contains(.maskShift) {
        names.append("SHIFT")
    }
    return names
}

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

func replaceStatusLine(_ text: String) {
    writeStderr("\r\u{001B}[2K\(text)")
}

func renderCurrent(_ flags: CGEventFlags) {
    let names = modifierNames(flags)
    if names.isEmpty {
        replaceStatusLine("New shortcut: ")
        writeStderr("(Press [Enter] to keep [\(defaultShortcut)])")
        writeStderr("\r\u{001B}[14C")
    } else {
        replaceStatusLine("New shortcut: \(names.joined(separator: "+"))")
    }
}

func finish(_ shortcut: String, status: Int32 = 0) {
    selectedShortcut = shortcut
    exitStatus = status
    CFRunLoopStop(CFRunLoopGetMain())
}

func shortcutString(flags: CGEventFlags, keyCode: CGKeyCode) -> String? {
    var names = modifierNames(flags)
    guard flags.contains(.maskCommand), let key = keyName(for: keyCode) else {
        return nil
    }
    names.append(key)
    return names.joined(separator: "+")
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .flagsChanged {
        renderCurrent(event.flags)
        return nil
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if Int(keyCode) == kVK_Escape {
        writeStderr("\nCanceled.\n")
        finish("", status: 130)
        return nil
    }
    if Int(keyCode) == kVK_Return || Int(keyCode) == kVK_ANSI_KeypadEnter {
        writeStderr("\nKeeping \(defaultShortcut).\n")
        finish(defaultShortcut)
        return nil
    }
    guard let shortcut = shortcutString(flags: event.flags, keyCode: keyCode) else {
        replaceStatusLine("New shortcut: Use CMD, optionally with other modifiers, plus a normal key.")
        return nil
    }
    writeStderr("\nRecorded \(shortcut).\n")
    finish(shortcut)
    return nil
}

writeStderr("Recording paste command...\n")
configureTerminalForRecording()
renderCurrent([])

let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(mask),
    callback: callback,
    userInfo: nil
) else {
    restoreTerminal()
    writeStderr("Could not record shortcut. Grant Accessibility permission to your terminal app, then try again.\n")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()

if let shortcut = selectedShortcut, exitStatus == 0 {
    print(shortcut)
}
restoreTerminal()
exit(exitStatus)
