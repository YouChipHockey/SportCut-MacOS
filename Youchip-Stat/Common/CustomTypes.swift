//
//  CustomTypes.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 21.06.2024.
//

import Foundation

class CustomTypes {
    
    typealias Completion = (FileDocumentPickerFileResponse) -> Void
    typealias MultipleFilesCompletion = (FileDocumentPickerFilesResponse) -> Void
    typealias SubscriptionRequestHandler = (Result<Data, Error>) -> Void
    typealias CompletionWithResult = (Result<URL, Error>) -> Void
    typealias DataCompletion = (Result<Data, Error>) -> Void
    
}
