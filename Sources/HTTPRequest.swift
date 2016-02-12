//
//  HTTPRequest.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation
import Swifter


/// An HTTP request sent to the `MockServer`.
///
public struct HTTPRequest {
    
    /// The path component of the request URL
    let path: String
    
    /// The HTTP method
    let method: String
    
    /// The query parameters
    let query: [String:String]
    
    /// The HTTP headers
    let headers: [String:String]
    
    /// The body data
    let data: NSData?
    
    /// The HTTP method and path, separated by a 
    /// space. E.g. `"GET /foo/bar"`
    var endpoint: String {
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
