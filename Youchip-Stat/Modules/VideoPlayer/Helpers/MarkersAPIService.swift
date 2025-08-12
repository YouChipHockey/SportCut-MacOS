//
//  MarkersAPIService.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import FirebaseAppCheck

enum MarkersAPIError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String?)
    case noData
    case unauthorized
    case unknown
    case appCheckTokenError
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message ?? "Unknown error")"
        case .noData:
            return "No data received"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "Unknown error"
        case .appCheckTokenError:
            return "Failed to get App Check token"
        }
    }
}

struct Stream: Codable {
    let title: String
    let scheduledStart: Date
    let id: Int
    let streamKey: String
    let serverUrl: String
    let isLive: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case title
        case scheduledStart = "scheduled_start"
        case id
        case streamKey = "stream_key"
        case serverUrl = "server_url"
        case isLive = "is_live"
        case createdAt = "created_at"
    }
}

class MarkersAPIService {
    static let shared = MarkersAPIService()
    
    private var baseURL: URL? {
        return URL(string: "https://razmetka.youchip.pro")
    }
    
    private let session: URLSession
    private let decoder: JSONDecoder
        
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func addAppCheckToken(to request: URLRequest, completion: @escaping (Result<URLRequest, MarkersAPIError>) -> Void) {
        var mutableRequest = request
        
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                completion(.failure(.appCheckTokenError))
                return
            }
            
            guard let token = token else {
                completion(.failure(.appCheckTokenError))
                return
            }
            
