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
            XCTAssertEqual(response.allHeaderNames, ["Connection"])
            XCTAssertEqual(data.count, 0)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher() {
        let mockData = "foofoo".data(using: String.Encoding.utf16)!
        server.mockResponse(
            status: 201,
            data: mockData,
            headers: ["X-Greeting": "Hey yall", "Content-Type": "thing/foobar"],
            onlyOnce: false,
            matcher: nil)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertEqual(response.allHeaderNames, ["X-Greeting", "Content-Type", "Content-Length", "Connection"])
            XCTAssertEqual(response.headerWithName("X-Greeting"), "Hey yall")
            XCTAssertEqual(response.headerWithName("Content-Type"), "thing/foobar")
            XCTAssertEqual(response.headerWithName("Content-Length"), "\(mockData.count)")
            XCTAssertEqual(data, mockData)
            XCTAssertNil(error)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher_overriding() {
        server.mockResponse(status: 201)
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        server.mockResponse(status: 202)
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
    }
    
    func testResponseMocking_defaultMockResponseWithNoMatcher_overriding_withOnlyOnceBefore() {
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 201)
        server.mockResponse(status: 203) // Overrides previously configured 201
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 202) // 202 onlyOnce
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 203) // fallback
        }
    }
    
    func testResponseMocking_matcher() {
        server.mockResponse(status: 500) // default fallback
        server.mockResponse(status: 202) { request in
            return (request.method == "GET" && request.path.contains("foo"))
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
        let dataToMatchOn = "woohoo".data(using: String.Encoding.utf8)
        let otherData = "something else".data(using: String.Encoding.utf8)
        
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
            return request.path.contains("foo")
        }
        server.mockResponse(status: 202) { request in
            return request.path.contains("bar")
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
        server.mockResponse(endpoint: "GET /bar", status: 202)
        server.mockResponse(endpoint: "GET /bar/baz", status: 203)
        server.mockResponse(endpoint: "GET /", status: 204)
        server.mockResponse(status: 500) // default fallback
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/bar") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/bar?a=1") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/bar?a=1&b=2") { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        request("GET", "/bar/baz") { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        request("GET", "/") { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
        }
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500, "Method doesn't match")
        }
        
        // If `matcher` and `endpoint` are both given, `endpoint`
        // takes precedence:
        //
        server.mockResponse(endpoint: "GET /both", status: 201) { req in return false }
        request("GET", "/both") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
    func testResponseMocking_matcher_viaEndpointParameter_methodOnly() {
        server.mockResponse(endpoint: "GET", status: 201)
        server.mockResponse(status: 500) // default fallback
        
        request("GET", "") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("GET", "/bar") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        request("POST", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 500, "Method doesn't match")
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
        let delayToTest: TimeInterval = 0.5
        
        // First try with NO delay:
        //
        server.mockResponse(status: 205, delay: 0)
        
        let noDelayStartDate = Date()
        request("GET", "/foo") { data, response, error in
            let endDate = Date()
            XCTAssertEqual(response.statusCode, 205)
            XCTAssertLessThan(endDate.timeIntervalSince(noDelayStartDate), 0.1)
        }
        
        // Then try with the delay:
        //
        server.clearMockResponses()
        server.mockResponse(status: 201, delay: delayToTest)
        
        let withDelayStartDate = Date()
        request("GET", "/foo") { data, response, error in
            let endDate = Date()
            XCTAssertEqual(response.statusCode, 201)
            XCTAssertGreaterThan(endDate.timeIntervalSince(withDelayStartDate), delayToTest)
        }
    }
    
    func testResponseMocking_jsonString() {
        server.mockJSONResponse(status: 501, json: "{\"greeting\": \"Moro\"}")
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 501)
            XCTAssertEqual(response.headerWithName("Content-Type"), "application/json")
            XCTAssertEqual(String(data: data, encoding: String.Encoding.utf8), "{\"greeting\": \"Moro\"}")
        }
    }
    
    func testResponseMocking_jsonObject() {
        server.mockJSONResponse(status: 501, object: ["greeting": "Moro"])
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 501)
            XCTAssertEqual(response.headerWithName("Content-Type"), "application/json")
            XCTAssertEqual(String(data: data, encoding: String.Encoding.utf8), "{\"greeting\":\"Moro\"}")
        }
    }
    
    func testResponseMocking_AdHoc() {
        var requestReceivedByHandler: HTTPRequest?
        server.mockAdHocResponse { request in
            requestReceivedByHandler = request
            return MockResponse(
                statusCode: 507,
                data: "adhoc".data(using: .utf8),
                headers: [
                    "X-Adhoc": "adhoc!"
                ])
        }
        
        request("GET", "/foo/bar%20baz?a=b") { data, response, error in
            XCTAssertNotNil(requestReceivedByHandler)
            XCTAssertEqual(requestReceivedByHandler!.method, "GET")
            XCTAssertEqual(requestReceivedByHandler!.path, "/foo/bar%20baz")
            XCTAssertEqual(requestReceivedByHandler!.query["a"], "b")
            
            XCTAssertEqual(response.statusCode, 507)
            XCTAssertEqual(String(data: data, encoding: .utf8), "adhoc")
            XCTAssertEqual(response.headerWithName("X-Adhoc"), "adhoc!")
        }
        
        server.clearAllMockingState()
        
        request("GET", "/foo/bar%20baz?a=b") { data, response, error in
            XCTAssertEqual(response.statusCode, 200)
        }
    }
    
    func testResponseMocking_AdHoc_TakesPrecedenceOverStaticMockResponses() {
        server.mockResponse(endpoint: nil, status: 300)
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 300)
        }
        
        server.mockAdHocResponse { request in
            return MockResponse(
                statusCode: 507,
                data: nil,
                headers: nil)
        }
        
        request("GET", "/foo") { data, response, error in
            XCTAssertEqual(response.statusCode, 507)
        }
    }
    
    func testResponseMocking_AdHoc_InvokedInOrder_SomeReturnNil() {
        server.mockResponse(endpoint: nil, status: 300)
        
        server.mockAdHocResponse { request in
            guard request.path.contains("first") else { return nil }
            return MockResponse(statusCode: 501, data: nil, headers: nil)
        }
        server.mockAdHocResponse { request in
            guard request.path.contains("second") else { return nil }
            return MockResponse(statusCode: 502, data: nil, headers: nil)
        }
        server.mockAdHocResponse { request in
            guard request.path.contains("third") else { return nil }
            return MockResponse(statusCode: 503, data: nil, headers: nil)
        }
        
        request("GET", "/first") { data, response, error in
            XCTAssertEqual(response.statusCode, 501, "Matches 1st ad-hoc handler")
        }
        request("GET", "/second") { data, response, error in
            XCTAssertEqual(response.statusCode, 502, "Matches 2nd ad-hoc handler")
        }
        request("GET", "/third") { data, response, error in
            XCTAssertEqual(response.statusCode, 503, "Matches 3rd ad-hoc handler")
        }
        request("GET", "/fourth") { data, response, error in
            XCTAssertEqual(response.statusCode, 300, "Matches none of the ad-hoc handlers")
        }
    }
}
