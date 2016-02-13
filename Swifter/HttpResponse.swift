//
//  HttpResponse.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

internal protocol HttpResponseBodyWriter {
    func write(data: [UInt8])
}

internal struct HttpResponse {
    
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String:String]
    let content: (length: Int, write: (HttpResponseBodyWriter throws -> Void)?)
    
    init(_ statusCode: Int, _ reasonPhrase: String, _ headers: [String:String]?, _ write: (HttpResponseBodyWriter throws -> Void)?) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers ?? [:]
        self.content = (-1, write)
    }
}
