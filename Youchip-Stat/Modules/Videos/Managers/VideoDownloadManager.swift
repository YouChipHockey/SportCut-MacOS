//
//  VideoDownloadManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 22.01.2026.
//

import Foundation
import Combine

class VideoDownloadManager: NSObject, ObservableObject {
    
    static let shared = VideoDownloadManager()
    
    @Published var downloadState: VideoDownloadState = .idle
    @Published var availableQualities: [VideoQuality] = []
    @Published var suggestedFilename: String = ""
    @Published var videoTitle: String?
    
    private var downloadTask: URLSessionDownloadTask?
    private var progressTask: Task<Void, Never>?
    private let permissionManager = DownloadsFolderPermissionManager.shared
    
    private override init() {
        super.init()
    }
    
    func fetchFormats(for urlString: String, ext: String = "mp4") async throws {
        await MainActor.run {
            self.downloadState = .fetchingFormats
        }
        
        guard var components = URLComponents(string: "https://myaeva.pro/formats") else {
            throw VideoDownloadError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "url", value: urlString),
            URLQueryItem(name: "ext", value: ext)
        ]
        
        guard let url = components.url else {
            throw VideoDownloadError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VideoDownloadError.serverError
        }
        
        let formatsResponse = try JSONDecoder().decode(VideoFormatsResponse.self, from: data)
        
        await MainActor.run {
            self.availableQualities = formatsResponse.qualities
            self.suggestedFilename = formatsResponse.filename
            self.videoTitle = formatsResponse.title
            self.downloadState = .selectingQuality
        }
    }
    
    func checkAndRequestPermissions() async -> Bool {
        if permissionManager.checkDownloadsAccess() {
            return true
        }
        
        return await withCheckedContinuation { continuation in
            permissionManager.requestDownloadsAccess { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func downloadVideo(
        quality: VideoQuality,
        filename: String
    ) async throws -> URL {
        let hasPermission = await checkAndRequestPermissions()
        guard hasPermission else {
            throw VideoDownloadError.permissionDenied
        }
        
        await MainActor.run {
            self.downloadState = .downloading(progress: 0.0)
        }
        
        guard let url = URL(string: "https://myaeva.pro\(quality.downloadUrl)") else {
            throw VideoDownloadError.invalidURL
        }
        
        let progressId = quality.progressID
        let destinationURL = try await downloadFile(from: url, filename: filename, progressId: progressId)
        
        await MainActor.run {
            self.downloadState = .completed(url: destinationURL)
        }
        
        return destinationURL
    }
    
    private func downloadFile(from url: URL, filename: String, progressId: String?) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let configuration = URLSessionConfiguration.default
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            
            let downloadTask = session.downloadTask(with: url) { [weak self] tempURL, response, error in
                self?.stopProgressTracking()
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: VideoDownloadError.downloadFailed)
                    return
                }
                
                do {
                    let documentsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    let destinationURL = documentsURL.appendingPathComponent(filename)
                    
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            self.downloadTask = downloadTask
            downloadTask.resume()
            
            if let progressId = progressId {
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.startProgressTracking(progressId: progressId)
                }
            }
        }
    }
    
    private func startProgressTracking(progressId: String) {
        progressTask?.cancel()
        
        progressTask = Task {
            guard let url = URL(string: "https://myaeva.pro/progress/\(progressId)") else {
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            
            while !Task.isCancelled {
                do {
                    let (data, _) = try await URLSession.shared.data(for: request)
                    
                    var jsonData = data
                    if let dataString = String(data: data, encoding: .utf8) {
                        var jsonString = dataString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if jsonString.hasPrefix("data:") {
                            jsonString = String(jsonString.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else if jsonString.hasPrefix("data: ") {
                            jsonString = String(jsonString.dropFirst(6))
                        }
                        
                        if let cleanedData = jsonString.data(using: .utf8) {
                            jsonData = cleanedData
                        }
                    }
                    
                    if let progressData = try? JSONDecoder().decode(ProgressData.self, from: jsonData) {
                        await MainActor.run {
                            self.downloadState = .downloading(progress: progressData.progress)
                        }
                        
                        if progressData.state == "done" || progressData.state == "completed" {
                            break
                        }
                        
                        if progressData.state == "error" || progressData.state == "failed" {
                            break
                        }
                    }
                    
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    
                } catch {
                    if Task.isCancelled {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }
    
    private func stopProgressTracking() {
        progressTask?.cancel()
        progressTask = nil
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        stopProgressTracking()
        downloadState = .idle
    }
    
    func reset() {
        cancelDownload()
        availableQualities = []
        suggestedFilename = ""
        videoTitle = nil
        downloadState = .idle
    }
}

extension VideoDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    }
}

private struct ProgressData: Codable {
    let state: String
    let bytesSent: Int64
    let totalBytes: Int64
    let percent: Double
    let createdAt: String?
    let updatedAt: String?
    let updatedAtTs: Double?
    
    enum CodingKeys: String, CodingKey {
        case state
        case bytesSent = "bytes_sent"
        case totalBytes = "total_bytes"
        case percent
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case updatedAtTs = "updated_at_ts"
    }
    
    var progress: Double {
        return percent / 100.0
    }
}

enum VideoDownloadError: LocalizedError {
    case invalidURL
    case serverError
    case downloadFailed
    case saveFailed
    case permissionDenied
    case progressIdNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверная ссылка на видео"
        case .serverError:
            return "Ошибка сервера при получении видео"
        case .downloadFailed:
            return "Не удалось загрузить видео"
        case .saveFailed:
            return "Не удалось сохранить видео"
        case .permissionDenied:
            return ^String.Titles.downloadsFolderAccessRequired
        case .progressIdNotFound:
            return "Не удалось получить идентификатор прогресса"
        }
    }
}
