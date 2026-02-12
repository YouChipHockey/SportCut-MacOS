//
//  KeychainHelper.swift
//  Youchip-Stat
//
//  Created on 12.02.2026.
//

import Foundation
import Security

/// Helper class for working with Keychain
class KeychainHelper {
    
    static let shared = KeychainHelper()
    
    private let service: String
    
    private init() {
        // Use bundle identifier as service name
        self.service = Bundle.main.bundleIdentifier ?? "com.youchip.stat"
    }
    
    /// Saves a boolean value to Keychain
    /// - Parameters:
    ///   - value: Boolean value to save
    ///   - key: Key identifier
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func saveBool(_ value: Bool, forKey key: String) -> Bool {
        let data = (value ? "true" : "false").data(using: .utf8)!
        return save(data, forKey: key)
    }
    
    /// Retrieves a boolean value from Keychain
    /// - Parameter key: Key identifier
    /// - Returns: Boolean value if found, nil otherwise
    func getBool(forKey key: String) -> Bool? {
        guard let data = get(forKey: key),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string == "true"
    }
    
    /// Saves a string value to Keychain
    /// - Parameters:
    ///   - value: String value to save
    ///   - key: Key identifier
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func saveString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        return save(data, forKey: key)
    }
    
    /// Retrieves a string value from Keychain
    /// - Parameter key: Key identifier
    /// - Returns: String value if found, nil otherwise
    func getString(forKey key: String) -> String? {
        guard let data = get(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Deletes a value from Keychain
    /// - Parameter key: Key identifier
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Private Methods
    
    private func save(_ data: Data, forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item if it exists
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func get(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
}
