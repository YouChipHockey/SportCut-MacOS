//
//  CustomTypes.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 21.06.2024.
//

import Foundation

class CustomTypes {
    
    typealias Completion = (FileDocumentPickerFileResponse) -> Void // CustomTypes.Completion
    typealias MultipleFilesCompletion = (FileDocumentPickerFilesResponse) -> Void // CustomTypes.MultipleFilesCompletion
    typealias SubscriptionRequestHandler = (Result<Data, Error>) -> Void // CustomTypes.SubscriptionRequestHandler
    typealias CompletionWithResult = (Result<URL, Error>) -> Void // CustomTypes.CompletionWithResult
    typealias DataCompletion = (Result<Data, Error>) -> Void // CustomTypes.DataCompletion
    
}
