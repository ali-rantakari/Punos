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
    public let statusCode: Int
    
    /// The body data
    public let data: Data?
    
    /// The HTTP headers
    public let headers: [String:String]?
    
    public init(statusCode: Int, data: Data?, headers: [String:String]?) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
    
    /// Returns a copy of self by replacing members with the supplied
    /// values.
    ///
    public func copyWithChanges(statusCode: Int? = nil, data: Data? = nil, headers: [String:String]? = nil) -> MockResponse {
        return MockResponse(
            statusCode: statusCode ?? self.statusCode,
            data: data ?? self.data,
            headers: headers ?? self.headers
        )
    }
}


private struct MockResponseConfiguration {
    let response: MockResponse
    let matcher: MockResponseMatcher?
    let onlyOnce: Bool
    let delay: TimeInterval
}


private func printMessageToLog(_ message: String) {
    print("Punos: \(message)")
}


/// A web server that runs on `localhost` and can be told how to respond
/// to incoming requests. Meant for automated tests.
///
public class MockHTTPServer {
    
    private let server: PunosHTTPServer
    private let log: Logger
    
    /// Create a new MockHTTPServer.
    ///
    /// - parameter loggingEnabled: Whether to print status messages to stdout.
    ///
    public init(loggingEnabled: Bool = false) {
        log = loggingEnabled ? printMessageToLog : { _ in }
        server = PunosHTTPServer(
            queue: DispatchQueue(label: "org.hasseg.Punos.server", attributes: DispatchQueueAttributes.concurrent),
            logger: log
        )
        server.responder = respondToRequest
    }
    
    // ------------------------------------
    // MARK: Starting and stopping
    
    /// Start the server.
    ///
    /// - parameter preferredPorts: A list of ports to try and bind to, in order of
    ///                             preference. By default, `[8080, 8081, 8082]`.
    ///
    /// - throws: `NSError` if the server could not be started.
    ///
    public func start(preferredPorts ports: [in_port_t] = [8080, 8081, 8082]) throws {
        do {
            try server.start(portsToTry: ports)
            isRunning = true
            log("\(self.dynamicType) started at port \(port)")
        } catch let error {
            throw punosError(Int(port), "The mock server failed to start with preferred ports \(ports). Error: \(error)")
        }
    }
    
    /// Stop the server.
    ///
    public func stop() {
        server.stop()
        isRunning = false
        log("\(self.dynamicType) stopped.")
    }
    
    /// Whether the server is currently running.
    ///
    public private(set) var isRunning: Bool = false
    
    /// The port the server is running on, or 0 if the server
    /// is not running.
    ///
    public var port: in_port_t {
        return server.port ?? 0
    }
    
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
    
    private func mockResponseConfigForRequest(_ request: HTTPRequest) -> MockResponseConfiguration? {
        
        for i in mockResponsesWithMatchers.indices {
            let responseConfig = mockResponsesWithMatchers[i]
            guard let matcher = responseConfig.matcher else { continue }
            
            if matcher(request: request) {
                if responseConfig.onlyOnce {
                    mockResponsesWithMatchers.remove(at: i)
                }
                return responseConfig
            }
        }
        
        for i in defaultMockResponses.indices {
            let responseConfig = defaultMockResponses[i]
            if responseConfig.onlyOnce {
                defaultMockResponses.remove(at: i)
            }
            return responseConfig
        }
        
        return nil
    }
    
    private let defaultMockResponseConfiguration = MockResponseConfiguration(
        response: MockResponse(statusCode: 200, data: nil, headers: nil),
        matcher: nil,
        onlyOnce: false,
        delay: 0)
    
    private let responseLock = Lock()
    
