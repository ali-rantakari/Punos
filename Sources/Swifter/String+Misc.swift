//
//  String+Misc.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

extension String {

    internal func split(_ separator: Character) -> [String] {
        return self.split { $0 == separator }.map(String.init)
    }
    
    internal func split(_ maxSplit: Int = Int.max, separator: Character) -> [String] {
        return self.split(maxSplits: maxSplit) { $0 == separator }.map(String.init)
    }
    
    internal func replace(_ old: Character, _ new: Character) -> String {
        var buffer = [Character]()
        forEach { buffer.append($0 == old ? new : $0) }
        return String(buffer)
    }
    
    internal func unquote() -> String {
        var scalars = unicodeScalars
        if scalars.first == "\"" && scalars.last == "\"" && scalars.count >= 2 {
            scalars.removeFirst()
            scalars.removeLast()
            return String(scalars)
        }
        return self
    }
    
    internal var trimmed: String {
        return trimmingCharacters(in: CharacterSet.whitespaces)
    }
    
    internal static func fromUInt8(_ array: [UInt8]) -> String {
        return String(data: Data(bytes: UnsafePointer<UInt8>(array), count: array.count), encoding: String.Encoding.utf8) ?? ""
    }
}
