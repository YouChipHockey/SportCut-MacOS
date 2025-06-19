//
//  NetworkMonitor.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import Foundation
import Combine
import FirebaseAppCheck

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    @Published var isConnected: Bool? = nil
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        isConnected = true
        
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                let connected = Double.random(in: 0...1) < 0.95
                
                if self?.isConnected != connected {
                    self?.isConnected = connected
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NetworkStatusChanged"),
                        object: nil,
                        userInfo: ["isConnected": connected]
                    )
                }
            }
            .store(in: &cancellables)
    }
}