    private func respondToRequest(_ request: HttpRequest, _ callback: (HttpResponse) -> Void) {
        let mockConfig: MockResponseConfiguration = lock(responseLock) {
            let publicRequest = HTTPRequest(request)
            self.latestRequests.append(publicRequest)
            
            return self.mockResponseConfigForRequest(publicRequest) ?? self.defaultMockResponseConfiguration
        }
        let mockData = commonResponseModifier(mockConfig.response)
        
        let statusCode = mockData.statusCode
        let content: HttpResponseContent? = {
            if let bodyData = mockData.data {
                return (length: bodyData.count, write: { responseBodyWriter in
                    let bytes = Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>((bodyData as NSData).bytes), count: bodyData.count))
                    responseBodyWriter.write(bytes)
                })
            }
            return nil
        }()
        
        let response = HttpResponse(
            statusCode,
            mockData.headers,
            content)
        
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
    
    private func matcherForEndpoint(_ endpoint: String?) -> MockResponseMatcher? {
        guard let endpoint = endpoint else { return nil }
        let parts = endpoint.components(separatedBy: " ")
        let method = parts.first
        let path: String? = 1 < parts.count ? parts[1] : nil
        return { request in
            return request.method == method && (path == nil || request.path == path)
        }
    }
    
    /// A function that modifies each response before it is sent.
    /// Useful for e.g. setting common headers like `"Server"`.
    /// By default, the “identity” function (`{ $0 }`).
    ///
    public var commonResponseModifier: ((MockResponse) -> MockResponse) = { $0 }
    
    /// Tell the server to send this response to incoming requests.
    ///
    /// - If multiple configured responses match an incoming request, the _first_ one added wins.
    /// - Responses with `endpoint` or `matcher` take precedence over ones without.
    /// - “Permanent default fallback responses” (i.e. ones with no `endpoint` or `matcher`, and
    ///   `onlyOnce == false`) can be overridden — configuring such a response will override
    ///   previously added ones.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. The HTTP verb is required
    ///       but the path is optional. If set, this will supersede `matcher`.
    ///     - response: The mock response to send
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - delay: How long to wait (after processing the incoming request) before sending
    ///       the response
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests.
    ///
    public func mockResponse(endpoint: String? = nil, response: MockResponse, onlyOnce: Bool = false, delay: TimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        let config = MockResponseConfiguration(
            response: response,
            matcher: matcherForEndpoint(endpoint) ?? matcher,
            onlyOnce: onlyOnce,
            delay: delay)
        if config.matcher == nil {
            // "Permanent" response overrides any previously added permanent response:
            if !config.onlyOnce, let indexToOverride = defaultMockResponses.index(where: { !$0.onlyOnce }) {
                defaultMockResponses[indexToOverride] = config
            } else {
                defaultMockResponses.append(config)
            }
        } else {
            mockResponsesWithMatchers.append(config)
        }
    }
    
    /// Tell the server to send this response to incoming requests.
    ///
    /// - If multiple configured responses match an incoming request, the _first_ one added wins.
    /// - Responses with `endpoint` or `matcher` take precedence over ones without.
    /// - “Permanent default fallback responses” (i.e. ones with no `endpoint` or `matcher`, and
    ///   `onlyOnce == false`) can be overridden — configuring such a response will override
    ///   previously added ones.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. The HTTP verb is required
    ///       but the path is optional. If set, this will supersede `matcher`.
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
    ///       incoming requests.
    ///
    public func mockResponse(endpoint: String? = nil, status: Int? = nil, data: Data? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: TimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        let response = MockResponse(
            statusCode: status ?? 200,
            data: data,
            headers: headers)
        mockResponse(endpoint: endpoint, response: response, onlyOnce: onlyOnce, delay: delay, matcher: matcher)
    }
    
    /// Tell the server to send this JSON response to incoming requests (sending
    /// the `Content-Type` header as `"application/json"`.)
    ///
    /// - If multiple configured responses match an incoming request, the _first_ one added wins.
    /// - Responses with `endpoint` or `matcher` take precedence over ones without.
    /// - “Permanent default fallback responses” (i.e. ones with no `endpoint` or `matcher`, and
    ///   `onlyOnce == false`) can be overridden — configuring such a response will override
    ///   previously added ones.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. The HTTP verb is required
    ///       but the path is optional. If set, this will supersede `matcher`.
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
    ///       incoming requests.
    ///
    public func mockJSONResponse(endpoint: String? = nil, json: String? = nil, status: Int? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: TimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        mockResponse(
            status: status,
            data: json?.data(using: String.Encoding.utf8),
            headers: ["Content-Type": "application/json"].merged(headers),
            onlyOnce: onlyOnce,
            delay: delay,
            endpoint: endpoint,
            matcher: matcher)
    }
    
    /// Tell the server to send this JSON response to incoming requests (sending
    /// the `Content-Type` header as `"application/json"`.)
    ///
    /// - If multiple configured responses match an incoming request, the _first_ one added wins.
    /// - Responses with `endpoint` or `matcher` take precedence over ones without.
    /// - “Permanent default fallback responses” (i.e. ones with no `endpoint` or `matcher`, and
    ///   `onlyOnce == false`) can be overridden — configuring such a response will override
    ///   previously added ones.
    ///
    /// - parameters:
    ///     - endpoint: The “endpoint,” requests to which this response should be sent for,
    ///       in the format `"HTTPVERB path"`, e.g. `"POST /foo/bar"`. The HTTP verb is required
    ///       but the path is optional. If set, this will supersede `matcher`.
    ///     - object: The object to be sent in the response body, serialized as JSON. Serialization
    ///       failures will be silent and yield an empty response body.
    ///     - status: The response HTTP status code. Default: 200
    ///     - headers: The response headers
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - delay: How long to wait (after processing the incoming request) before sending
    ///       the response
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests.
    ///
    public func mockJSONResponse(endpoint: String? = nil, object: AnyObject? = nil, status: Int? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: TimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        let jsonData: Data? = {
            guard let o = object else { return nil }
            return try? JSONSerialization.data(withJSONObject: o, options: JSONSerialization.WritingOptions())
        }()
        mockResponse(
            status: status,
            data: jsonData,
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
    
    /// Removes all “mocking” state: the mock responses, the
    /// common response modifier, and the latest request list.
    ///
    public func clearAllMockingState() {
        clearLatestRequests()
        clearMockResponses()
        commonResponseModifier = { $0 }
    }
}

