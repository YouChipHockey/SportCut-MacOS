//
//  CameraLogger.swift
//  Youchip-Stat
//

import Foundation
import AVFoundation

/// Persistent logger for live camera/capture-card diagnostics.
/// Writes to `~/Library/Application Support/YouChip-Stat/cameraLogs.txt`.
/// Each app launch starts a new SECTION; each live-markup session starts a new SESSION block.
final class CameraLogger {

    static let shared = CameraLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.youchip.cameraLogger", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YouChip-Stat")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fileURL = dir.appendingPathComponent("cameraLogs.txt")

        let header = """

        ╔══════════════════════════════════════════════════════════════════╗
        ║  APP LAUNCH — \(dateFormatter.string(from: Date()))
        ║  App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
        ║  macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ║  Machine: \(Self.machineModel())
        ╚══════════════════════════════════════════════════════════════════╝

        """
        appendRaw(header)
    }

    // MARK: - Public API

    func startSession(deviceName: String, deviceType: String, deviceUID: String, formatDescription: String) {
        let divider = """

        ┌──────────────────────────────────────────────────────────────────┐
        │  LIVE SESSION START — \(timestamp())
        │  Device: \(deviceName)
        │  Type: \(deviceType)
        │  UID: \(deviceUID)
        │  Format: \(formatDescription)
        └──────────────────────────────────────────────────────────────────┘

        """
        appendRaw(divider)
    }

    func endSession(reason: String, duration: Double, segmentCount: Int) {
        let divider = """

        ┌──────────────────────────────────────────────────────────────────┐
        │  LIVE SESSION END — \(timestamp())
        │  Reason: \(reason)
        │  Duration: \(String(format: "%.2f", duration))s
        │  Segments: \(segmentCount)
        └──────────────────────────────────────────────────────────────────┘

        """
        appendRaw(divider)
    }

    func log(_ message: String, level: LogLevel = .info) {
        let line = "[\(timestamp())] [\(level.rawValue)] \(message)\n"
        appendRaw(line)
    }

    func logFrame(_ message: String) {
        let line = "[\(timestamp())] [FRAME] \(message)\n"
        appendRaw(line)
    }

    func logWriter(_ message: String) {
        let line = "[\(timestamp())] [WRITER] \(message)\n"
        appendRaw(line)
    }

    func logMixer(_ message: String) {
        let line = "[\(timestamp())] [MIXER] \(message)\n"
        appendRaw(line)
    }

    func logPreview(_ message: String) {
        let line = "[\(timestamp())] [PREVIEW] \(message)\n"
        appendRaw(line)
    }

    func logError(_ message: String) {
        let line = "[\(timestamp())] [ERROR] \(message)\n"
        appendRaw(line)
    }

    var logFileURL: URL { fileURL }

    var hasLogs: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Log Levels

    enum LogLevel: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }

    // MARK: - Private

    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    private func appendRaw(_ text: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let data = text.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.fileURL, options: .atomic)
                }
            }
        }
    }

    private static func machineModel() -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
