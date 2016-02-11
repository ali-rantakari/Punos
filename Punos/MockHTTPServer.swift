//
//  MockHTTPServer.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation
import GCDWebServers


typealias MockResponseMatcher = (request: HTTPRequest) -> Bool


/// Data for a mocked HTTP server response.
///
public struct MockResponse {
    
    /// The HTTP status code
    let statusCode: Int?
    
    /// The body data
    let data: NSData?
    
    /// The `Content-Type` header value
    let contentType: String?
    
    /// The HTTP headers
    let headers: [String:String]?
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
    
    private let server = GCDWebServer()
    
    init() {
        attachHandlers()
    }
    
    // ------------------------------------
    // MARK: Starting and stopping
    
    /// Start the server on the given `port` (`8080` by default.)
    ///
    func start(port: UInt? = nil) {
        do {
            try server.startWithOptions([
                GCDWebServerOption_Port: port ?? 8080,
                GCDWebServerOption_BindToLocalhost: true,
                GCDWebServerOption_ServerName: "",
                ])
        } catch let error {
            fatalError("The mock server failed to start on port \(port). Error: \(error)")
        }
    }
    
    /// Stop the server.
    ///
    func stop() {
        server.stop()
    }
    
    /// Whether the server is currently running.
    ///
    var isRunning: Bool { return server.running }
    
    /// The port the server is running on, or 0 if the server
    /// is not running.
    ///
    var port: UInt {
        return isRunning ? server.port : 0
    }
    
    /// The “base URL” (protocol, hostname, port) for the
    /// running server, or `nil` if the server is not running.
    ///
    var baseURLString: String? {
        if !server.running {
            return nil
        }
        return "http://localhost:\(server.port)"
    }
    
    
    // ------------------------------------
    // MARK: Responding
    
    private let allHTTPVerbs = ["OPTIONS", "GET", "HEAD", "POST", "PUT", "DELETE", "TRACE", "CONNECT"]
    
    private func attachHandlers() {
        for method in allHTTPVerbs {
            server.addDefaultHandlerForMethod(method, requestClass: GCDWebServerDataRequest.self, asyncProcessBlock: respondToRequest)
        }
    }
    
    private func mockResponseConfigForRequest(request: GCDWebServerRequest!) -> MockResponseConfiguration? {
        
        let publicRequest = HTTPRequest(request)
        
        for i in mockResponsesWithMatchers.indices {
            let responseConfig = mockResponsesWithMatchers[i]
            guard let matcher = responseConfig.matcher else { continue }
            
            if matcher(request: publicRequest) {
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
    
    private func respondToRequest(request: GCDWebServerRequest!, completion: ((GCDWebServerResponse!) -> Void)!) {
        latestRequests.append(HTTPRequest(request))
        
        guard let mockConfig = mockResponseConfigForRequest(request) else {
            completion(GCDWebServerResponse())
            return
        }
        let mockData = mockConfig.response
        
        let response: GCDWebServerResponse = {
            if let bodyData = mockData.data, contentType = mockData.contentType {
                return GCDWebServerDataResponse(data: bodyData, contentType: contentType)
            }
            return GCDWebServerResponse()
        }()
        
        response.statusCode = mockData.statusCode ?? 200
        
        if let headers = mockData.headers {
            for (k, v) in headers {
                if k == "ETag" {
                    response.eTag = v
                } else if k == "Cache-Control" {
                    // TODO: set .cacheControlMaxAge
                } else {
                    response.setValue(v, forAdditionalHeader: k)
                }
            }
        }
        
        dispatchAfterInterval(mockConfig.delay, queue: dispatch_get_main_queue()) {
            completion(response)
        }
    }
    
    /// The latest HTTP requests this server has received, in order of receipt.
    ///
    var latestRequests = [HTTPRequest]()
    
    /// The most recent HTTP request this server has received, or `nil` if none.
    ///
    var lastRequest: HTTPRequest? {
        return latestRequests.last
    }
    
    /// Clear the `latestRequests` list (and `lastRequest`.)
    ///
    func clearLatestRequests() {
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
    func mockResponse(endpoint endpoint: String? = nil, response: MockResponse, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
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
    ///     - data: The response body data
    ///     - contentType: The content type of the response body data (i.e. the `Content-Type` header)
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
    func mockResponse(endpoint endpoint: String? = nil, status: Int? = nil, data: NSData? = nil, contentType: String? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        let response = MockResponse(
            statusCode: status,
            data: data,
            contentType: contentType,
            headers: headers)
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
    func mockJSONResponse(endpoint: String? = nil, json: String? = nil, status: Int? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, delay: NSTimeInterval = 0, matcher: MockResponseMatcher? = nil) {
        mockResponse(
            status: status,
            data: json?.dataUsingEncoding(NSUTF8StringEncoding),
            contentType: "application/json",
            headers: headers,
            onlyOnce: onlyOnce,
            delay: delay,
            endpoint: endpoint,
            matcher: matcher)
    }
    
    /// Remove all mock responses previously added with `mockResponse()`.
    ///
    func clearMockResponses() {
        defaultMockResponses.removeAll()
        mockResponsesWithMatchers.removeAll()
    }
}

