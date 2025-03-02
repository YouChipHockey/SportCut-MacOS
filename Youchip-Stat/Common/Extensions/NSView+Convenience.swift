//
//  NSView+Convenience.swift
//  printer
//
//  Created by tpe on 21.08.2024.
//

import TinyConstraints

extension NSView {
    
    func findSplitView() -> NSSplitView? {
        var queue = [NSView]()
        queue.append(self)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current is NSSplitView {
                return current as? NSSplitView
            }
            for subview in current.subviews {
                queue.append(subview)
            }
        }
        return nil
    }
    
}
