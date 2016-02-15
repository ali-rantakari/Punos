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

typealias Logger = String -> Void

class PunosHTTPServer {
    
    let queue: dispatch_queue_t
    private let log: Logger
    
    init(queue: dispatch_queue_t, logger: Logger = { _ in }) {
        self.log = logger
        self.queue = queue
    }
    
    private var sourceGroup: dispatch_group_t?
    private var dispatchSource: dispatch_source_t?
    
    private var clientSockets: Set<Socket> = []
    private let clientSocketsLock = NSLock()
    
    private func createDispatchSource(listeningSocket: Socket) -> dispatch_source_t? {
        guard let sourceGroup = sourceGroup else { return nil }
        
        let listeningSocketFD = listeningSocket.socketFileDescriptor
        dispatch_group_enter(sourceGroup)
        let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(listeningSocketFD), 0, queue)
        
        dispatch_source_set_cancel_handler(source) { _ in
            if Socket.release(listeningSocketFD) != 0 {
                self.log("Failed to close listening socket \(listeningSocketFD): \(Socket.descriptionOfLastError())")
            } else {
                self.log("Closed listening socket \(listeningSocketFD)")
            }
            dispatch_group_leave(sourceGroup)
        }
        
        dispatch_source_set_event_handler(source) { _ in
            autoreleasepool {
                do {
                    let clientSocket = try listeningSocket.acceptClientSocket()
                    
                    lock(self.clientSocketsLock) {
                        self.clientSockets.insert(clientSocket)
                    }
                    
                    dispatch_async(self.queue) {
                        self.handleConnection(clientSocket) {
                            lock(self.clientSocketsLock) {
                                self.clientSockets.remove(clientSocket)
                            }
                        }
                    }
                } catch let error {
                    self.log("Failed to accept socket. Error: \(error)")
                }
            }
        }
        
        self.log("Started dispatch source for listening socket \(listeningSocketFD)")
        return source
    }
    
    func start(listenPort: in_port_t) throws {
        if dispatchSource != nil {
            throw punosError(0, "Already running")
        }
        sourceGroup = dispatch_group_create()
        dispatchSource = createDispatchSource(try Socket.tcpSocketForListen(listenPort))
        guard let source = dispatchSource else {
            throw punosError(0, "Could not create dispatch source")
        }
        dispatch_resume(source)
    }
    
    func stop() {
        guard let source = dispatchSource, group = sourceGroup else {
            return
        }
        
        // These properties are our implicit "are we running" state:
        //
        self.dispatchSource = nil
        self.sourceGroup = nil
        
        // Shut down all the client sockets, so that our dispatch
        // source can be cancelled:
        //
        for socket in self.clientSockets {
            socket.shutdwn()
        }
        self.clientSockets.removeAll(keepCapacity: true)
        
        // Cancel the main listening socket dispatch source (the
        // cancellation handler is responsible for closing the
        // socket):
        //
        dispatch_source_cancel(source)
        
        // Wait until the cancellation handler has been called, which
        // guarantees that the listening socket is closed:
        //
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
    }
    
    var responder: ((HttpRequest, (HttpResponse) -> Void) -> Void)?
    var defaultResponse = HttpResponse(200, "OK", nil, nil)
    
    private func respondToRequestAsync(request: HttpRequest, responseCallback: (HttpResponse) -> Void) {
        if let responder = responder {
            responder(request, responseCallback)
        } else {
            responseCallback(defaultResponse)
        }
    }
    
    private func handleConnection(socket: Socket, doneCallback: () -> Void) {
        let parser = HttpParser()
        
        guard let request = try? parser.readHttpRequest(socket) else {
            socket.release()
            doneCallback()
            return
        }
        
        request.address = try? socket.peername()
        
        self.respondToRequestAsync(request) { response in
            do {
                try self.respond(socket, response: response, keepAlive: false)
            } catch {
                print("Failed to send response: \(error)")
            }
            socket.release()
            doneCallback()
        }
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
        try socket.writeUTF8AndCRLF("HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)")
        
        let content = response.content
        
        if 0 <= content.length {
            try socket.writeUTF8AndCRLF("Content-Length: \(content.length)")
        }
        
        let respondKeepAlive = keepAlive && content.length != -1
        if respondKeepAlive {
            try socket.writeUTF8AndCRLF("Connection: keep-alive")
        }
        
        for (name, value) in response.headers {
            try socket.writeUTF8AndCRLF("\(name): \(value)")
        }
        
        try socket.writeUTF8AndCRLF("")
        
        if let writeClosure = content.write {
            let context = InnerWriteContext(socket: socket)
            try writeClosure(context)
        }
        
        return respondKeepAlive
    }
}
