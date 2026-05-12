#!/usr/bin/env swift
import AppKit
import Foundation

struct CaptureResult: Codable {
    let path: String
    let mimeType: String
    let sizeBytes: Int
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func argumentValue(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

func pngData(from image: NSImage) -> Data? {
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
    else {
        return nil
    }
    return rep.representation(using: .png, properties: [:])
}

func imageFromFileURL(_ urlString: String) -> NSImage? {
    guard let url = URL(string: urlString) else {
        return nil
    }
    return NSImage(contentsOf: url)
}

let outputPath = argumentValue("--output")
    ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("ssh-bin-paste-\(UUID().uuidString).png")

let pasteboard = NSPasteboard.general
let pngType = NSPasteboard.PasteboardType("public.png")
let tiffType = NSPasteboard.PasteboardType("public.tiff")

let data: Data?
if let png = pasteboard.data(forType: pngType) {
    data = png
} else if let tiff = pasteboard.data(forType: tiffType), let rep = NSBitmapImageRep(data: tiff) {
    data = rep.representation(using: .png, properties: [:])
} else if let file = pasteboard.string(forType: .fileURL), let image = imageFromFileURL(file) {
    data = pngData(from: image)
} else if let image = NSImage(pasteboard: pasteboard) {
    data = pngData(from: image)
} else {
    data = nil
}

guard let png = data else {
    fail("No image found on the clipboard")
}

let url = URL(fileURLWithPath: outputPath)
do {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url, options: .atomic)
    let result = CaptureResult(path: outputPath, mimeType: "image/png", sizeBytes: png.count)
    let encoded = try JSONEncoder().encode(result)
    FileHandle.standardOutput.write(encoded)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fail("Failed to write clipboard image: \(error.localizedDescription)")
}

