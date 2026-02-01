//
//  VideoDownloadModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 22.01.2026.
//

import Foundation

struct VideoFormatsResponse: Codable {
    let title: String?
    let filename: String
    let qualities: [VideoQuality]
}

struct VideoQuality: Codable, Identifiable {
    let height: Int
    let sizeBytes: Int
    let downloadUrl: String
    
    var id: Int { height }
    
    var displayName: String {
        "\(height)p"
    }
    
    var displaySize: String {
        let bytes = Double(sizeBytes)
        let mb = bytes / 1_048_576
        let gb = bytes / 1_073_741_824
        
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }
    
    var progressID: String? {
        guard let urlComponents = URLComponents(string: downloadUrl) else { return nil }
        return urlComponents.queryItems?.first(where: { 
            $0.name.lowercased() == "progressid" 
        })?.value
    }
    
    enum CodingKeys: String, CodingKey {
        case height
        case sizeBytes = "size_bytes"
        case downloadUrl = "download_url"
    }
}

enum VideoDownloadState: Equatable {
    case idle
    case fetchingFormats
    case selectingQuality
    case downloading(progress: Double)
    case completed(url: URL)
    case error(message: String)
}
