//
//  File.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 31.07.2024.
//

import StoreKit

extension SKProduct {
    var priceAsDouble: Double {
        return price.doubleValue
    }
    
    var formattedPriceString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        
        let defaultFractionDigits = formatter.maximumFractionDigits
        
        // Convert price to a double value for comparison
        let priceValue = price.doubleValue
        let isInteger = floor(priceValue) == priceValue
        
        // Adjust fraction digits based on the actual price
        if isInteger {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = defaultFractionDigits
        }
        
        return formatter.string(from: price) ?? ""
    }
    
}

extension SKProductDiscount {
    
    var formattedDiscountString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        
        let defaultFractionDigits = formatter.maximumFractionDigits
        
        // Convert price to a double value for comparison
        let priceValue = price.doubleValue
        let isInteger = floor(priceValue) == priceValue
        
        // Adjust fraction digits based on the actual price
        if isInteger {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = defaultFractionDigits
        }
        
        return formatter.string(from: price) ?? ""
    }
}
