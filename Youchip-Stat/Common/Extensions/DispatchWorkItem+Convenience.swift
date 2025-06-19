//
//  DispatchWorkItem+Convenience.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import AVFoundation

extension DispatchWorkItem {
    
    private static var previousItem: DispatchWorkItem?
    
    static func cancelPreviousAndScheduleNew(after delay: TimeInterval = 0.1, action: @escaping () -> Void) {
        previousItem?.cancel()
        let newItem = DispatchWorkItem(block: action)
        previousItem = newItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newItem)
    }
    
}
