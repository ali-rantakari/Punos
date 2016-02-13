//
//  MockHTTPServer.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation


public typealias MockResponseMatcher = (request: HTTPRequest) -> Bool


/// Data for a mocked HTTP server response.
///
public struct MockResponse {
    
    /// The HTTP status code
    public let statusCode: Int?
    
    /// The body data
    public let data: NSData?
    
    /// The HTTP headers
    public let headers: [String:String]?
}


private struct MockResponseConfiguration {
    let response: MockResponse
    let matcher: MockResponseMatcher?
    let onlyOnce: Bool
    let delay: NSTimeInterval
}


/// A web server that runs on `localhost` and can be told how to respond
/// to incoming requests. Meant for automated tests.
///
public class MockHTTPServer {
    
    private let server = BaseServer(queue: dispatch_queue_create("org.hasseg.Punos.server", DISPATCH_QUEUE_CONCURRENT))
    
    public init() {
        server.responder = respondToRequest
    }
    
    // ------------------------------------
    // MARK: Starting and stopping
    
    /// Start the server on the given `port` (`8080` by default.)
    ///
    /// - throws: `NSError` if the server could not be started.
    ///
    public func start(port: in_port_t? = nil) throws {
        let effectivePort = port ?? 8080
        do {
            try server.start(effectivePort)
            self.port = effectivePort
            isRunning = true
            print("\(self.dynamicType) started at port \(effectivePort)")
        } catch let error {
            throw punosError(Int(effectivePort), "The mock server failed to start on port \(effectivePort). Error: \(error)")
        }
    }
    
    /// Stop the server.
    ///
    public func stop() {
        server.stop()
        port = 0
        isRunning = false
        print("\(self.dynamicType) stopped.")
    }
    
    /// Whether the server is currently running.
    ///
    public private(set) var isRunning: Bool = false
    
    /// The port the server is running on, or 0 if the server
    /// is not running.
    ///
    public private(set) var port: in_port_t = 0
    
    /// The “base URL” (protocol, hostname, port) for the
    /// running server, or `nil` if the server is not running.
    ///
    public var baseURLString: String? {
        if !isRunning {
            return nil
        }
        return "http://localhost:\(port)"
    }
    
    
    // ------------------------------------
    // MARK: Responding
    
    private func mockResponseConfigForRequest(request: HTTPRequest) -> MockResponseConfiguration? {
        
        for i in mockResponsesWithMatchers.indices {
            let responseConfig = mockResponsesWithMatchers[i]
            guard let matcher = responseConfig.matcher else { continue }
            
            if matcher(request: request) {
                if responseConfig.onlyOnce {
                    mockResponsesWithMatchers.removeAtIndex(i)
                }
                return responseConfig
            }
        }
        
        for i in defaultMockResponses.indices {
            let responseConfig = defaultMockResponses[i]
            if responseConfig.onlyOnce {
                defaultMockResponses.removeAtIndex(i)
            }
            return responseConfig
        }
        
        return nil
    }
    
    private let responseLock = NSLock()
    
