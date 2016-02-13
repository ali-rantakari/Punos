//
//  BaseServer.swift
//  Punos
//
//  Created by Ali Rantakari on 13.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation

// http://stackoverflow.com/a/34042435
//
private let INADDR_LOOPBACK = UInt32(0x7f000001)
private let INADDR_ANY = UInt32(0x00000000)


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


private func htonsPort(port: in_port_t) -> in_port_t {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt16(port) : port
}

private func htonl(value: UInt32) -> UInt32 {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt32(value) : value
}

private func releaseSocket(socket: Int32) -> Int32 {
    Darwin.shutdown(socket, SHUT_RDWR)
    return close(socket)
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
    
    /*
    private func createListeningSocket(useIPv6 useIPv6: Bool, port: in_port_t, bindToLocalhost: Bool, maxPendingConnections: Int32) throws -> Int32 {
        let socketFD = socket(useIPv6 ? PF_INET6 : PF_INET, SOCK_STREAM, IPPROTO_TCP)
        if socketFD <= 0 {
            throw posixNSErrorFromErrno(errno, "Failed to create an \(ipVersionString(useIPv6)) listening socket")
        }
        
        var value: Int32 = 1
        if setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(sizeof(Int32))) != 0 {
            releaseSocket(socketFD)
            throw posixNSErrorFromErrno(errno, "Failed to set options on an \(ipVersionString(useIPv6)) listening socket")
        }
        
        var bind_addr = sockaddr()
        
        if useIPv6 {
            var addr = sockaddr_in6()
            addr.sin6_len = __uint8_t(sizeof(sockaddr_in6))
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = htonsPort(port)
            addr.sin6_addr = bindToLocalhost ? in6addr_loopback : in6addr_any
            memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in)))
        } else {
            var addr = sockaddr_in()
            addr.sin_len = __uint8_t(sizeof(sockaddr_in))
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = htonsPort(port)
            //addr.sin_addr = in_addr(s_addr: bindToLocalhost ? htonl(INADDR_LOOPBACK) : htonl(INADDR_ANY))
            addr.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))
            addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)
            memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in)))
        }
        
        if bind(socketFD, &bind_addr, socklen_t(sizeof(sockaddr_in))) != 0 {
            releaseSocket(socketFD)
            throw posixNSErrorFromErrno(errno, "Failed to bind an \(ipVersionString(useIPv6)) listening socket")
        }
        
        if listen(socketFD, maxPendingConnections) != 0 {
            releaseSocket(socketFD)
            throw posixNSErrorFromErrno(errno, "Failed to listen on an \(ipVersionString(useIPv6)) listening socket")
        }
        
        return socketFD
    }
    */
    
    private func createDispatchSource(listeningSocketFD: Int32, isIPv6: Bool) -> dispatch_source_t {
        dispatch_group_enter(sourceGroup)
        let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(listeningSocketFD), 0, queue)
        
        dispatch_source_set_cancel_handler(source) { _ in
            if releaseSocket(listeningSocketFD) != 0 {
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
                
                /*
                let remoteAddress = NSData(bytes: &remoteSockAddr, length: Int(remoteSockAddrLen))
                let localAddress: NSData? = {
                    var localSockAddr = sockaddr()
                    var localSockAddrLen: socklen_t = 0
                    if getsockname(clientSocket, &localSockAddr, &localSockAddrLen) == 0 {
                        return NSData(bytes: &localSockAddr, length: Int(localSockAddrLen))
                    }
                    return nil
                }()
                */
                
                // Make sure this socket cannot generate SIG_PIPE:
                var noSigPipe: Int32 = 1;
                setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(sizeof(Int32)));

                dispatch_async(self.queue) {
                    self.handleConnection(Socket(socketFileDescriptor: clientSocket))
                    releaseSocket(clientSocket)
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
        
        // Wait until the cancellation handlers have been called which guarantees the listening sockets are closed
        dispatch_group_wait(sourceGroup, DISPATCH_TIME_FOREVER)
    }
}
