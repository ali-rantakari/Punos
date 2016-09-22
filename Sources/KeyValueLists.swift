//
//  KeyValueLists.swift
//  Punos
//
//  Created by Ali Rantakari on 23/06/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


/// A list of string key-value pairs.
///
public protocol KeyValueList {
    var pairs: [(String,String)] { get }
    init(pairs: [(String,String)])
    init(arrayLiteral elements: (String,String)...)
}

public extension KeyValueList {
    
    // ------------------------------
    // MARK: Literal convertibles
    
    public init(arrayLiteral elements: (String,String)...) {
        self.init(pairs: elements)
    }

    public init(dictionaryLiteral elements: (String,String)...) {
        self.init(pairs: elements)
    }
    
    public init(_ name: String, _ value: String) {
        self.init(pairs: [(name, value)])
    }
    
    public init(_ dictionary: [String:String]) {
        var p = [(String,String)]()
        for (k,v) in dictionary {
            p.append((k,v))
        }
        self.init(pairs: p)
    }
    
    // ------------------------------
    // MARK: Utilities
    
    subscript(index: String) -> String? {
        get {
            for (k,v) in pairs {
                if k == index {
                    return v
                }
            }
            return nil
        }
    }
    
    public var dictionary: [String:String] {
        var dict = [String:String]()
        for (k,v) in pairs {
            dict[k] = v
        }
        return dict
    }
    
    func contains(name: String) -> Bool {
        return pairs.map { $0.0.lowercased() }.contains(name.lowercased())
    }
    
    func merged(_ other: KeyValueList?) -> Self {
        var p = pairs
        if let o = other {
            p.append(contentsOf: o.pairs)
        }
        return Self(pairs: p)
    }
    
    var keys: [String] {
        return pairs.map { $0.0 }
    }
}


/// A list of HTTP headers
///
public struct HTTPHeaders: KeyValueList, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral {
    public let pairs: [(String,String)]
    public init(pairs: [(String,String)]) {
        self.pairs = pairs
    }
}


/// A list of URL query parameters
///
public struct URLQueryParameters: KeyValueList, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral {
    public let pairs: [(String,String)]
    public init(pairs: [(String,String)]) {
        self.pairs = pairs
    }
}

