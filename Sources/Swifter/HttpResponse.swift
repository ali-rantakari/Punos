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
    func write(_ data: [UInt8])
}

typealias HttpResponseContent = (length: Int, write: ((HttpResponseBodyWriter) throws -> Void)?)

internal struct HttpResponse {
    
    let statusCode: Int
    let reasonPhrase: String
    let headers: HTTPHeaders
    let content: HttpResponseContent
    
    init(_ statusCode: Int, _ headers: HTTPHeaders?, _ content: HttpResponseContent?) {
        self.statusCode = statusCode
        self.reasonPhrase = RFC2616.reasonsForStatusCodes[statusCode] ?? ""
        self.headers = headers ?? []
        self.content = content ?? (-1, nil)
    }
    
    // TODO: Move to HTTPHeaders
    func containsHeader(_ headerName: String) -> Bool {
        return headers.pairs.map { $0.0.lowercased() }.contains(headerName.lowercased())
    }
}
