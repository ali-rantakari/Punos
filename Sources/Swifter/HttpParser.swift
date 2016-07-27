//
//  HttpParser.swift
//  Swifter
// 
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

enum HttpParserError: ErrorProtocol {
    case invalidChunk(String)
    case invalidStatusLine(String)
}

private func pathWithoutQueryOrAnchor(_ path: String) -> String {
    let nsString = path as NSString
    
    let queryIndex = nsString.range(of: "?").location
    if queryIndex != NSNotFound {
        return nsString.substring(to: queryIndex)
    }
    
    return path
}

private func headersWithCapitalizedNames(_ headers: [String:String]) -> [String:String] {
    var ret = [String:String]()
    for (k, v) in headers {
        ret[k.capitalized] = v
    }
    return ret
}

internal func readHttpRequest(_ socket: Socket) throws -> HTTPRequest {
    let statusLine = try socket.readLine()
    let statusLineTokens = statusLine.split(" ")
    if statusLineTokens.count < 3 {
        throw HttpParserError.invalidStatusLine(statusLine)
    }
    let method = statusLineTokens[0]
    let pathLine = statusLineTokens[1]
    let path = pathWithoutQueryOrAnchor(pathLine)
    let queryPairs = extractQueryParams(pathLine)
    var headers = try readHeaders(socket)
    var body: [UInt8]?
    if let contentLength = headers["content-length"], let contentLengthValue = Int(contentLength) {
        body = try readBody(socket, size: contentLengthValue)
    } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
        body = try readChunkedBody(socket)
        // Read potential footers (and consume the blank line at the end):
        let footers = try readHeaders(socket)
        headers = headers.merged(footers)
    }
    
    let data: Data
    if let b = body {
        data = Data(bytes: UnsafePointer<UInt8>(b), count: b.count)
    } else {
        data = Data()
    }
    
    return HTTPRequest(
        path: path,
        method: method,
        queryParameters: URLQueryParameters(pairs: queryPairs),
        headers: HTTPHeaders(headersWithCapitalizedNames(headers)),
        data: data)
}

private func extractQueryParams(_ url: String) -> [(String, String)] {
    guard let query = url.split("?").last else {
        return []
    }
    return query.split("&").reduce([(String, String)]()) { (c, s) -> [(String, String)] in
        let tokens = s.split(1, separator: "=")
        guard 0 < tokens.count else { return c }
        let name = tokens[0]
        let value = 1 < tokens.count ? tokens[1] : ""
        return c + [(name.removingPercentEncoding ?? "", value.removingPercentEncoding ?? "")]
    }
}

private func readBody(_ socket: Socket, size: Int) throws -> [UInt8] {
    return try socket.readNumBytes(size)
}

private func readChunkedBody(_ socket: Socket) throws -> [UInt8] {
    var body = [UInt8]()
    repeat {
        // Read the chunk header, discard `;` and anything after it, and
        // interpret the chunk size, which is expressed in hex:
        //
        let chunkHeaderLine = try socket.readLine()
        if chunkHeaderLine == "0" || chunkHeaderLine.hasPrefix("0;") {
            return body
        }
        let chunkSizeHexString: String = {
            if chunkHeaderLine.contains(";") {
                return chunkHeaderLine.substring(to: chunkHeaderLine.range(of: ";")!.lowerBound)
            }
            return chunkHeaderLine
        }()
        
        guard let chunkSizeBytes = Int(chunkSizeHexString, radix: 16) else {
            throw HttpParserError.invalidChunk("Invalid chunk header line: \(chunkHeaderLine)")
        }
        
        // Read the chunk contents
        //
        body.append(contentsOf: try socket.readNumBytes(chunkSizeBytes))
        
        // Assert that the contents end in CRLF
        //
        if try ((try socket.readOneByte() != Socket.CR) || (try socket.readOneByte() != Socket.NL)) {
            throw HttpParserError.invalidChunk("Chunk does not end in CRLF")
        }
    } while true
}

private func readHeaders(_ socket: Socket) throws -> [String: String] {
    var headers = [String: String]()
    repeat {
        let headerLine = try socket.readLine()
        if headerLine.isEmpty {
            return headers
        }
        let headerTokens = headerLine.split(1, separator: ":")
        if let name = headerTokens.first, let value = headerTokens.last {
            headers[name.lowercased()] = value.trimmed
        }
    } while true
}
