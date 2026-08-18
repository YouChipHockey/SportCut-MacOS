//
//  MainLoadJsonFunc.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

func loadJSON<T: Decodable>(filename: String) -> T? {
    guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
        return nil
    }
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let loaded = try decoder.decode(T.self, from: data)
        return loaded
    } catch {
        return nil
    }
}

func loadJSON<T: Decodable>(url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    return try? decoder.decode(T.self, from: data)
}

/// Формат `hh:mm:ss`.
///
/// Собирается вручную, без `String(format:)`: тот идёт через NSString-форматирование и заметно
/// дороже, а функция зовётся из отрисовки линейки времени — до 240 раз на каждый её пересчёт.
/// Вывод побайтово совпадает с прежним `"%02d:%02d:%02d"`. См. TASK-007, 6.3.
func secondsToTimeString(_ seconds: Double) -> String {
    let hours = Int(seconds / 3600)
    let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
    return "\(twoDigits(hours)):\(twoDigits(minutes)):\(twoDigits(secs))"
}

/// Целое в две цифры с ведущим нулём. Для отрицательных и трёхзначных отдаёт обычное
/// десятичное представление — как и `%02d`.
private func twoDigits(_ value: Int) -> String {
    (value >= 0 && value < 10) ? "0\(value)" : "\(value)"
}

func timeStringToSeconds(_ time: String) -> Double {
    let components = time.split(separator: ":").map { Double($0) ?? 0 }
    if components.count == 3 {
        return components[0] * 3600 + components[1] * 60 + components[2]
    } else if components.count == 2 {
        return components[0] * 60 + components[1]
    }
    return 0
}
