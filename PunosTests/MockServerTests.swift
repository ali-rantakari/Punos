//
//  MockServerTests.swift
//  PunosTests
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import Punos

class MockServerTests: MockServerTestCase {
    
    func testStartupAndShutdownEffectOnAPI() {
        let s = MockHTTPServer()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        s.stop() // Already stopped; shouldn't do anything:
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        try! s.start(preferredPorts: [8888])
        
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.port, 8888)
        XCTAssertEqual(s.baseURLString, "http://localhost:8888")
        
        do {
            try s.start(preferredPorts: [8888]) // Same port
            XCTFail("start() should throw error: already running")
        } catch let error {
            XCTAssertNotNil(error)
        }
        do {
            try s.start(preferredPorts: [8889]) // Different port
            XCTFail("start() should throw error: already running")
        } catch let error {
            XCTAssertNotNil(error)
        }
        
        s.stop()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        s.stop() // Already stopped; shouldn't do anything:
        s.stop()
        s.stop()
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        // Start it again!
        try! s.start(preferredPorts: [8888])
        
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.port, 8888)
        XCTAssertEqual(s.baseURLString, "http://localhost:8888")
        
        s.stop()
        
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
        
        s.stop() // Already stopped; shouldn't do anything:
        s.stop()
        s.stop()
        XCTAssertFalse(s.isRunning)
        XCTAssertEqual(s.port, 0)
        XCTAssertNil(s.baseURLString)
    }
    
    func testPortPreferences() {
        let ports: [in_port_t] = [8081, 8082, 8083]
        
        let s1 = MockHTTPServer()
        AssertDoesNotThrowError(try s1.start(preferredPorts: ports))
        XCTAssertTrue(s1.isRunning)
        XCTAssertEqual(s1.port, 8081)
        
        let s2 = MockHTTPServer()
        AssertDoesNotThrowError(try s2.start(preferredPorts: ports))
        XCTAssertTrue(s2.isRunning)
        XCTAssertEqual(s2.port, 8082)
        
        let s3 = MockHTTPServer()
        AssertDoesNotThrowError(try s3.start(preferredPorts: ports))
        XCTAssertTrue(s3.isRunning)
        XCTAssertEqual(s3.port, 8083)
        
        let s4 = MockHTTPServer()
        XCTAssertThrowsError(try s4.start(preferredPorts: ports))
        
        s1.stop()
        s2.stop()
        s3.stop()
    }
    
    func testPendingRequestsAreKilledUponShutdown() {
        let s = MockHTTPServer()
        try! s.start(preferredPorts: [8888])
        
        s.mockResponse(status: 210, delay: 2)
        requestThatCanFail("GET", "/i-will-be-delayed", port: s.port, wait: false) { data, response, error in
            XCTAssertNil(response, "This request should be interrupted when server.stop() is called")
            XCTAssertNotNil(error, "This request should be interrupted when server.stop() is called")
        }
        
        // Give the above request some time to reach the server, so that
        // the server accepts the socket and starts the (delayed) response
        // processing:
        //
        Thread.sleep(forTimeInterval: 0.1)
        
        // Then stop the server while it's still processing the above
        // request. It should cancel the request processing and shut
        // down the client socket.
        //
        s.stop()
        
        waitForExpectations(timeout: 3) { error in
            XCTAssertNil(error, "\(String(describing: error))")
        }
    }
    
    func testLatestRequestsGetters() {
        request("GET", "/gettersson")
        request("HEAD", "/headster")
        
        let requestData = "i used to be with it".data(using: String.Encoding.utf8)
        request("POST", "/foo/bar?a=0&b=2&a=1&c=&d=%C3%A5", data: requestData, headers: ["X-Eka":"eka", "X-Toka":"toka"]) { data, response, error in
            XCTAssertEqual(self.server.latestRequests.count, 3)
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /gettersson",
                "HEAD /headster",
                "POST /foo/bar",
                ])
            
            XCTAssertNotNil(self.server.lastRequest)
            
            if let lastRequest = self.server.lastRequest {
                XCTAssertEqual(lastRequest.endpoint, "POST /foo/bar")
                XCTAssertEqual(lastRequest.method, "POST")
                XCTAssertEqual(lastRequest.path, "/foo/bar")
                XCTAssertEqual(lastRequest.query.pairs[0].0, "a")
                XCTAssertEqual(lastRequest.query.pairs[0].1, "0")
                XCTAssertEqual(lastRequest.query.pairs[1].0, "b")
                XCTAssertEqual(lastRequest.query.pairs[1].1, "2")
                XCTAssertEqual(lastRequest.query.pairs[2].0, "a")
                XCTAssertEqual(lastRequest.query.pairs[2].1, "1")
                XCTAssertEqual(lastRequest.query.dictionary, ["a":"1", "b":"2", "c":"", "d":"å"])
                XCTAssertEqual(lastRequest.headers["X-Eka"], "eka")
                XCTAssertEqual(lastRequest.headers["X-Toka"], "toka")
                XCTAssertEqual(lastRequest.data, "i used to be with it".data(using: String.Encoding.utf8))
            } else {
                XCTFail("lastRequest can’t be nil")
            }
            
            self.server.clearLatestRequests()
            
            XCTAssertEqual(self.server.latestRequests.count, 0)
            XCTAssertNil(self.server.lastRequest)
        }
        
        for path in ["/", "/foo", "/foo/bar", "/foo/bar?"] {
            request("POST", path) { _, _, _ in
                XCTAssertEqual(self.server.lastRequest?.query.count, 0,
                               "Expected empty query for URL path '\(path)'")
            }
        }
    }
    
    func testManyRequestsInQuickSuccession() {
        server.mockResponse(status: 201, onlyOnce: true)
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 203, onlyOnce: true)
        server.mockResponse(status: 204, onlyOnce: true)
        server.mockResponse(status: 205, onlyOnce: true)
        
        let waitBetweenRequestSends: TimeInterval = 0.1
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo5") { data, response, error in
            XCTAssertEqual(response.statusCode, 205)
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /foo1",
                "GET /foo2",
                "GET /foo3",
                "GET /foo4",
                "GET /foo5",
                ])
        }
    }
    
    func testConcurrentRequests() {
        server.mockResponse(status: 201, delay: 0.5, onlyOnce: true)
        server.mockResponse(status: 202, delay: 0.1, onlyOnce: true)
        server.mockResponse(status: 203, delay: 0.2, onlyOnce: true)
        server.mockResponse(status: 204, delay: 0.1, onlyOnce: true)
        server.mockResponse(status: 205, onlyOnce: true)
        
        let waitBetweenRequestSends: TimeInterval = 0.05
        
        let finishedRequestStatusesLock = NSLock()
        var finishedRequestStatuses = [Int]()
        func statusFinished(_ status: Int) {
            finishedRequestStatusesLock.lock()
            finishedRequestStatuses.append(status)
            finishedRequestStatusesLock.unlock()
        }
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            statusFinished(response.statusCode)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
            statusFinished(response.statusCode)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
            statusFinished(response.statusCode)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
            statusFinished(response.statusCode)
        }
        Thread.sleep(forTimeInterval: waitBetweenRequestSends)
        request("GET", "/foo5", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 205)
            statusFinished(response.statusCode)
        }
        
        waitForExpectations(timeout: 2) { error in
            if error != nil {
                XCTFail("Request error: \(String(describing: error))")
                return
            }
            
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /foo1",
                "GET /foo2",
                "GET /foo3",
                "GET /foo4",
                "GET /foo5",
                ])
            
            // The first request (that got the status 201) should have
            // gotten its response the _last_, due to the long delay):
            XCTAssertEqual(finishedRequestStatuses.count, 5)
            XCTAssertEqual(finishedRequestStatuses.last, 201)
        }
    }
    
    func testCommonResponseModifier_noMockedResponsesConfigured() {
        let commonData = "common override".data(using: String.Encoding.utf8)
        server.commonResponseModifier = { response in
            return response.copyWithChanges(statusCode: 207, data: commonData, headers: ["Date": "today"])
        }
        
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(response.statusCode, 207)
            XCTAssertEqual(response.allHeaderNames, ["Date", "Connection", "Content-Length"])
            XCTAssertEqual(response.headerWithName("Date"), "today")
            XCTAssertEqual(data, commonData)
        }
    }
    
    func testCommonResponseModifier_baseMockedResponseConfigured() {
        server.mockResponse(status: 200)
        
        let commonData = "common override".data(using: String.Encoding.utf8)
        server.commonResponseModifier = { response in
            return response.copyWithChanges(statusCode: 207, data: commonData, headers: ["Date": "today"])
        }
        
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(response.statusCode, 207)
            XCTAssertEqual(response.allHeaderNames, ["Date", "Connection", "Content-Length"])
            XCTAssertEqual(response.headerWithName("Date"), "today")
            XCTAssertEqual(data, commonData)
        }
    }
    
    func testCommonResponseModifier_calledForEveryRequest() {
        var counter = 0
        
        server.commonResponseModifier = { response in
            counter += 1
            return response
        }
        
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(counter, 1)
        }
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(counter, 2)
        }
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(counter, 3)
        }
    }
    
    func testStreamedRequest_chunkedTransferEncoding() {
        let testDataFilePath = "/usr/share/dict/words"
        let testData = try? Data(contentsOf: URL(fileURLWithPath: testDataFilePath))
        
        let expectation: XCTestExpectation = self.expectation(description: "Chunked request")
        
        let request = NSMutableURLRequest(url: URL(string: "\(server.baseURLString ?? "")/stream")!)
        request.httpMethod = "POST"
        request.addValue("Chunked", forHTTPHeaderField: "Transfer-Encoding")
        
        // Note: We do NOT set a value for the "Content-Length" header here.
        // This makes NSURLSession use "Transfer-Encoding: Chunked".
        
        class DataProviderDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
            let expectation: XCTestExpectation?
            let testDataFilePath: String
            init(_ expectation: XCTestExpectation, _ testDataFilePath: String) {
                self.expectation = expectation
                self.testDataFilePath = testDataFilePath
            }
            
            @objc func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
                completionHandler(InputStream(fileAtPath: testDataFilePath)!)
            }
            @objc func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
                print("bytesSent:\(bytesSent), totalBytesSent:\(totalBytesSent), totalBytesExpectedToSend:\(totalBytesExpectedToSend)")
            }
            @objc func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                expectation?.fulfill()
                completionHandler(.allow)
            }
        }
        
        let urlSession = URLSession(
            configuration: URLSessionConfiguration.default,
            delegate: DataProviderDelegate(expectation, testDataFilePath),
            delegateQueue: nil)
        urlSession.uploadTask(withStreamedRequest: request as URLRequest).resume()
        
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Request expectation timeout error: \(String(describing: error))")
            
            if error == nil {
                let receivedData = self.server.lastRequest?.data
                
                XCTAssertEqual(self.server.lastRequest?.headers["Transfer-Encoding"], "Chunked")
                
                // Avoid failing on the data equality assertion (the file is so large
                // that the length of the error message in Xcode will bog down the whole editor.)
                //
                XCTAssertEqual(receivedData?.count, testData?.count)
                if receivedData?.count == testData?.count {
                    XCTAssertEqual(receivedData, testData)
                }
            }
        }
    }
    
    func testRequestObserver() {
        var observedRequests1: [HTTPRequest] = []
        var observedRequests2: [HTTPRequest] = []
        
        server.addRequestObserver { request in
            observedRequests1.append(request)
        }
        server.addRequestObserver { request in
            observedRequests2.append(request)
        }

        XCTAssertEqual(observedRequests1.count, 0)
        XCTAssertEqual(observedRequests2.count, 0)
        
        request("GET", "/foo1") { data, response, error in
            XCTAssertEqual(observedRequests1.count, 1)
            XCTAssertEqual(observedRequests2.count, 1)
        }
        
        request("GET", "/foo2") { data, response, error in
            XCTAssertEqual(observedRequests1.count, 2)
            XCTAssertEqual(observedRequests2.count, 2)
        }
        
        XCTAssertEqual(observedRequests1[0].endpoint, "GET /foo1")
        XCTAssertEqual(observedRequests1[1].endpoint, "GET /foo2")
        XCTAssertEqual(observedRequests2[0].endpoint, "GET /foo1")
        XCTAssertEqual(observedRequests2[1].endpoint, "GET /foo2")

        server.clearRequestObservers()
        observedRequests1.removeAll()
        observedRequests2.removeAll()

        request("GET", "/foo3") { data, response, error in
            XCTAssertEqual(observedRequests1.count, 0)
            XCTAssertEqual(observedRequests2.count, 0)
        }
    }
    
    func testIPv4Support() {
        server.mockResponse(status: 201)
        
        request("GET", "/foo", host: "127.0.0.1") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
    func testIPv6Support() {
        server.mockResponse(status: 201)
        
        request("GET", "/foo", host: "[::1]") { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
    }
    
}
