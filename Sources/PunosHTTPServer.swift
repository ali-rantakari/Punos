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

typealias Logger = (String) -> Void

class PunosHTTPServer {
    
    let queue: DispatchQueue
    private let log: Logger
    
    init(queue: DispatchQueue, logger: Logger = { _ in }) {
        self.log = logger
        self.queue = queue
    }
    
    private var sourceGroup: DispatchGroup?
    private var dispatchSource: DispatchSourceType?
    
    private var clientSockets: Set<Socket> = []
    private let clientSocketsLock = Lock()
    
    private func createDispatchSource(_ listeningSocket: Socket) -> DispatchSourceType? {
        guard let sourceGroup = sourceGroup else { return nil }
        
        let listeningSocketFD = listeningSocket.socketFileDescriptor
        sourceGroup.enter()
        let source = DispatchSource.read(fileDescriptor: listeningSocketFD, queue: queue)
        
        source.setCancelHandler { _ in
            do {
                try Socket.release(listeningSocketFD)
                self.log("Closed listening socket \(listeningSocketFD)")
            } catch (let error) {
                self.log("Failed to close listening socket \(listeningSocketFD): \(error)")
            }
            sourceGroup.leave()
        }
        
        source.setEventHandler { _ in
            autoreleasepool {
                do {
                    let clientSocket = try listeningSocket.acceptClientSocket()
                    
                    self.clientSocketsLock.with {
                        self.clientSockets.insert(clientSocket)
                    }
                    
                    self.queue.async {
                        self.handleConnection(clientSocket) {
                            self.clientSocketsLock.with {
                                self.clientSockets.remove(clientSocket)
                            }
                        }
                    }
                } catch let error {
                    self.log("Failed to accept socket. Error: \(error)")
                }
            }
        }
        
        log("Started dispatch source for listening socket \(listeningSocketFD)")
        return source
    }
    
    private(set) var port: in_port_t?
    
    func start(portsToTry: [in_port_t]) throws {
        if dispatchSource != nil {
            throw punosError(0, "Already running")
        }
        
        var maybeSocket: Socket? = nil
        for port in portsToTry {
            log("Attempting to bind to port \(port)")
            do {
                maybeSocket = try Socket.tcpSocketForListen(port)
            } catch let error {
                if case SocketError.bindFailedAddressAlreadyInUse(_) = error {
                    continue
                }
                throw error
            }
            self.port = port
            break
        }
        
        guard let socket = maybeSocket else {
            throw punosError(0, "Could not bind to any given port")
        }
        
        sourceGroup = DispatchGroup()
        dispatchSource = createDispatchSource(socket)
        
        guard let source = dispatchSource else {
            throw punosError(0, "Could not create dispatch source")
        }
        source.resume()
    }
    
    func stop() {
        guard let source = dispatchSource, group = sourceGroup else {
            return
        }
        
        // These properties are our implicit "are we running" state:
        //
        dispatchSource = nil
        sourceGroup = nil
        
        // Shut down all the client sockets, so that our dispatch
        // source can be cancelled:
        //
        for socket in clientSockets {
            socket.shutdown()
        }
        clientSockets.removeAll(keepingCapacity: true)
        
        // Cancel the main listening socket dispatch source (the
        // cancellation handler is responsible for closing the
        // socket):
        //
        source.cancel()
        
        // Wait until the cancellation handler has been called, which
        // guarantees that the listening socket is closed:
        //
        _ = group.wait(timeout: DispatchTime.distantFuture)
        
        port = nil
    }
    
    var responder: ((HTTPRequest, (HttpResponse) -> Void) -> Void)?
    var defaultResponse = HttpResponse(200, nil, nil)
    
    private func respondToRequestAsync(_ request: HTTPRequest, responseCallback: (HttpResponse) -> Void) {
        if let responder = responder {
            responder(request, responseCallback)
        } else {
            responseCallback(defaultResponse)
        }
    }
    
    private func handleConnection(_ socket: Socket, doneCallback: () -> Void) {
        guard let request = try? readHttpRequest(socket) else {
            socket.releaseIgnoringErrors()
            doneCallback()
            return
        }
        
        respondToRequestAsync(request) { response in
            do {
                _ = try self.respond(socket, response: response, keepAlive: false)
            } catch {
                self.log("Failed to send response: \(error)")
            }
            socket.releaseIgnoringErrors()
            doneCallback()
        }
    }
    
    private struct InnerWriteContext: HttpResponseBodyWriter {
        let socket: Socket
        let log: Logger
        func write(_ data: [UInt8]) {
            do {
                try socket.writeUInt8(data)
            } catch {
                log("Error writing to socket \(socket.socketFileDescriptor): \(error)")
            }
        }
    }
    
    private func respond(_ socket: Socket, response: HttpResponse, keepAlive: Bool) throws -> Bool {
        try socket.writeUTF8AndCRLF("HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)")
        
        let content = response.content
        
        if 0 <= content.length {
            try socket.writeUTF8AndCRLF("Content-Length: \(content.length)")
        }
        
        let respondKeepAlive = keepAlive && content.length != -1
        if !response.containsHeader("Connection") { // Allow the response to override this
            if respondKeepAlive {
                try socket.writeUTF8AndCRLF("Connection: keep-alive")
            } else {
                try socket.writeUTF8AndCRLF("Connection: close")
            }
        }
        
        for (name, value) in response.headers {
            try socket.writeUTF8AndCRLF("\(name): \(value)")
        }
        
        try socket.writeUTF8AndCRLF("")
        
        if let writeClosure = content.write {
            let context = InnerWriteContext(socket: socket, log: log)
            try writeClosure(context)
        }
        
        return respondKeepAlive
    }
}
