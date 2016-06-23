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

internal class HttpParser {
    
    internal init() { }
    
    internal func readHttpRequest(_ socket: Socket) throws -> HttpRequest {
        let statusLine = try socket.readLine()
        let statusLineTokens = statusLine.split(" ")
        if statusLineTokens.count < 3 {
            throw HttpParserError.invalidStatusLine(statusLine)
        }
        let request = HttpRequest()
        request.method = statusLineTokens[0]
        request.path = statusLineTokens[1]
        request.queryParams = extractQueryParams(request.path)
        request.headers = try readHeaders(socket)
        if let contentLength = request.headers["content-length"], let contentLengthValue = Int(contentLength) {
            request.body = try readBody(socket, size: contentLengthValue)
        } else if request.headers["transfer-encoding"]?.lowercased() == "chunked" {
            request.body = try readChunkedBody(socket)
            // Read potential footers (and consume the blank line at the end):
            let footers = try readHeaders(socket)
            request.headers = request.headers.merged(footers)
        }
        return request
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
            return c + [(name.removePercentEncoding(), value.removePercentEncoding())]
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
            if let name = headerTokens.first, value = headerTokens.last {
                headers[name.lowercased()] = value.trim()
            }
        } while true
    }
    
    func supportsKeepAlive(_ headers: [String: String]) -> Bool {
        if let value = headers["connection"] {
            return "keep-alive" == value.trim()
        }
        return false
    }
}
