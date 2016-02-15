//
//  ResponseMockingTests.swift
//  Punos
//
//  Created by Ali Rantakari on 12.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import Punos

class ResponseMockingTests: MockServerTestCase {
    
    func testResponseMocking_defaultsWhenNoMockResponsesConfigured() {
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.allHeaderNames, [])
            XCTAssertEqual(data.length, 0)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher() {
        let mockData = "foofoo".dataUsingEncoding(NSUTF16StringEncoding)!
        server.mockResponse(
            status: 201,
            data: mockData,
            headers: ["X-Greeting": "Hey yall", "Content-Type": "thing/foobar"],
            onlyOnce: false,
            matcher: nil)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertEqual(response.allHeaderNames, ["X-Greeting", "Content-Type", "Content-Length"])
            XCTAssertEqual(response.headerWithName("X-Greeting"), "Hey yall")
            XCTAssertEqual(response.headerWithName("Content-Type"), "thing/foobar")
            XCTAssertEqual(response.headerWithName("Content-Length"), "\(mockData.length)")
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
    
    func testResponseMocking_matcher_matchByData() {
        let dataToMatchOn = "woohoo".dataUsingEncoding(NSUTF8StringEncoding)
        let otherData = "something else".dataUsingEncoding(NSUTF8StringEncoding)
        
        server.mockResponse(status: 500) // default fallback
        server.mockResponse(status: 202) { request in
            return request.data == dataToMatchOn
        }
        
        request("POST", "/foo", data: dataToMatchOn) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("POST", "/dom/xfoobar/gg", data: dataToMatchOn) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        
        request("POST", "/foo") { data, response, error in // no data
            XCTAssertEqual(response.statusCode, 500)
        }
        request("POST", "/foo2", data: otherData) { data, response, error in
            XCTAssertEqual(response.statusCode, 500)
        }
    }
    
    func testResponseMocking_matcher_overlapping() {
        server.mockResponse(status: 201) { request in
            return request.path.containsString("foo")
        }
        server.mockResponse(status: 202) { request in
            return request.path.containsString("bar")
        }
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/bar") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        
        // Both match --> 1st one added wins
        request("GET", "/foobar") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
    func testResponseMocking_matcher_viaEndpointParameter() {
        server.mockResponse(endpoint: "GET /foo", status: 201)
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        
        // If `matcher` and `endpoint` are both given, `endpoint`
        // takes precedence:
        //
        server.mockResponse(endpoint: "GET /foo", status: 201) { req in return false }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
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
    
    func testResponseMocking_delay() {
        // Let's try to keep the delay short enough to not make our
        // tests slow, but long enough for us to reliably check that
        // it was intentional and not accidental
        //
        let delayToTest: NSTimeInterval = 0.5
        
        // First try with NO delay:
        //
        server.mockResponse(status: 205, delay: 0)
        
        let noDelayStartDate = NSDate()
        request("GET", "/foo") { data, response, error in
            let endDate = NSDate()
            XCTAssertEqual(response.statusCode, 205)
            XCTAssertLessThan(endDate.timeIntervalSinceDate(noDelayStartDate), 0.1)
        }
        
        // Then try with the delay:
        //
        server.clearMockResponses()
        server.mockResponse(status: 201, delay: delayToTest)
        
        let withDelayStartDate = NSDate()
        request("GET", "/foo") { data, response, error in
            let endDate = NSDate()
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertGreaterThan(endDate.timeIntervalSinceDate(withDelayStartDate), delayToTest)
        }
    }
    
    func testResponseMocking_headersSpecialCasedByGCDWebServerAPI() {
        
        // Test that we can, if we want, modify the values of response headers
        // that the GCDWebServer API handles as some kind of a special case
        // (either through a bespoke property/API or by setting values by default
        // on its own.)
        //
        let fakeHeaders = [
            "Etag": "-etag",
            "Cache-Control": "-cc",
            "Server": "-server",
            "Date": "-date",
            "Connection": "-connection",
            "Last-Modified": "-lm",
            "Transfer-Encoding": "-te",
        ]
        server.mockResponse(headers: fakeHeaders)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.allHeaderFields as! [String:String], fakeHeaders)
        }
    }
  
    // TODO: test "convenience" versions of .mockResponse()
    
}
