//
//  BaseServer.swift
//  Punos
//
//  Created by Ali Rantakari on 13.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


class BaseServer: HttpServerIO {
    
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
                    Socket.setNoSigPipe(clientSocket.socketFileDescriptor)
                    self.handleConnection(clientSocket)
                    Socket.release(clientSocket.socketFileDescriptor)
                } catch let error {
                    self.log("Failed to accept socket. Error: \(error)")
                }
            }
        }
        
        return source
    }
    
    override func start(listenPort: in_port_t) throws {
        dispatchSource = createDispatchSource(try Socket.tcpSocketForListen(listenPort))
        guard let source = dispatchSource else {
            throw punosError(0, "Could not create dispatch source")
        }
        dispatch_resume(source)
    }
    
    override func stop() {
        if let source = dispatchSource {
            dispatch_source_cancel(source)
        }
        
        // Wait until the cancellation handlers have been called which
        // guarantees the listening sockets are closed
        dispatch_group_wait(sourceGroup, DISPATCH_TIME_FOREVER)
    }
}
