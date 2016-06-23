//
//  HTTPHeaders.swift
//  Punos
//
//  Created by Ali Rantakari on 23/06/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


/// A list of HTTP headers
///
public struct HTTPHeaders: DictionaryLiteralConvertible, ArrayLiteralConvertible {
    public let pairs: [(String,String)]
    
    public init(pairs: [(String,String)]) {
        self.pairs = pairs
    }
    
    public init(_ name: String, _ value: String) {
        self.pairs = [(name, value)]
    }
    
    public init(_ dictionary: [String:String]) {
        var p = [(String,String)]()
        for (k,v) in dictionary {
            p.append((k,v))
        }
        self.pairs = p
    }
    
    // ------------------------------
    // MARK: Literal convertibles
    
    public init(dictionaryLiteral elements: (String,String)...) {
        self.pairs = elements
    }
    
    public init(arrayLiteral elements: (String,String)...) {
        self.pairs = elements
    }
    
    // ------------------------------
    // MARK: Utilities
    
    func contains(name: String) -> Bool {
        return pairs.map { $0.0.lowercased() }.contains(name.lowercased())
    }
    
    func merged(_ other: HTTPHeaders?) -> HTTPHeaders {
        var p = pairs
        if let o = other {
            p.append(contentsOf: o.pairs)
        }
        return HTTPHeaders(pairs: p)
    }
}
