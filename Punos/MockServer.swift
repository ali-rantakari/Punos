//
//  MockServer.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import Foundation
import GCDWebServers


typealias MockResponseMatcher = (request: GCDWebServerRequest) -> Bool


private struct MockResponse {
    let statusCode: Int?
    let data: NSData?
    let contentType: String?
    let headers: [String:String]?
    let matcher: MockResponseMatcher?
    let onlyOnce: Bool
}


/// A web server that runs on `localhost` and can be told how to respond
/// to incoming requests. Meant for automated tests.
///
public class MockServer {
    
    private let server = GCDWebServer()
    
    
    // ------------------------------------
    // MARK: Starting and stopping
    
    /// Start the server on the given `port` (`8080` by default.)
    ///
    func start(port: UInt? = nil) {
        if !server.startWithPort(port ?? 8080, bonjourName: nil) {
            fatalError("The mock server failed to start on port \(port)")
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
    
    private func updateHandlers() {
        for method in allHTTPVerbs {
            server.addDefaultHandlerForMethod(method, requestClass: nil, processBlock: respondToRequest)
        }
    }
    
    private func mockResponseDataForRequest(request: GCDWebServerRequest!) -> MockResponse? {
        
        for i in mockResponsesWithMatchers.indices {
            let responseWithMatcher = mockResponsesWithMatchers[i]
            guard let matcher = responseWithMatcher.matcher else { continue }
            
            if matcher(request: request) {
                if responseWithMatcher.onlyOnce {
                    mockResponsesWithMatchers.removeAtIndex(i)
                }
                return responseWithMatcher
            }
        }
        
        if let def = defaultMockResponse {
            if def.onlyOnce {
                defaultMockResponse = nil
                return def
            }
        }
        
        return nil
    }
    
    private func respondToRequest(request: GCDWebServerRequest!) -> GCDWebServerResponse {
        guard let mockData = mockResponseDataForRequest(request) else {
            return GCDWebServerResponse()
        }
        
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
        
        return response
    }
    
    
    // ------------------------------------
    // MARK: Response mocking
    
    private var defaultMockResponse: MockResponse?
    private var mockResponsesWithMatchers: [MockResponse] = []
    
    /// Tell the server to send this response to incoming requests.
    ///
    /// - parameters:
    ///     - status: The response HTTP status code. Default: 200
    ///     - data: The response body data
    ///     - contentType: The content type of the response body data (i.e. the `Content-Type` header)
    ///     - headers: The response headers
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests.
    ///
    func mockResponse(status status: Int? = nil, data: NSData? = nil, contentType: String? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, matcher: MockResponseMatcher? = nil) {
        let mockResponse = MockResponse(
            statusCode: status,
            data: data,
            contentType: contentType,
            headers: headers,
            matcher: matcher,
            onlyOnce: onlyOnce)
        
        if matcher == nil {
            defaultMockResponse = mockResponse
        } else {
            mockResponsesWithMatchers.append(mockResponse)
        }
    }
    
    /// Tell the server to send this JSON response to incoming requests (sending
    /// the `Content-Type` header as `"application/json"`.)
    ///
    /// - parameters:
    ///     - status: The response HTTP status code. Default: 200
    ///     - json: The UTF-8 encoded JSON to be sent in the response body
    ///     - headers: The response headers
    ///     - onlyOnce: Whether to only mock this response once — if `true`, this
    ///       mock response will only be sent for the first matching request and not
    ///       thereafter
    ///     - matcher: An “evaluator” function that determines what requests this response
    ///       should be sent for. If omitted or `nil`, this response will match _all_
    ///       incoming requests.
    ///
    func mockResponse(status status: Int? = nil, json: String? = nil, headers: [String:String]? = nil, onlyOnce: Bool = false, matcher: MockResponseMatcher? = nil) {
        mockResponse(
            status: status,
            data: json?.dataUsingEncoding(NSUTF8StringEncoding),
            contentType: "application/json",
            headers: headers,
            onlyOnce: onlyOnce,
            matcher: matcher)
    }
    
    /// Remove all mock responses previously added with `mockResponse()`.
    ///
    func clearMockResponses() {
        defaultMockResponse = nil
        mockResponsesWithMatchers.removeAll()
    }
}

