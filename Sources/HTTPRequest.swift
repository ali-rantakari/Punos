//
//  HTTPRequest.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


/// An HTTP request sent to the `MockServer`.
///
public struct HTTPRequest {
    
    /// The path component of the request URL
    public let path: String
    
    /// The HTTP method
    public let method: String
    
    /// The query parameters
    public let query: [String:String]
    
    /// The HTTP headers
    public let headers: [String:String]
    
    /// The body data
    public let data: NSData?
    
    /// The HTTP method and path, separated by a 
    /// space. E.g. `"GET /foo/bar"`
    public var endpoint: String {
        return "\(method) \(path)"
    }
}


private func pathWithoutQueryOrAnchor(path: String) -> String {
    let nsString = path as NSString
    
    let queryIndex = nsString.rangeOfString("?").location
    if queryIndex != NSNotFound {
        return nsString.substringToIndex(queryIndex)
    }
    
    return path
}

private func headersWithCapitalizedNames(headers: [String:String]) -> [String:String] {
    var ret = [String:String]()
    for (k, v) in headers {
        ret[k.capitalizedString] = v
    }
    return ret
}

internal extension HTTPRequest {
    
    init(_ request: HttpRequest) {
        self.path = pathWithoutQueryOrAnchor(request.path)
        self.method = request.method
        self.headers = headersWithCapitalizedNames(request.headers)
        
        var q = [String:String]()
        for (k, v) in request.queryParams {
            q[k] = v
        }
        self.query = q
        
        let bytes = request.body
        self.data = NSData(bytes: bytes, length: bytes.count)
    }
}
