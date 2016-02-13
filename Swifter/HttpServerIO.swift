//
//  HttpServer.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

#if os(Linux)
    import Glibc
    import NSLinux
#endif

internal class HttpServerIO {
    
    let queue: dispatch_queue_t
    
    init(queue: dispatch_queue_t) {
        self.queue = queue
    }
    
    internal func respondToRequestAsync(request: HttpRequest, responseCallback: (HttpResponse) -> Void) {
        responseCallback(HttpResponse(404, "Not Found", nil, nil))
    }
    
    internal func handleConnection(socket: Socket) {
        let address = try? socket.peername()
        let parser = HttpParser()
        
        func handleNextRequest() {
            if let request = try? parser.readHttpRequest(socket) {
                let request = request
                request.address = address
                var keepConnection = parser.supportsKeepAlive(request.headers)
                
                self.respondToRequestAsync(request) { response in
                    do {
                        keepConnection = try self.respond(socket, response: response, keepAlive: keepConnection)
                    } catch {
                        print("Failed to send response: \(error)")
                        socket.release()
                        return
                    }
                    if keepConnection {
                        handleNextRequest()
                    } else {
                        socket.release()
                    }
                }
            }
        }
        
        handleNextRequest()
    }
    
    private struct InnerWriteContext: HttpResponseBodyWriter {
        let socket: Socket
        func write(data: [UInt8]) {
            do {
                try socket.writeUInt8(data)
            } catch {
                print("\(error)")
            }
        }
    }
    
    private func respond(socket: Socket, response: HttpResponse, keepAlive: Bool) throws -> Bool {
        try socket.writeUTF8("HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)\r\n")
        
        let content = response.content
        
        if content.length >= 0 {
            try socket.writeUTF8("Content-Length: \(content.length)\r\n")
        }
        
        if keepAlive && content.length != -1 {
            try socket.writeUTF8("Connection: keep-alive\r\n")
        }
        
        for (name, value) in response.headers {
            try socket.writeUTF8("\(name): \(value)\r\n")
        }
        
        try socket.writeUTF8("\r\n")
    
        if let writeClosure = content.write {
            let context = InnerWriteContext(socket: socket)
            try writeClosure(context)
        }
        
        return keepAlive && content.length != -1;
    }
}
