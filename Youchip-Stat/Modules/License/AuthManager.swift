//
//  AuthManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/12/25.
//

import SwiftUI
import Foundation

struct AuthResponse: Codable {
    let expiration_date: String
    let detail: String?
    let status: Int
}

class AuthManager: ObservableObject {
    @Published var isAuthValid = false
    @Published var showAuthSheet = false
    @Published var isValidating = false
    @Published var validationError: String?
    @Published var shouldDismissSheet = false
    @Published var timeManipulationDetected = false
    
    private let deviceIDKey = "device_code"
    private let authDeadlineKey = "auth_deadline"
    private let lastLoginDateKey = "last_login_date"
    private let serverURL = "https://razmetka.youchip.pro/api/auth/license"
    
    init() {
        checkAuthStatus()
        validateSystemDate()
    }
    
    func checkAuthStatus() {
        if UserDefaults.standard.string(forKey: deviceIDKey) == nil {
            let deviceID = UUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: deviceIDKey)
        }
        if let deadlineString = UserDefaults.standard.string(forKey: authDeadlineKey),
           let deadline = dateFromString(deadlineString),
           deadline > Date() {
            isAuthValid = true
        } else {
            isAuthValid = false
            showAuthSheet = true
        }
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter.date(from: string)
    }
    
    private func validateSystemDate() {
        let currentDate = Date()
        
        if let lastLoginDateString = UserDefaults.standard.string(forKey: lastLoginDateKey),
           let lastLoginDate = dateFromString(lastLoginDateString) {
            
            let calendar = Calendar.current
            if calendar.compare(currentDate, to: lastLoginDate, toGranularity: .day) == .orderedAscending {
                timeManipulationDetected = true
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        let currentDateString = formatter.string(from: currentDate)
        UserDefaults.standard.set(currentDateString, forKey: lastLoginDateKey)
    }
    
    func validateAuth(code: String) {
        guard !code.isEmpty else {
            validationError = "Пожалуйста, введите данные"
            return
        }
        
        isValidating = true
        validationError = nil
        
        guard let deviceID = UserDefaults.standard.string(forKey: deviceIDKey) else {
            isValidating = false
            validationError = "Не удалось идентифицировать устройство"
            return
        }
        let requestData: [String: String] = [
            "device_id": deviceID,
            "license_code": code
        ]
        
        guard let jsonData = try? JSONEncoder().encode(requestData) else {
            isValidating = false
            validationError = "Не удалось подготовить запрос"
            return
        }
        
        var request = URLRequest(url: URL(string: serverURL)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isValidating = false
                
                if let error = error {
                    self?.validationError = "Error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.validationError = "Данные с сервера не получены"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(AuthResponse.self, from: data)
                    
                    if response.status == 200 {
                        UserDefaults.standard.set(response.expiration_date, forKey: self?.authDeadlineKey ?? "")
                        self?.isAuthValid = true
                        self?.showAuthSheet = false
                        self?.shouldDismissSheet = true
                    } else if let detail = response.detail {
                        self?.validationError = detail
                    } else {
                        self?.validationError = "Аккаунта нету"
                    }
                } catch {
                    self?.validationError = "Не удалось обработать ответ сервера"
                }
            }
        }.resume()
    }
}