    private func respondToRequest(request: HttpRequest, _ callback: (HttpResponse) -> Void) {
        let maybeMockConfig: MockResponseConfiguration? = lock(responseLock) {
            let publicRequest = HTTPRequest(request)
            self.latestRequests.append(publicRequest)
            
            return self.mockResponseConfigForRequest(publicRequest)
        }
        guard let mockConfig = maybeMockConfig else {
            callback(server.defaultResponse)
            return
        }
        let mockData = mockConfig.response
        
        let statusCode = mockData.statusCode ?? 200
        let response = HttpResponse(
            statusCode,
            RFC2616.reasonsForStatusCodes[statusCode] ?? "",
            mockData.headers,
            { responseBodyWriter in
                if let bodyData = mockData.data {
                    let bytes = Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>(bodyData.bytes), count: bodyData.length))
                    responseBodyWriter.write(bytes)
                }
            })
        
        if 0 < mockConfig.delay {
            dispatchAfterInterval(mockConfig.delay, queue: server.queue) {
                callback(response)
            }
        } else {
            callback(response)
        }
    }
    
    /// The latest HTTP requests this server has received, in order of receipt.
    ///
    public var latestRequests = [HTTPRequest]()
    
    /// The `.endpoint` values for `latestRequests`.
    ///
    public var latestRequestEndpoints: [String] {
        return latestRequests.map { $0.endpoint }
    }
    
    /// The most recent HTTP request this server has received, or `nil` if none.
    ///
    public var lastRequest: HTTPRequest? {
        return latestRequests.last
    }
    
    /// Clear the `latestRequests` list (and `lastRequest`.)
    ///
    public func clearLatestRequests() {
        latestRequests.removeAll()
    }
    
    
    // ------------------------------------
    // MARK: Response mocking
    
    private var defaultMockResponses: [MockResponseConfiguration] = []
    private var mockResponsesWithMatchers: [MockResponseConfiguration] = []
    
    private func matcherForEndpoint(endpoint: String?) -> MockResponseMatcher? {
        guard let endpoint = endpoint else { return nil }
        let parts = endpoint.componentsSeparatedByString(" ")
        let method = parts.first
        let path = parts.last
        return { request in
            return request.method == method && request.path == path
        }
    }
    
    /// Tell the server to send this response to incoming requests.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. If set, this will
    ///       supersede `matcher`.
    ///     - response: The mock response to send
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - delay: How long to wait (after processing the incoming request) before sending
    ///       the response
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests. If multiple matchers match an incoming request, the
    ///       first one added wins.
    ///
    public func mockResponse(endpoint endpoint: String? = nil, response: MockResponse, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        let config = MockResponseConfiguration(
            response: response,
            matcher: matcherForEndpoint(endpoint) ?? matcher,
            onlyOnce: onlyOnce,
            delay: delay)
        if matcher == nil {
            defaultMockResponses.append(config)
        } else {
            mockResponsesWithMatchers.append(config)
        }
    }
    
    /// Tell the server to send this response to incoming requests.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. If set, this will
    ///       supersede `matcher`.
    ///     - status: The response HTTP status code. Default: 200
    ///     - data: The response body data. If non-nil, the `"Content-Length"` header will
    ///       be given an appropriate value.
    ///     - headers: The response headers
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - delay: How long to wait (after processing the incoming request) before sending
    ///       the response
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests. If multiple matchers match an incoming request, the
    ///       first one added wins.
    ///
    public func mockResponse(endpoint endpoint: String? = nil, status: Int? = nil, data: NSData? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        var effectiveHeaders = headers
        if let data = data {
            if effectiveHeaders == nil {
                effectiveHeaders = [:]
            }
            effectiveHeaders!["Content-Length"] = "\(data.length)"
        }
        let response = MockResponse(
            statusCode: status,
            data: data,
            headers: effectiveHeaders)
        mockResponse(endpoint: endpoint, response: response, onlyOnce: onlyOnce, delay: delay, matcher: matcher)
    }
    
    /// Tell the server to send this JSON response to incoming requests (sending
    /// the `Content-Type` header as `"application/json"`.)
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. If set, this will
    ///       supersede `matcher`.
    ///     - json: The UTF-8 encoded JSON to be sent in the response body
    ///     - status: The response HTTP status code. Default: 200
    ///     - headers: The response headers
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - delay: How long to wait (after processing the incoming request) before sending
    ///       the response
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests. If multiple matchers match an incoming request, the
    ///       first one added wins.
    ///
    public func mockJSONResponse(endpoint: String? = nil, json: String? = nil, status: Int? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        mockResponse(
            status: status,
            data: json?.dataUsingEncoding(NSUTF8StringEncoding),
            headers: ["Content-Type": "application/json"].merged(headers),
            onlyOnce: onlyOnce,
            delay: delay,
            endpoint: endpoint,
            matcher: matcher)
    }
    
    /// Remove all mock responses previously added with `mockResponse()`.
    ///
    public func clearMockResponses() {
        defaultMockResponses.removeAll()
        mockResponsesWithMatchers.removeAll()
    }
    
    /// Removes all “mocking” state: the mock responses, and the latest request list.
    ///
    public func clearAllMockingState() {
        clearLatestRequests()
        clearMockResponses()
    }
}

