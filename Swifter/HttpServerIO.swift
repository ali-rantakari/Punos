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
    
    private var listenSocket: Socket = Socket(socketFileDescriptor: -1)
    private var clientSockets: Set<Socket> = []
    private let clientSocketsLock = NSLock()
    private let queue: dispatch_queue_t
    
    init(queue: dispatch_queue_t) {
        self.queue = queue
    }
    
    internal func start(listenPort: in_port_t = 8080) throws {
        stop()
        listenSocket = try Socket.tcpSocketForListen(listenPort)
        dispatch_async(self.queue) {
            while let socket = try? self.listenSocket.acceptClientSocket() {
                self.lock(self.clientSocketsLock) {
                    self.clientSockets.insert(socket)
                }
                dispatch_async(self.queue, {
                    self.handleConnection(socket)
                    self.lock(self.clientSocketsLock) {
                        self.clientSockets.remove(socket)
                    }
                })
            }
            self.stop()
        }
    }
    
    internal func stop() {
        listenSocket.release()
        lock(self.clientSocketsLock) {
            for socket in self.clientSockets {
                socket.shutdwn()
            }
            self.clientSockets.removeAll(keepCapacity: true)
        }
    }
    
    internal func dispatch(method: String, path: String) -> ([String: String], HttpRequest -> HttpResponse) {
        return ([:], { _ in HttpResponse(404, "Not Found", nil, nil) })
    }
    
    private func handleConnection(socket: Socket) {
        let address = try? socket.peername()
        let parser = HttpParser()
        while let request = try? parser.readHttpRequest(socket) {
            let request = request
            let (params, handler) = self.dispatch(request.method, path: request.path)
            request.address = address
            request.params = params;
            let response = handler(request)
            var keepConnection = parser.supportsKeepAlive(request.headers)
            do {
                keepConnection = try self.respond(socket, response: response, keepAlive: keepConnection)
            } catch {
                print("Failed to send response: \(error)")
                break
            }
            if !keepConnection { break }
        }
        socket.release()
    }
    
    private func lock(handle: NSLock, closure: () -> ()) {
        handle.lock()
        closure()
        handle.unlock();
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
