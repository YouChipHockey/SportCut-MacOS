//
//  ProjectNotificationSubscriptions.swift
//  Youchip-Stat
//
//  Centralized storage for NotificationCenter/Combine subscriptions.
//

import Foundation
import Combine

final class ProjectNotificationSubscriptions: ObservableObject {
    private(set) var cancellables = Set<AnyCancellable>()
    
    func store(_ cancellable: AnyCancellable) {
        cancellables.insert(cancellable)
    }
    
    func cancelAll() {
        cancellables.removeAll()
    }
}