            mutableRequest.addValue(token.token, forHTTPHeaderField: "X-Firebase-AppCheck")
            completion(.success(mutableRequest))
        }
    }
    
    private func getAppCheckToken() -> AnyPublisher<String, MarkersAPIError> {
        return Future<String, MarkersAPIError> { promise in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error = error {
                    promise(.failure(.appCheckTokenError))
                    return
                }
                
                guard let token = token else {
                    promise(.failure(.appCheckTokenError))
                    return
                }
                
                promise(.success(token.token))
            }
        }.eraseToAnyPublisher()
    }
    
    func uploadMarkers(for videoId: String, markersData: [TimelineLine], completion: @escaping (Result<Void, MarkersAPIError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let fullData = transformToFullTimelineLines(markersData)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(fullData)
            request.httpBody = jsonData
            
            addAppCheckToken(to: request) { result in
                switch result {
                case .success(let tokenizedRequest):
                    let task = self.session.dataTask(with: tokenizedRequest) { data, response, error in
                        if let error = error {
                            completion(.failure(.networkError(error)))
                            return
                        }
                        
                        guard let httpResponse = response as? HTTPURLResponse else {
                            completion(.failure(.unknown))
                            return
                        }
                        
                        switch httpResponse.statusCode {
                        case 200...299:
                            completion(.success(()))
                        case 401:
                            completion(.failure(.unauthorized))
                        default:
                            let message = String(data: data ?? Data(), encoding: .utf8)
                            completion(.failure(.serverError(httpResponse.statusCode, message)))
                        }
                    }
                    task.resume()
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(.networkError(error)))
        }
    }
    
    func getMarkers(for videoId: String, completion: @escaping (Result<[TimelineLine], MarkersAPIError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        addAppCheckToken(to: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let tokenizedRequest):
                let task = self.session.dataTask(with: tokenizedRequest) { [weak self] data, response, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(.unknown))
                        return
                    }
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        guard let data = data else {
                            completion(.failure(.noData))
                            return
                        }
                        
                        do {
                            if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let markersData = responseDict["data"] as? [[String: Any]] {
                                
                                let jsonData = try JSONSerialization.data(withJSONObject: markersData)
                                let fullTimelineLines = try JSONDecoder().decode([FullTimelineLine].self, from: jsonData)
                                
                                let timelineLines = self.convertFromFullTimelineLines(fullTimelineLines)
                                completion(.success(timelineLines))
                            } else {
                                let timelineLines = try JSONDecoder().decode([TimelineLine].self, from: data)
                                completion(.success(timelineLines))
                            }
                        } catch {
                            completion(.failure(.decodingError(error)))
                        }
                    case 401:
                        completion(.failure(.unauthorized))
                    default:
                        let message = String(data: data ?? Data(), encoding: .utf8)
                        completion(.failure(.serverError(httpResponse.statusCode, message)))
                    }
                }
                task.resume()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteMarkers(for videoId: String, completion: @escaping (Result<Void, MarkersAPIError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        addAppCheckToken(to: request) { result in
            switch result {
            case .success(let tokenizedRequest):
                let task = self.session.dataTask(with: tokenizedRequest) { data, response, error in
                    if let error = error {
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(.unknown))
                        return
                    }
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        completion(.success(()))
                    case 401:
                        completion(.failure(.unauthorized))
                    default:
                        let message = String(data: data ?? Data(), encoding: .utf8)
                        completion(.failure(.serverError(httpResponse.statusCode, message)))
                    }
                }
                task.resume()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func uploadMarkersPublisher(for videoId: String, markersData: [TimelineLine]) -> AnyPublisher<Void, MarkersAPIError> {
        guard let baseURL = baseURL else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let fullData = transformToFullTimelineLines(markersData)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(fullData)
            request.httpBody = jsonData
            
            return getAppCheckToken()
                .flatMap { token -> AnyPublisher<URLSession.DataTaskPublisher.Output, MarkersAPIError> in
                    var tokenizedRequest = request
                    tokenizedRequest.addValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
                    
                    return self.session.dataTaskPublisher(for: tokenizedRequest)
                        .mapError { MarkersAPIError.networkError($0) }
                        .eraseToAnyPublisher()
                }
                .tryMap { data, response in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw MarkersAPIError.unknown
                    }
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        return ()
                    case 401:
                        throw MarkersAPIError.unauthorized
                    default:
                        let message = String(data: data, encoding: .utf8)
                        throw MarkersAPIError.serverError(httpResponse.statusCode, message)
                    }
                }
                .mapError { error in
                    if let apiError = error as? MarkersAPIError {
                        return apiError
                    }
                    return .networkError(error)
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: .networkError(error)).eraseToAnyPublisher()
        }
    }
    
    func getMarkersPublisher(for videoId: String) -> AnyPublisher<[TimelineLine], MarkersAPIError> {
        guard let baseURL = baseURL else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        return getAppCheckToken()
            .flatMap { token -> AnyPublisher<URLSession.DataTaskPublisher.Output, MarkersAPIError> in
                var tokenizedRequest = request
                tokenizedRequest.addValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
                
                return self.session.dataTaskPublisher(for: tokenizedRequest)
                    .mapError { MarkersAPIError.networkError($0) }
                    .eraseToAnyPublisher()
            }
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MarkersAPIError.unknown
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw MarkersAPIError.unauthorized
                default:
                    let message = String(data: data, encoding: .utf8)
                    throw MarkersAPIError.serverError(httpResponse.statusCode, message)
                }
            }
            .tryMap { [weak self] data -> [TimelineLine] in
                guard let self = self else {
                    throw MarkersAPIError.unknown
                }
                
                do {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let markersData = responseDict["data"] as? [[String: Any]] {
                        
                        let jsonData = try JSONSerialization.data(withJSONObject: markersData)
                        let fullTimelineLines = try JSONDecoder().decode([FullTimelineLine].self, from: jsonData)
                        return self.convertFromFullTimelineLines(fullTimelineLines)
                    } else {
                        return try JSONDecoder().decode([TimelineLine].self, from: data)
                    }
                } catch {
                    throw MarkersAPIError.decodingError(error)
                }
            }
            .mapError { error in
                if let apiError = error as? MarkersAPIError {
                    return apiError
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    func deleteMarkersPublisher(for videoId: String) -> AnyPublisher<Void, MarkersAPIError> {
        guard let baseURL = baseURL else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("api/markers/\(videoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        return getAppCheckToken()
            .flatMap { token -> AnyPublisher<URLSession.DataTaskPublisher.Output, MarkersAPIError> in
                var tokenizedRequest = request
                tokenizedRequest.addValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
                
                return self.session.dataTaskPublisher(for: tokenizedRequest)
                    .mapError { MarkersAPIError.networkError($0) }
                    .eraseToAnyPublisher()
            }
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MarkersAPIError.unknown
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return ()
                case 401:
                    throw MarkersAPIError.unauthorized
                default:
                    let message = String(data: data, encoding: .utf8)
                    throw MarkersAPIError.serverError(httpResponse.statusCode, message)
                }
            }
            .mapError { error in
                if let apiError = error as? MarkersAPIError {
                    return apiError
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    func getAllStreams(completion: @escaping (Result<[Stream], MarkersAPIError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/streams")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        addAppCheckToken(to: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let tokenizedRequest):
                let task = self.session.dataTask(with: tokenizedRequest) { data, response, error in
                    if let error = error {
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(.unknown))
                        return
                    }
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        guard let data = data else {
                            completion(.failure(.noData))
                            return
                        }
                        
                        do {
                            let streams = try self.decoder.decode([Stream].self, from: data)
                            completion(.success(streams))
                        } catch {
                            completion(.failure(.decodingError(error)))
                        }
                    case 401:
                        completion(.failure(.unauthorized))
                    default:
                        let message = String(data: data ?? Data(), encoding: .utf8)
                        completion(.failure(.serverError(httpResponse.statusCode, message)))
                    }
                }
                task.resume()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getStream(withId streamId: Int, completion: @escaping (Result<Stream, MarkersAPIError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let url = baseURL.appendingPathComponent("api/streams/\(streamId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        addAppCheckToken(to: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let tokenizedRequest):
                let task = self.session.dataTask(with: tokenizedRequest) { data, response, error in
                    if let error = error {
                        completion(.failure(.networkError(error)))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(.unknown))
                        return
                    }
                    
                    switch httpResponse.statusCode {
                    case 200...299:
                        guard let data = data else {
                            completion(.failure(.noData))
                            return
                        }
                        
                        do {
                            let stream = try self.decoder.decode(Stream.self, from: data)
                            completion(.success(stream))
                        } catch {
                            completion(.failure(.decodingError(error)))
                        }
                    case 401:
                        completion(.failure(.unauthorized))
                    default:
                        let message = String(data: data ?? Data(), encoding: .utf8)
                        completion(.failure(.serverError(httpResponse.statusCode, message)))
                    }
                }
                task.resume()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getAllStreamsPublisher() -> AnyPublisher<[Stream], MarkersAPIError> {
        guard let baseURL = baseURL else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("api/streams")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        return getAppCheckToken()
            .flatMap { token -> AnyPublisher<URLSession.DataTaskPublisher.Output, MarkersAPIError> in
                var tokenizedRequest = request
                tokenizedRequest.addValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
                
                return self.session.dataTaskPublisher(for: tokenizedRequest)
                    .mapError { MarkersAPIError.networkError($0) }
                    .eraseToAnyPublisher()
            }
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MarkersAPIError.unknown
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw MarkersAPIError.unauthorized
                default:
                    let message = String(data: data, encoding: .utf8)
                    throw MarkersAPIError.serverError(httpResponse.statusCode, message)
                }
            }
            .decode(type: [Stream].self, decoder: self.decoder)
            .mapError { error in
                if let apiError = error as? MarkersAPIError {
                    return apiError
                }
                if error is DecodingError {
                    return .decodingError(error)
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    func getStreamPublisher(withId streamId: Int) -> AnyPublisher<Stream, MarkersAPIError> {
        guard let baseURL = baseURL else {
            return Fail(error: .invalidURL).eraseToAnyPublisher()
        }
        
        let url = baseURL.appendingPathComponent("api/streams/\(streamId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        return getAppCheckToken()
            .flatMap { token -> AnyPublisher<URLSession.DataTaskPublisher.Output, MarkersAPIError> in
                var tokenizedRequest = request
                tokenizedRequest.addValue(token, forHTTPHeaderField: "X-Firebase-AppCheck")
                
                return self.session.dataTaskPublisher(for: tokenizedRequest)
                    .mapError { MarkersAPIError.networkError($0) }
                    .eraseToAnyPublisher()
            }
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MarkersAPIError.unknown
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw MarkersAPIError.unauthorized
                default:
                    let message = String(data: data, encoding: .utf8)
                    throw MarkersAPIError.serverError(httpResponse.statusCode, message)
                }
            }
            .decode(type: Stream.self, decoder: self.decoder)
            .mapError { error in
                if let apiError = error as? MarkersAPIError {
                    return apiError
                }
                if error is DecodingError {
                    return .decodingError(error)
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    
    private func transformToFullTimelineLines(_ lines: [TimelineLine]) -> [FullTimelineLine] {
        let tagLibrary = TagLibraryManager.shared
        
        return lines.map { line in
            let fullStamps = line.stamps.map { stamp -> FullTimelineStamp in
                let tag = tagLibrary.findTagById(stamp.idTag)
                var tagGroup: TagGroupInfo? = nil
                if let tagID = tag?.id {
                    for group in tagLibrary.allTagGroups {
                        if group.tags.contains(tagID) {
                            tagGroup = TagGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                }
                
                let fullTag = FullTagWithGroup(
                    id: tag?.id ?? "",
                    primaryID: tag?.primaryID,
                    name: tag?.name ?? stamp.label,
                    description: tag?.description ?? "",
                    color: tag?.color ?? "FFFFFF",
                    defaultTimeBefore: tag?.defaultTimeBefore ?? 0,
                    defaultTimeAfter: tag?.defaultTimeAfter ?? 0,
                    collection: tag?.collection ?? "",
                    hotkey: tag?.hotkey,
                    labelHotkeys: tag?.labelHotkeys,
                    group: tagGroup
                )
                
                let fullLabels = stamp.labels.compactMap { labelID -> FullLabelWithGroup? in
                    guard let label = tagLibrary.findLabelById(labelID) else { return nil }
                    
                    var labelGroup: LabelGroupInfo? = nil
                    for group in tagLibrary.allLabelGroups {
                        if group.lables.contains(labelID) {
                            labelGroup = LabelGroupInfo(id: group.id, name: group.name)
                            break
                        }
                    }
                    
                    return FullLabelWithGroup(
                        id: label.id,
                        name: label.name,
                        description: label.description,
                        group: labelGroup
                    )
                }
                
                let fullTimeEvents = stamp.timeEvents.compactMap { eventID in
                    tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
                }
                
                return FullTimelineStamp(
                    id: stamp.id,
                    timeStart: stamp.timeStart,
                    timeFinish: stamp.timeFinish,
                    tag: fullTag,
                    labels: fullLabels,
                    timeEvents: fullTimeEvents,
                    position: stamp.position
                )
            }
            
            return FullTimelineLine(id: line.id, name: line.name, stamps: fullStamps)
        }
    }
    
    private func convertFromFullTimelineLines(_ fullLines: [FullTimelineLine]) -> [TimelineLine] {
        return fullLines.map { fullLine in
            let stamps = fullLine.stamps.map { fullStamp -> TimelineStamp in
                let position = fullStamp.position
                let isActiveForMapView = position != nil
                
                return TimelineStamp(
                    id: fullStamp.id,
                    idTag: fullStamp.tag.id,
                    primaryID: fullStamp.tag.primaryID,
                    timeStart: fullStamp.timeStart,
                    timeFinish: fullStamp.timeFinish,
                    colorHex: fullStamp.tag.color,
                    label: fullStamp.tag.name,
                    labels: fullStamp.labels.map { $0.id },
                    timeEvents: fullStamp.timeEvents.map { $0.id },
                    position: position,
                    isActiveForMapView: isActiveForMapView
                )
            }
            
            return TimelineLine(id: fullLine.id, name: fullLine.name, stamps: stamps)
        }
    }
}
