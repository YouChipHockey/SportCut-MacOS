//
//  Date+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 26.06.2024.
//

import Foundation

extension Date {
    
    func formattedString() -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        if calendar.isDateInToday(self) {
            return "Today, \(dateFormatter.string(from: self))"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday, \(dateFormatter.string(from: self))"
        } else {
            dateFormatter.dateFormat = "d MMMM"
            let datePart = dateFormatter.string(from: self)
            dateFormatter.dateFormat = "HH:mm"
            let timePart = dateFormatter.string(from: self)
            return "\(datePart), \(timePart)"
        }
    }
    
    func dateFormattedString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        dateFormatter.dateFormat = "d MMMM"
        let datePart = dateFormatter.string(from: self)
        dateFormatter.dateFormat = "HH:mm"
        let timePart = dateFormatter.string(from: self)
        return "\(datePart), \(timePart)"
    }
    
}
