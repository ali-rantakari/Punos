//
//  Utils.swift
//  Punos
//
//  Created by Ali Rantakari on 10/02/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation

func dispatchAfterInterval(interval: NSTimeInterval, queue: dispatch_queue_t, block: () -> Void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(interval * Double(NSEC_PER_SEC))), queue, block);
}

extension Dictionary {
    
    /// Returns a copy of `self`, adding the key-value pairs
    /// from `other`, overwriting existing entries if necessary.
    ///
    func merged(other: Dictionary?) -> Dictionary {
        guard let other = other else { return self }
        var copy = self
        for (k, v) in other {
            copy.updateValue(v, forKey: k)
        }
        return copy
    }
}
