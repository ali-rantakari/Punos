//
//  HttpResponse.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//
//  Modified in 2016 by Ali Rantakari for Punos.
//

import Foundation

internal protocol HttpResponseBodyWriter {
    func write(data: [UInt8])
}

typealias HttpResponseContent = (length: Int, write: (HttpResponseBodyWriter throws -> Void)?)

internal struct HttpResponse {
    
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String:String]
    let content: HttpResponseContent
    
    init(_ statusCode: Int, _ headers: [String:String]?, _ content: HttpResponseContent?) {
        self.statusCode = statusCode
        self.reasonPhrase = RFC2616.reasonsForStatusCodes[statusCode] ?? ""
        self.headers = headers ?? [:]
        self.content = content ?? (-1, nil)
    }
    
    func containsHeader(headerName: String) -> Bool {
        return headers.keys.map { $0.lowercaseString }.contains(headerName.lowercaseString)
    }
}
