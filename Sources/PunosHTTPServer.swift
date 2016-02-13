//
//  PunosHTTPServer.swift
//  Punos
//
//  Created by Ali Rantakari on 13.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//
//  This implementation is based on:
//  Swifter by Damian Kołakowski -- https://github.com/glock45/swifter
//  GCDWebServer by Pierre-Olivier Latour -- https://github.com/swisspol/GCDWebServer
//

import Foundation


class PunosHTTPServer {
    
    let queue: dispatch_queue_t
    
    init(queue: dispatch_queue_t) {
        self.queue = queue
    }
    
    private func log(message: String) {
        debugPrint(message)
    }
    
    private let sourceGroup = dispatch_group_create()
    private var dispatchSource: dispatch_source_t?
    
    private func createDispatchSource(listeningSocket: Socket) -> dispatch_source_t {
        let listeningSocketFD = listeningSocket.socketFileDescriptor
        dispatch_group_enter(sourceGroup)
        let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(listeningSocketFD), 0, queue)
        
        dispatch_source_set_cancel_handler(source) { _ in
            if Socket.release(listeningSocketFD) != 0 {
                self.log("Failed to close listening socket \(listeningSocketFD): \(Socket.descriptionOfLastError())")
            } else {
                self.log("Closed listening socket \(listeningSocketFD)")
            }
            dispatch_group_leave(self.sourceGroup)
        }
        
        dispatch_source_set_event_handler(source) { _ in
            autoreleasepool {
                do {
                    let clientSocket = try listeningSocket.acceptClientSocket()
                    dispatch_async(self.queue) {
                        self.handleConnection(clientSocket)
                    }
                } catch let error {
                    self.log("Failed to accept socket. Error: \(error)")
                }
            }
        }
        
        return source
    }
    
    func start(listenPort: in_port_t) throws {
        dispatchSource = createDispatchSource(try Socket.tcpSocketForListen(listenPort))
        guard let source = dispatchSource else {
            throw punosError(0, "Could not create dispatch source")
        }
        dispatch_resume(source)
    }
    
    func stop() {
        if let source = dispatchSource {
            dispatch_source_cancel(source)
        }
        
        // Wait until the cancellation handlers have been called which
        // guarantees the listening sockets are closed
        dispatch_group_wait(sourceGroup, DISPATCH_TIME_FOREVER)
    }
    
    var responder: ((HttpRequest, (HttpResponse) -> Void) -> Void)?
    var defaultResponse = HttpResponse(200, "OK", nil, { writer in writer.write([])})
    
    private func respondToRequestAsync(request: HttpRequest, responseCallback: (HttpResponse) -> Void) {
        if let responder = responder {
            responder(request, responseCallback)
        } else {
            responseCallback(defaultResponse)
        }
    }
    
    private func handleConnection(socket: Socket) {
        let address = try? socket.peername()
        let parser = HttpParser()
        
        func handleNextRequest() {
            guard let request = try? parser.readHttpRequest(socket) else {
                return
            }
            
            request.address = address
            let clientSupportsKeepAlive = parser.supportsKeepAlive(request.headers)
            
            self.respondToRequestAsync(request) { response in
                do {
                    let keepConnection = try self.respond(socket, response: response, keepAlive: clientSupportsKeepAlive)
                    if keepConnection {
                        handleNextRequest()
                    } else {
                        socket.release()
                    }
                } catch {
                    print("Failed to send response: \(error)")
                    socket.release()
                    return
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
        
        if 0 <= content.length {
            try socket.writeUTF8("Content-Length: \(content.length)\r\n")
        }
        
        let respondKeepAlive = keepAlive && content.length != -1
        if respondKeepAlive {
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
        
        return respondKeepAlive
    }
}
