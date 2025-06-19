//
//  StreamManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import AVKit

enum StreamManagerError: Error {
    case streamNotAvailable
    case streamServerNotReachable
    case streamSetupFailed
    case videoPlayerNotReady
    case networkError(Error)
    
    var description: String {
        switch self {
        case .streamNotAvailable:
            return "Трансляция недоступна"
        case .streamServerNotReachable:
            return "Сервер трансляции не доступен"
        case .streamSetupFailed:
            return "Не удалось настроить трансляцию"
        case .videoPlayerNotReady:
            return "Плеер не готов к воспроизведению"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}

class StreamManager: ObservableObject {
    static let shared = StreamManager()
    
    private let apiService = MarkersAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isLoading = false
    @Published var error: StreamManagerError? = nil
    @Published var currentStream: Stream? = nil
    @Published var availableStreams: [Stream] = []
    @Published var isLive = false
    
    init() {
        refreshAvailableStreams()
    }
    
    func refreshAvailableStreams() {
        isLoading = true
        error = nil
        
        apiService.getAllStreamsPublisher()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                self.isLoading = false
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    print("Failed to load streams: \(error.localizedDescription)")
                    self.error = .networkError(error)
                }
            }, receiveValue: { [weak self] streams in
                guard let self = self else { return }
                
                self.availableStreams = streams
                self.sortStreams()
            })
            .store(in: &cancellables)
    }
    
    func fetchStreamDetails(streamId: Int, completion: @escaping (Result<Stream, StreamManagerError>) -> Void) {
        isLoading = true
        error = nil
        
        apiService.getStreamPublisher(withId: streamId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] result in
                guard let self = self else { return }
                
                self.isLoading = false
                switch result {
                case .finished:
                    break
                case .failure(let error):
                    print("Failed to load stream details: \(error.localizedDescription)")
                    self.error = .networkError(error)
                    completion(.failure(.networkError(error)))
                }
            }, receiveValue: { [weak self] stream in
                guard let self = self else { return }
                
                self.currentStream = stream
                self.isLive = stream.isLive
                completion(.success(stream))
            })
            .store(in: &cancellables)
    }
    
    func getStreamURL(stream: Stream) -> URL? {
        guard !stream.serverUrl.isEmpty, !stream.streamKey.isEmpty else {
            error = .streamNotAvailable
            return nil
        }
        
        let streamUrlString: String
        if stream.serverUrl.hasSuffix("/") {
            streamUrlString = "\(stream.serverUrl)\(stream.streamKey)/playlist.m3u8"
        } else {
            streamUrlString = "\(stream.serverUrl)/\(stream.streamKey)/playlist.m3u8"
        }
        
        return URL(string: streamUrlString)
    }
    
    func playStream(streamId: Int, completion: @escaping (Result<Void, StreamManagerError>) -> Void) {
        fetchStreamDetails(streamId: streamId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let stream):
                guard let streamURL = self.getStreamURL(stream: stream) else {
                    completion(.failure(.streamNotAvailable))
                    return
                }
                
                let asset = AVAsset(url: streamURL)
                let playerItem = AVPlayerItem(asset: asset)
                
                let videoManager = VideoPlayerManager.shared
                videoManager.player = AVPlayer(playerItem: playerItem)
                videoManager.player?.play()
                
                videoManager.player?.currentItem?.publisher(for: \.status)
                    .sink { status in
                        switch status {
                        case .readyToPlay:
                            completion(.success(()))
                        case .failed:
                            if let error = videoManager.player?.currentItem?.error {
                                completion(.failure(.networkError(error)))
                            } else {
                                completion(.failure(.streamSetupFailed))
                            }
                        default:
                            break
                        }
                    }
                    .store(in: &self.cancellables)
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func isStreamAvailable(_ stream: Stream) -> Bool {
        if stream.isLive {
            return true
        }
        
        let currentTime = Date()
        let timeInterval = stream.scheduledStart.timeIntervalSince(currentTime)
        return timeInterval > 0 && timeInterval < 600
    }
    
    private func sortStreams() {
        availableStreams.sort { (stream1, stream2) -> Bool in
            if stream1.isLive && !stream2.isLive {
                return true
            } else if !stream1.isLive && stream2.isLive {
                return false
            } else {
                return stream1.scheduledStart < stream2.scheduledStart
            }
        }
    }
}
