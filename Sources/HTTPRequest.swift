//
//  HTTPRequest.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


/// An HTTP request sent to a `MockHTTPServer`.
///
public struct HTTPRequest {
    
    /// The path component of the request URL
    public let path: String
    
    /// The HTTP method
    public let method: String
    
    /// The query parameters
    public let query: URLQueryParameters
    
    /// The HTTP headers
    public let headers: HTTPHeaders
    
    /// The body data
    public let data: Data?
    
    /// The HTTP method and path, separated by a 
    /// space. E.g. `"GET /foo/bar"`
    public var endpoint: String {
        return "\(method) \(path)"
    }
}
