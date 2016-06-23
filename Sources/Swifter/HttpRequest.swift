//
//  HttpRequest.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

internal class HttpRequest {
    
    internal var path: String = ""
    internal var queryParams: [(String, String)] = []
    internal var method: String = ""
    internal var headers: [String: String] = [:]
    internal var body: [UInt8] = []
    internal var address: String? = ""
    internal var params: [String: String] = [:]
    
    internal func parseUrlencodedForm() -> [(String, String)] {
        guard let contentTypeHeader = headers["content-type"] else {
            return []
        }
        let contentTypeHeaderTokens = contentTypeHeader.split(";").map { $0.trim() }
        guard let contentType = contentTypeHeaderTokens.first where contentType == "application/x-www-form-urlencoded" else {
            return []
        }
        return String.fromUInt8(body).split("&").map { param -> (String, String) in
            let tokens = param.split("=")
            if let name = tokens.first, value = tokens.last where tokens.count == 2 {
                return (name.replace("+", " ").removingPercentEncoding ?? "",
                        value.replace("+", " ").removingPercentEncoding ?? "")
            }
            return ("","")
        }
    }
    
    internal struct MultiPart {
        
        internal let headers: [String: String]
        internal let body: [UInt8]
        
        internal var name: String? {
            return valueFor("content-disposition", parameter: "name")?.unquote()
        }
        
        internal var fileName: String? {
            return valueFor("content-disposition", parameter: "filename")?.unquote()
        }
        
        private func valueFor(_ headerName: String, parameter: String) -> String? {
            return headers.reduce([String]()) { (combined, header: (key: String, value: String)) -> [String] in
                guard header.key == headerName else {
                    return combined
                }
                let headerValueParams = header.value.split(";").map { $0.trim() }
                return headerValueParams.reduce(combined, combine: { (results, token) -> [String] in
                    let parameterTokens = token.split(1, separator: "=")
                    if parameterTokens.first == parameter, let value = parameterTokens.last {
                        return results + [value]
                    }
                    return results
                })
            }.first
        }
    }
    
    internal func parseMultiPartFormData() -> [MultiPart] {
        guard let contentTypeHeader = headers["content-type"] else {
            return []
        }
        let contentTypeHeaderTokens = contentTypeHeader.split(";").map { $0.trim() }
        guard let contentType = contentTypeHeaderTokens.first where contentType == "multipart/form-data" else {
            return []
        }
        var boundary: String? = nil
        contentTypeHeaderTokens.forEach({
            let tokens = $0.split("=")
            if let key = tokens.first where key == "boundary" && tokens.count == 2 {
                boundary = tokens.last
            }
        })
        if let boundary = boundary where boundary.utf8.count > 0 {
            return parseMultiPartFormData(body, boundary: "--\(boundary)")
        }
        return []
    }
    
    private func parseMultiPartFormData(_ data: [UInt8], boundary: String) -> [MultiPart] {
        var generator = data.makeIterator()
        var result = [MultiPart]()
        while let part = nextMultiPart(&generator, boundary: boundary, isFirst: result.isEmpty) {
            result.append(part)
        }
        return result
    }
    
    private func nextMultiPart(_ generator: inout IndexingIterator<[UInt8]>, boundary: String, isFirst: Bool) -> MultiPart? {
        if isFirst {
            guard nextMultiPartLine(&generator) == boundary else {
                return nil
            }
        } else {
            _ = nextMultiPartLine(&generator)
        }
        var headers = [String: String]()
        while let line = nextMultiPartLine(&generator) where !line.isEmpty {
            let tokens = line.split(":")
            if let name = tokens.first, value = tokens.last where tokens.count == 2 {
                headers[name.lowercased()] = value.trim()
            }
        }
        guard let body = nextMultiPartBody(&generator, boundary: boundary) else {
            return nil
        }
        return MultiPart(headers: headers, body: body)
    }
    
    private func nextMultiPartLine(_ generator: inout IndexingIterator<[UInt8]>) -> String? {
        var result = String()
        while let value = generator.next() {
            if value > HttpRequest.CR {
                result.append(Character(UnicodeScalar(value)))
            }
            if value == HttpRequest.NL {
                break
            }
        }
        return result
    }
    
    static let CR = UInt8(13)
    static let NL = UInt8(10)
    
    private func nextMultiPartBody(_ generator: inout IndexingIterator<[UInt8]>, boundary: String) -> [UInt8]? {
        var body = [UInt8]()
        let boundaryArray = [UInt8](boundary.utf8)
        var matchOffset = 0;
        while let x = generator.next() {
            matchOffset = ( x == boundaryArray[matchOffset] ? matchOffset + 1 : 0 )
            body.append(x)
            if matchOffset == boundaryArray.count {
                body.removeSubrange((body.count-matchOffset)..<body.count)
                if body.last == HttpRequest.NL {
                    body.removeLast()
                    if body.last == HttpRequest.CR {
                        body.removeLast()
                    }
                }
                return body
            }
        }
        return nil
    }
}
