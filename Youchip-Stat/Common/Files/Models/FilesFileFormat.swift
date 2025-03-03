//
//  FilesFileFormat.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

enum FilesFileFormat: String {
    
    case folder
    
    //images
    case jpg
    case jpeg
    case png
    case gif
    case tiff
    case webp
    case bmp
    case heic
    case ico
    
    //archives
    case zip
    case rar
    case sevenZip = "7z"
    
    //videos
    case mov
    case mp4
    case m4v
    
    //audios
    case mp3
    case m4a
    case aiff
    case aac
    
    //files
    case txt
    case rtf
    case pages
    case numbers
    case key
    case epub
    case vcf
    case csv
    
    //spreadsheets
    case xls
    case xlsx
    
    //documents
    case doc
    case docx
    
    //presentations
    case ppt
    case pptx
    
    //pdf
    case pdf
    
    //unknown
    case unknown
    
    var kind: FilesFileKind {
        switch self {
        case .folder:
            return .folder
        case .jpg, .jpeg, .png, .gif, .tiff, .bmp, .webp, .heic, .ico:
            return .images
        case .zip, .rar, .sevenZip:
            return .archives
        case .mov, .mp4, .m4v:
            return .videos
        case .mp3, .m4a, .aiff, .aac:
            return .audios
        case .txt, .rtf, .pages, .numbers, .key, .epub, .vcf, .csv:
            return .files
        case .xls, .xlsx:
            return .spreadsheets
        case .doc, .docx:
            return .documents
        case .ppt, .pptx:
            return .presentations
        case .pdf:
            return .pdf
        case .unknown:
            return .unknown
        }
    }
    
    init(pathExtension: String) {
        self = FilesFileFormat(rawValue: pathExtension) ?? .unknown
    }
    
}

enum FilesFileKind {
    case folder
    case images
    case archives
    case videos
    case audios
    case files
    case spreadsheets
    case documents
    case presentations
    case pdf
    case unknown
}

extension FilesFile {
    
    var fileFormat: FilesFileFormat {
        let pathExtension = pathExtension.lowercased()
        return FilesFileFormat(pathExtension: pathExtension)
    }
    
}
