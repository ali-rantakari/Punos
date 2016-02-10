//
//  MockServerTests.swift
//  PunosTests
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
@testable import Punos

private extension NSHTTPURLResponse {
    func headerWithName(name: String) -> String? {
        return (allHeaderFields as? [String:String])?[name]
    }
    var allHeaderNames: Set<String> {
        guard let headers = allHeaderFields as? [String:String] else { return [] }
        return Set(headers.keys) ?? []
    }
}

class MockServerTests: XCTestCase {
    
    // ------------------------------------------------
    // MARK: Helpers; plumbing
    
    var server = MockServer()
    
    override func setUp() {
        super.setUp()
        server = MockServer()
        server.start()
    }
    
    override func tearDown() {
        super.tearDown()
        server.stop()
    }
    
    func request(method: String, _ path: String, body: String? = nil, headers: [String:String]? = nil, timeout: NSTimeInterval = 2, completionHandler: ((NSData, NSHTTPURLResponse, NSError?) -> Void)? = nil) {
        let expectation = expectationWithDescription("Request")
        
        let request = NSMutableURLRequest(URL: NSURL(string: "\(server.baseURLString ?? "")\(path)")!)
        request.HTTPMethod = method
        if let headers = headers {
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        }
        if let body = body {
            request.HTTPBody = body.dataUsingEncoding(NSUTF8StringEncoding)
        }
        
        NSURLSession.sharedSession().dataTaskWithRequest(request) { data, response, error in
            guard let response = response as? NSHTTPURLResponse else {
                XCTFail("The response should always be an NSHTTPURLResponse")
                return
            }
            completionHandler?(data!, response, error)
            expectation.fulfill()
        }.resume()
        
        waitForExpectationsWithTimeout(timeout) { error in
            if error != nil {
                XCTFail("Request error: \(error)")
            }
        }
    }
    
    
    // ------------------------------------------------
    // MARK: Test cases
    
    func testStartupAndShutdownEffectOnAPI() {
        let s = MockServer()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        s.start(8888)
        
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.port, 8888)
        XCTAssertEqual(s.baseURLString, "http://localhost:8888")
        
        s.stop()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
    }
    
    func testResponseMocking_defaultsWhenNoMockResponsesConfigured() {
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.allHeaderNames, ["Server", "Date", "Connection", "Cache-Control"])
            XCTAssertEqual(data.length, 0)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher() {
        let mockData = "foofoo".dataUsingEncoding(NSUTF16StringEncoding)
        server.mockResponse(
            status: 201,
            data: mockData,
            contentType: "thing/foobar",
            headers: ["X-Greeting": "Hey yall"],
            onlyOnce: false,
            matcher: nil)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertEqual(response.allHeaderNames, ["Server", "Date", "Connection", "Cache-Control", "X-Greeting", "Content-Type", "Content-Length"])
            XCTAssertEqual(response.headerWithName("X-Greeting"), "Hey yall")
            XCTAssertEqual(response.headerWithName("Content-Type"), "thing/foobar")
            XCTAssertEqual(data, mockData)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_matcher() {
        server.mockResponse(status: 500) // default fallback
        server.mockResponse(status: 202) { request in
            return (request.method == "GET" && request.path.containsString("foo"))
        }
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/dom/xfoobar/gg") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
        request("GET", "/oof") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testResponseMocking_onlyOnce_withoutMatcher() {
        
        // The responses should be dealt in the same order in which they were configured:
        //
        server.mockResponse(status: 201, onlyOnce: true)
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 203, onlyOnce: true)
        server.mockResponse(status: 500) // default fallback
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        
        // All three 'onlyOnce' responses are exhausted — we should get the fallback:
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testResponseMocking_onlyOnce_withMatcher() {
        server.mockResponse(status: 500) // default fallback
        
        let matcher: MockResponseMatcher = { request in request.path == "/match-me" }
        server.mockResponse(status: 201, onlyOnce: true, matcher: matcher)
        server.mockResponse(status: 202, onlyOnce: true, matcher: matcher)
        server.mockResponse(status: 203, onlyOnce: true, matcher: matcher)
        
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        
        // Try one non-matching request "in between":
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
        
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        
        // All three 'onlyOnce' responses are exhausted — we should get the fallback:
        request("POST", "/match-me") { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testLatestRequestsGetters() {
        request("GET", "/gettersson")
        request("HEAD", "/headster")
        
        request("POST", "/foo/bar?a=1&b=2", body: "i used to be with it", headers: ["X-Eka":"eka", "X-Toka":"toka"]) { data, response, error in
            XCTAssertEqual(self.server.latestRequests.count, 3)
            
            XCTAssertEqual(self.server.lastRequest?.method, "POST")
            XCTAssertEqual(self.server.lastRequest?.path, "/foo/bar")
            XCTAssertEqual(self.server.lastRequest!.query, ["a":"1", "b":"2"])
            XCTAssertEqual(self.server.lastRequest!.headers["X-Eka"], "eka")
            XCTAssertEqual(self.server.lastRequest!.headers["X-Toka"], "toka")
            XCTAssertEqual(self.server.lastRequest?.data, "i used to be with it".dataUsingEncoding(NSUTF8StringEncoding))
            
            self.server.clearLatestRequests()
            
            XCTAssertEqual(self.server.latestRequests.count, 0)
            XCTAssertNil(self.server.lastRequest)
        }
    }
    
    // TODO: test "convenience" versions of .mockResponse()
    
}
