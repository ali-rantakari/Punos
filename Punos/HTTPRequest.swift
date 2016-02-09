//
//  HTTPRequest.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation
import GCDWebServers


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
}


internal extension HTTPRequest {
    
    init(_ request: GCDWebServerRequest) {
        self.path = request.path != nil ? request.path : ""
        self.method = request.method != nil ? request.method : ""
        self.query = (request.query as? [String:String]) ?? [:]
        self.headers = (request.headers as? [String:String]) ?? [:]
        
        if let dataRequest = request as? GCDWebServerDataRequest {
            self.data = dataRequest.data
        } else {
            self.data = nil
        }
    }
}
