//
//  Fonts.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 04.06.2024.
//

import SwiftUI

extension Font {
    
    static func sFProText(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProText-Regular", size: size)
    }
    
    static func sFProTextMedium(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProText-Medium", size: size)
    }
    
    static func sFProTextSemibold(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProText-Semibold", size: size)
    }
    
    static func sFProTextBold(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProText-Bold", size: size)
    }
    
    static func sFProDisplay(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProDisplay-Regular", size: size)
    }
    
    static func sFProDisplaySemibold(ofSize size: CGFloat) -> Font {
        return Font.custom("sFProDisplay-Semibold", size: size)
    }
    
    static func sFProDisplayBold(ofSize size: CGFloat) -> Font {
        return Font.custom("SFProDisplay-Bold", size: size)
    }
    
}

