//
//  BaseServer.swift
//  Punos
//
//  Created by Ali Rantakari on 13.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation

private func posixNSErrorFromErrno(code: Int32, _ description: String? = nil) -> NSError {
    var d = String(CString: strerror(code), encoding: NSASCIIStringEncoding) ?? "errno \(code)"
    if let description = description {
        d = "\(description) - Error: \(d)"
    }
    return NSError(
        domain: NSPOSIXErrorDomain,
        code: Int(code),
        userInfo: [NSLocalizedDescriptionKey: d])
}

private func ipVersionString(isIPv6: Bool) -> String {
    return isIPv6 ? "IPv6" : "IPv4"
}


class BaseServer: HttpServerIO {
    
    private func log(message: String) {
        debugPrint(message)
    }
    
    private let sourceGroup = dispatch_group_create()
    private var dispatchSource4: dispatch_source_t?
    private var dispatchSource6: dispatch_source_t?
    
    private func createDispatchSource(listeningSocketFD: Int32, isIPv6: Bool) -> dispatch_source_t {
        dispatch_group_enter(sourceGroup)
        let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(listeningSocketFD), 0, queue)
        
        dispatch_source_set_cancel_handler(source) { _ in
            if Socket.release(listeningSocketFD) != 0 {
                self.log(posixNSErrorFromErrno(errno, "Failed to close \(ipVersionString(isIPv6)) listening socket \(listeningSocketFD)").description)
            } else {
                self.log("Closed \(ipVersionString(isIPv6)) listening socket \(listeningSocketFD)")
            }
            dispatch_group_leave(self.sourceGroup)
        }
        
        dispatch_source_set_event_handler(source) { _ in
            autoreleasepool {
                var remoteSockAddr = sockaddr()
                var remoteSockAddrLen: socklen_t = 0
                let clientSocket = accept(listeningSocketFD, &remoteSockAddr, &remoteSockAddrLen)
                guard 0 < clientSocket else {
                    self.log("Failed to accept \(ipVersionString(isIPv6)) socket: \(String(strerror(errno)))")
                    return
                }
                
                Socket.setNoSigPipe(clientSocket)
                
                dispatch_async(self.queue) {
                    self.handleConnection(Socket(socketFileDescriptor: clientSocket))
                    Socket.release(clientSocket)
                }
            }
        }
        
        return source
    }
    
    override func start(listenPort: in_port_t) throws {
        try start(listenPort, bindToLocalhost: true, useAlsoIPv6: false)
    }
    
    func start(port: in_port_t = 8080, bindToLocalhost: Bool = true, useAlsoIPv6: Bool = false) throws {
        
        //let ipv4ListeningSocketFD = try createListeningSocket(useIPv6: false, port: port, bindToLocalhost: bindToLocalhost, maxPendingConnections: SOMAXCONN)
        let ipv4Socket = try Socket.tcpSocketForListen(port)
        dispatchSource4 = createDispatchSource(ipv4Socket.socketFileDescriptor, isIPv6: false)
        guard let source4 = dispatchSource4 else {
            throw punosError(0, "Could not create IPv4 dispatch source")
        }
        dispatch_resume(source4)
        
        /*
        if useAlsoIPv6 {
            let ipv6ListeningSocketFD = try createListeningSocket(useIPv6: true, port: port, bindToLocalhost: bindToLocalhost, maxPendingConnections: SOMAXCONN)
            dispatchSource6 = createDispatchSource(ipv6ListeningSocketFD, isIPv6: true)
            guard let source6 = dispatchSource6 else {
                throw punosError(0, "Could not create IPv6 dispatch source")
            }
            dispatch_resume(source6)
        }
        */
    }
    
    override func stop() {
        if let source = dispatchSource6 {
            dispatch_source_cancel(source)
        }
        if let source = dispatchSource4 {
            dispatch_source_cancel(source)
        }
        
        // Wait until the cancellation handlers have been called which
        // guarantees the listening sockets are closed
        dispatch_group_wait(sourceGroup, DISPATCH_TIME_FOREVER)
    }
}
