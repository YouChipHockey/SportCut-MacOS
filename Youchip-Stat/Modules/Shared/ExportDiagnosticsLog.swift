//
//  ExportDiagnosticsLog.swift
//  Youchip-Stat
//
//  Журнал экспорта в ФАЙЛ. `print` виден только когда приложение запущено из Xcode, а разбирать
//  «Operation Stopped» и «почему не нанёсся счётчик/логотип» нужно по факту — на живом прогоне.
//  Поэтому каждый экспорт (разметка и просмотр) пишет сюда, что он собрал и чем кончил:
//
//      ~/Library/Application Support/YouChip-Stat/exportDiagnostics.log
//      (в песочнице — внутри контейнера приложения)
//
//  Файл кольцевой по размеру: при превышении лимита старое содержимое сбрасывается, чтобы журнал
//  не рос бесконечно. Ошибки печатаются со всей цепочкой `NSUnderlyingError` — именно там лежит
//  настоящая причина отказа AVFoundation.
//

import AVFoundation
import Foundation

enum ExportDiagnosticsLog {

    /// Порог, после которого файл начинается заново.
    private static let maxBytes = 2 * 1024 * 1024
    private static let queue = DispatchQueue(label: "com.youchip.exportDiagnostics")

    static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("YouChip-Stat", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("exportDiagnostics.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Заголовок нового прогона экспорта — по нему легко найти нужный кусок журнала.
    static func begin(_ title: String) {
        log("")
        log("=========== \(title) ===========")
    }

    static func log(_ text: String) {
        let line = text.isEmpty ? "" : "[\(formatter.string(from: Date()))] \(text)"
        queue.async {
            guard let url = fileURL else { return }
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                if size > UInt64(maxBytes) {
                    try? handle.truncate(atOffset: 0)
                }
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Ошибка со всей цепочкой `NSUnderlyingError` — у AVFoundation причина почти всегда там.
    static func error(_ label: String, _ error: Error?) {
        guard let error else {
            log("❌ \(label): (nil)")
            return
        }
        var ns = error as NSError
        var text = "❌ \(label): \(ns.domain) code=\(ns.code) — \(ns.localizedDescription)"
        var depth = 0
        while let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, depth < 5 {
            text += "\n    ↳ underlying: \(underlying.domain) code=\(underlying.code) — \(underlying.localizedDescription)"
            ns = underlying
            depth += 1
        }
        log(text)
    }

    // MARK: - Описания медиа (то, из-за чего AVFoundation обычно и отказывает)

    /// Краткое описание видеодорожки: размер, поворот, fps, кодек.
    static func describe(track: AVAssetTrack?) -> String {
        guard let track else { return "video track: nil" }
        let natural = track.naturalSize
        let oriented = natural.applying(track.preferredTransform)
        let codec: String = {
            // `formatDescriptions` объявлен как [Any], но у видеодорожки там всегда
            // CMFormatDescription. Условный каст на CF-тип компилятор ругает («всегда успешно»),
            // поэтому берём напрямую.
            guard let desc = track.formatDescriptions.first else { return "?" }
            return fourCC(CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription))
        }()
        return String(
            format: "video %.0fx%.0f (oriented %.0fx%.0f) fps=%.2f codec=%@ transform=[%.2f %.2f %.2f %.2f %.1f %.1f]",
            natural.width, natural.height,
            abs(oriented.width), abs(oriented.height),
            track.nominalFrameRate, codec,
            track.preferredTransform.a, track.preferredTransform.b,
            track.preferredTransform.c, track.preferredTransform.d,
            track.preferredTransform.tx, track.preferredTransform.ty
        )
    }

    /// Краткое описание композиции: длительность и дорожки с их сегментами.
    static func describe(composition: AVComposition) -> String {
        var lines: [String] = ["composition duration=\(fmt(composition.duration)) tracks=\(composition.tracks.count)"]
        for track in composition.tracks {
            lines.append("    track \(track.mediaType.rawValue) id=\(track.trackID) segments=\(track.segments.count) duration=\(fmt(track.timeRange.duration))")
        }
        return lines.joined(separator: "\n")
    }

    /// Краткое описание видео-композиции: размер кадра и инструкции (их разрывы и нули —
    /// самая частая причина отказа экспорта).
    static func describe(videoComposition: AVVideoComposition?) -> String {
        guard let vc = videoComposition else { return "videoComposition: nil" }
        var text = String(format: "videoComposition renderSize=%.0fx%.0f frameDuration=%@ instructions=%d",
                          vc.renderSize.width, vc.renderSize.height, fmt(vc.frameDuration), vc.instructions.count)
        var previousEnd: CMTime = .zero
        for (index, instruction) in vc.instructions.enumerated() {
            let range = instruction.timeRange
            let gap = CMTimeCompare(range.start, previousEnd) != 0
            text += "\n    [\(index)] \(fmt(range.start)) + \(fmt(range.duration))"
            if CMTimeGetSeconds(range.duration) <= 0 { text += "  ⚠️ ZERO/NEGATIVE DURATION" }
            if gap { text += "  ⚠️ NOT CONTIGUOUS (ожидалось начало \(fmt(previousEnd)))" }
            previousEnd = CMTimeAdd(range.start, range.duration)
        }
        return text
    }

    static func fmt(_ time: CMTime) -> String {
        guard time.isValid else { return "invalid" }
        return String(format: "%.3fs", CMTimeGetSeconds(time))
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
    }
}

// MARK: - Пустые дорожки

extension AVMutableComposition {

    /// Удаляет из композиции дорожки, в которые ничего не вставили.
    ///
    /// Аудио-дорожку заводят заранее, до разбора исходников. Если звука нет ни у одного куска
    /// (запись экрана, немой mov), она остаётся без сегментов — и `AVAssetExportSession` падает
    /// на такой композиции с «Operation Stopped» (-11838, внутри OSStatus -16976), больше ничего
    /// не объясняя. Поэтому чистим композицию перед созданием сессии экспорта.
    func removeEmptyTracks() {
        for track in tracks where track.segments.isEmpty || CMTimeGetSeconds(track.timeRange.duration) <= 0 {
            ExportDiagnosticsLog.log("удалена ПУСТАЯ дорожка \(track.mediaType.rawValue) id=\(track.trackID) — иначе экспорт падает с «Operation Stopped»")
            removeTrack(track)
        }
    }
}
