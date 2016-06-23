//
//  Utils.swift
//  Punos
//
//  Created by Ali Rantakari on 10/02/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation

func punosError(_ code: Int, _ description: String) -> NSError {
    return NSError(domain: "org.hasseg.Punos", code: code, userInfo: [NSLocalizedDescriptionKey: description])
}

extension TimeInterval {
    var asDispatchTimeInterval: DispatchTimeInterval {
        return DispatchTimeInterval.milliseconds(Int(self * 1000))
    }
}

extension DispatchQueue {
    func after(interval: TimeInterval, execute work: @convention(block) () -> Swift.Void) {
        after(walltime: DispatchWallTime.now() + interval.asDispatchTimeInterval, execute: work)
    }
}

@discardableResult
func lock<T>(_ lockObject: Lock, fn: @noescape () -> T) -> T {
    lockObject.lock()
    let ret = fn()
    lockObject.unlock()
    return ret
}

extension Dictionary {
    
    /// Returns a copy of `self`, adding the key-value pairs
    /// from `other`, overwriting existing entries if necessary.
    ///
    func merged(_ other: Dictionary?) -> Dictionary {
        guard let other = other else { return self }
        var copy = self
        for (k, v) in other {
            copy.updateValue(v, forKey: k)
        }
        return copy
    }
}
