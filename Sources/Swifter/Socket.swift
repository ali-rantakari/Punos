//
//  Socket.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

/* Low level routines for POSIX sockets */

internal enum SocketError: ErrorProtocol {
    case socketCreationFailed(String)
    case socketSettingReUseAddrFailed(String)
    case socketSettingIPV6OnlyFailed(String)
    case bindFailed(String)
    case bindFailedAddressAlreadyInUse(String)
    case listenFailed(String)
    case writeFailed(String)
    case getPeerNameFailed(String)
    case convertingPeerNameFailed
    case getNameInfoFailed(String)
    case acceptFailed(String)
    case recvFailed(String)
    case closeFailed(String)
}

internal class Socket: Hashable, Equatable {
    
    internal class func tcpSocketForListen(_ port: in_port_t, maxPendingConnection: Int32 = SOMAXCONN) throws -> Socket {
        
        #if os(Linux)
            let socketFileDescriptor = socket(AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        #else
            let socketFileDescriptor = socket(AF_INET6, SOCK_STREAM, 0)
        #endif
        
        if socketFileDescriptor == -1 {
            throw SocketError.socketCreationFailed(Socket.descriptionOfLastError())
        }
        
        var sockoptValueYES: Int32 = 1
        var sockoptValueNO: Int32 = 0
        
        // Allow reuse of local addresses:
        //
        if setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &sockoptValueYES, socklen_t(sizeof(Int32))) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.releaseIgnoringErrors(socketFileDescriptor)
            throw SocketError.socketSettingReUseAddrFailed(details)
        }
        
