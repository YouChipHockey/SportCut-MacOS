//
//  NSImage+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 26.06.2024.
//

import SwiftUI

extension NSImage {
    
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    func flipped() -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let flippedImage = NSImage(size: self.size)
        
        flippedImage.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            return nil
        }
        
        context.translateBy(x: 0, y: self.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: self.size))
        
        flippedImage.unlockFocus()
        
        return flippedImage
    }
    
    func toCGImage() -> CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    
}
