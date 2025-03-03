//
//  PreferenceManager.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 13.06.2024.
//

import Foundation

class PreferenceManager<Key: RawRepresentable>: NSObject {
    
    private let userDefaults = UserDefaults.standard
    
    func register(_ defaults: [String: Any]) {
        userDefaults.register(defaults: defaults)
    }
    
    func string(for key: Key) -> String {
        return userDefaults.string(forKey: key.rawValue as! String) ?? ""
    }
    
    func setString(_ string: String, for key: Key) {
        userDefaults.setValue(string, forKey: key.rawValue as! String)
    }
    
    func bool(for key: Key) -> Bool {
        return userDefaults.bool(forKey: key.rawValue as! String)
    }
    
    func setBool(_ bool: Bool, for key: Key) {
        userDefaults.setValue(bool, forKey: key.rawValue as! String)
    }
    
    func float(for key: Key) -> Float {
        return userDefaults.float(forKey: key.rawValue as! String)
    }
    
    func setFloat(_ float: Float, for key: Key) {
        userDefaults.setValue(float, forKey: key.rawValue as! String)
    }
    
    func double(for key: Key) -> Double {
        return userDefaults.double(forKey: key.rawValue as! String)
    }
    
    func setDouble(_ double: Double, for key: Key) {
        userDefaults.setValue(double, forKey: key.rawValue as! String)
    }
    
    func integer(for key: Key) -> Int {
        return userDefaults.integer(forKey: key.rawValue as! String)
    }
    
    func setInteger(_ int: Int, for key: Key) {
        userDefaults.setValue(int, forKey: key.rawValue as! String)
    }
    
    func object(for key: Key) -> Any? {
        return userDefaults.object(forKey: key.rawValue as! String)
    }
    
    func setObject(_ object: Any, for key: Key) {
        userDefaults.setValue(object, forKey: key.rawValue as! String)
    }
    
    func removeObjectForKey(_ key: Key) {
        userDefaults.removeObject(forKey: key.rawValue as! String)
    }
    
    func stringArray(for key: Key) -> [String] {
        let keyString = key.rawValue as? String
        return userDefaults.object(forKey: keyString!) as? [String] ?? []
    }
    
    func setStringArray(_ array: [String], for key: Key) {
        let keyString = key.rawValue as? String
        userDefaults.setValue(array, forKey: keyString!)
    }
    
}