        // Accept also IPv4 connections (note that this means we must bind to
        // in6addr_any — binding to in6addr_loopback will effectively rule out
        // IPv4 addresses):
        //
        if setsockopt(socketFileDescriptor, IPPROTO_IPV6, IPV6_V6ONLY, &sockoptValueNO, socklen_t(sizeof(Int32))) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.releaseIgnoringErrors(socketFileDescriptor)
            throw SocketError.socketSettingIPV6OnlyFailed(details)
        }
        
        Socket.setNoSigPipe(socketFileDescriptor)
        
        #if os(Linux)
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = Socket.htonsPort(port)
            addr.sin6_addr = in6addr_any
        #else
            var addr = sockaddr_in6()
            addr.sin6_len = __uint8_t(sizeof(sockaddr_in6))
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = Socket.htonsPort(port)
            addr.sin6_addr = in6addr_any
        #endif
        
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in6)))
        
        if bind(socketFileDescriptor, &bind_addr, socklen_t(sizeof(sockaddr_in6))) == -1 {
            let myErrno = errno
            let details = Socket.descriptionOfLastError()
            Socket.releaseIgnoringErrors(socketFileDescriptor)
            if myErrno == EADDRINUSE {
                throw SocketError.bindFailedAddressAlreadyInUse(details)
            }
            throw SocketError.bindFailed(details)
        }
        
        if listen(socketFileDescriptor, maxPendingConnection) == -1 {
            let details = Socket.descriptionOfLastError()
            Socket.releaseIgnoringErrors(socketFileDescriptor)
            throw SocketError.listenFailed(details)
        }
        return Socket(socketFileDescriptor: socketFileDescriptor)
    }
    
    internal let socketFileDescriptor: Int32
    
    internal init(socketFileDescriptor: Int32) {
        self.socketFileDescriptor = socketFileDescriptor
    }
    
    internal var hashValue: Int { return Int(socketFileDescriptor) }
    
    internal func release() throws {
        try Socket.release(socketFileDescriptor)
    }
    
    internal func releaseIgnoringErrors() {
        Socket.releaseIgnoringErrors(socketFileDescriptor)
    }
    
    internal func shutdown() {
        Socket.shutdown(socketFileDescriptor)
    }
    
    internal func acceptClientSocket() throws -> Socket {
        var addr = sockaddr()        
        var len: socklen_t = 0
        let clientSocket = accept(socketFileDescriptor, &addr, &len)
        if clientSocket == -1 {
            throw SocketError.acceptFailed(Socket.descriptionOfLastError())
        }
        Socket.setNoSigPipe(clientSocket)
        return Socket(socketFileDescriptor: clientSocket)
    }
    
    internal func writeUTF8(_ string: String) throws {
        try writeUInt8([UInt8](string.utf8))
    }
    
    internal func writeUTF8AndCRLF(_ string: String) throws {
        try writeUTF8(string + "\r\n")
    }
    
    internal func writeUInt8(_ data: [UInt8]) throws {
        try data.withUnsafeBufferPointer {
            var sent = 0
            while sent < data.count {
                #if os(Linux)
                    let s = send(socketFileDescriptor, $0.baseAddress + sent, data.count - sent, Int32(MSG_NOSIGNAL))
                #else
                    let s = write(socketFileDescriptor, $0.baseAddress! + sent, data.count - sent)
                #endif
                if s <= 0 {
                    throw SocketError.writeFailed(Socket.descriptionOfLastError())
                }
                sent += s
            }
        }
    }
    
    internal func readOneByte() throws -> UInt8 {
        var buffer = [UInt8](repeating: 0, count: 1)
        let next = recv(socketFileDescriptor, &buffer, buffer.count, 0)
        if next <= 0 {
            throw SocketError.recvFailed(Socket.descriptionOfLastError())
        }
        return buffer[0]
    }
    
    internal func readNumBytes(_ count: Int) throws -> [UInt8] {
        var ret = [UInt8]()
        while ret.count < count {
            let maxBufferSize = 2048
            let remainingExpectedBytes = count - ret.count
            let bufferSize = min(remainingExpectedBytes, maxBufferSize)
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let numBytesReceived = recv(socketFileDescriptor, &buffer, buffer.count, 0)
            if numBytesReceived <= 0 {
                throw SocketError.recvFailed(Socket.descriptionOfLastError())
            }
            ret.append(contentsOf: buffer)
        }
        return ret
    }
    
    internal static let CR = UInt8(13)
    internal static let NL = UInt8(10)
    
    internal func readLine() throws -> String {
        var characters: String = ""
        var n: UInt8 = 0
        repeat {
            n = try readOneByte()
            if n > Socket.CR { characters.append(Character(UnicodeScalar(n))) }
        } while n != Socket.NL
        return characters
    }
    
    internal func peername() throws -> String {
        var addr = sockaddr(), len: socklen_t = socklen_t(sizeof(sockaddr))
        if getpeername(socketFileDescriptor, &addr, &len) != 0 {
            throw SocketError.getPeerNameFailed(Socket.descriptionOfLastError())
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) != 0 {
            throw SocketError.getNameInfoFailed(Socket.descriptionOfLastError())
        }
        guard let name = String(validatingUTF8: hostBuffer) else {
            throw SocketError.convertingPeerNameFailed
        }
        return name
    }
    
    internal class func descriptionOfLastError() -> String {
        return String(cString: strerror(errno)) ?? "Error: \(errno)"
    }
    
    internal class func setNoSigPipe(_ socketFileDescriptor: Int32) {
        #if os(Linux)
            // There is no SO_NOSIGPIPE in Linux (nor some other systems). You can instead use the MSG_NOSIGNAL flag when calling send(),
            // or use signal(SIGPIPE, SIG_IGN) to make your entire application ignore SIGPIPE.
        #else
            // Prevents crashes when blocking calls are pending and the app is paused ( via Home button ).
            var no_sig_pipe: Int32 = 1
            setsockopt(socketFileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(sizeof(Int32)))
        #endif
    }
    
    private class func shutdown(_ socketFileDescriptor: Int32) {
        #if os(Linux)
            _ = shutdown(socket, Int32(SHUT_RDWR))
        #else
            _ = Darwin.shutdown(socketFileDescriptor, SHUT_RDWR)
        #endif
    }
    
    internal class func release(_ socketFileDescriptor: Int32) throws {
        shutdown(socketFileDescriptor)
        if close(socketFileDescriptor) == -1 {
            throw SocketError.closeFailed(Socket.descriptionOfLastError())
        }
    }
    
    private class func releaseIgnoringErrors(_ socketFileDescriptor: Int32) {
        _ = try? release(socketFileDescriptor)
    }
    
    private class func htonsPort(_ port: in_port_t) -> in_port_t {
        #if os(Linux)
            return htons(port)
        #else
            let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
            return isLittleEndian ? _OSSwapInt16(port) : port
        #endif
    }
}

internal func ==(socket1: Socket, socket2: Socket) -> Bool {
    return socket1.socketFileDescriptor == socket2.socketFileDescriptor
}
