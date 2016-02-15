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
        
        try! s.start(8888)
        
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.port, 8888)
        XCTAssertEqual(s.baseURLString, "http://localhost:8888")
        
        do {
            try s.start(8888) // Same port
            XCTFail("start() should throw error: already running")
        } catch let error {
            XCTAssertNotNil(error)
        }
        do {
            try s.start(8889) // Different port
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
        try! s.start(8888)
        
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
    
    func testPendingRequestsAreKilledUponShutdown() {
        server.mockResponse(status: 210, delay: 2)
        requestThatCanFail("GET", "/i-will-be-delayed", wait: false) { data, response, error in
            XCTAssertNil(response, "This request should be interrupted when server.stop() is called")
            XCTAssertNotNil(error, "This request should be interrupted when server.stop() is called")
        }
        
        // Give the above request some time to reach the server, so that
        // the server accepts the socket and starts the (delayed) response
        // processing:
        //
        NSThread.sleepForTimeInterval(0.1)
        
        // Then stop the server while it's still processing the above
        // request. It should cancel the request processing and shut
        // down the client socket.
        //
        server.stop()
        
        waitForExpectationsWithTimeout(3) { error in
            XCTAssertNil(error, "\(error)")
        }
    }
    
    func testLatestRequestsGetters() {
        request("GET", "/gettersson")
        request("HEAD", "/headster")
        
        let requestData = "i used to be with it".dataUsingEncoding(NSUTF8StringEncoding)
        request("POST", "/foo/bar?a=1&b=2", data: requestData, headers: ["X-Eka":"eka", "X-Toka":"toka"]) { data, response, error in
            XCTAssertEqual(self.server.latestRequests.count, 3)
            XCTAssertEqual(self.server.latestRequestEndpoints, [
                "GET /gettersson",
                "HEAD /headster",
                "POST /foo/bar",
                ])
            
            XCTAssertNotNil(self.server.lastRequest)
            if self.server.lastRequest != nil {
                XCTAssertEqual(self.server.lastRequest?.endpoint, "POST /foo/bar")
                XCTAssertEqual(self.server.lastRequest?.method, "POST")
                XCTAssertEqual(self.server.lastRequest?.path, "/foo/bar")
                XCTAssertEqual(self.server.lastRequest!.query, ["a":"1", "b":"2"])
                XCTAssertEqual(self.server.lastRequest!.headers["X-Eka"], "eka")
                XCTAssertEqual(self.server.lastRequest!.headers["X-Toka"], "toka")
                XCTAssertEqual(self.server.lastRequest?.data, "i used to be with it".dataUsingEncoding(NSUTF8StringEncoding))
            }
            
            self.server.clearLatestRequests()
            
            XCTAssertEqual(self.server.latestRequests.count, 0)
            XCTAssertNil(self.server.lastRequest)
        }
    }
    
    func testManyRequestsInQuickSuccession() {
        server.mockResponse(status: 201, onlyOnce: true)
        server.mockResponse(status: 202, onlyOnce: true)
        server.mockResponse(status: 203, onlyOnce: true)
        server.mockResponse(status: 204, onlyOnce: true)
        server.mockResponse(status: 205, onlyOnce: true)
        
        let waitBetweenRequestSends: NSTimeInterval = 0.01
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
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
        
        let waitBetweenRequestSends: NSTimeInterval = 0.05
        
        let finishedRequestStatusesLock = NSLock()
        var finishedRequestStatuses = [Int]()
        func statusFinished(status: Int) {
            finishedRequestStatusesLock.lock()
            finishedRequestStatuses.append(status)
            finishedRequestStatusesLock.unlock()
        }
        
        request("GET", "/foo1", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 201)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo2", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 202)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo3", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 203)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo4", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 204)
            statusFinished(response.statusCode)
        }
        NSThread.sleepForTimeInterval(waitBetweenRequestSends)
        request("GET", "/foo5", wait: false) { data, response, error in
            XCTAssertEqual(response.statusCode, 205)
            statusFinished(response.statusCode)
        }
        
        waitForExpectationsWithTimeout(2) { error in
            if error != nil {
                XCTFail("Request error: \(error)")
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
        let commonData = "common override".dataUsingEncoding(NSUTF8StringEncoding)
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
        
        let commonData = "common override".dataUsingEncoding(NSUTF8StringEncoding)
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
        let testData = NSData(contentsOfFile: testDataFilePath)
        
        let expectation: XCTestExpectation = expectationWithDescription("Chunked request")
        
        let request = NSMutableURLRequest(URL: NSURL(string: "\(server.baseURLString ?? "")/stream")!)
        request.HTTPMethod = "POST"
        request.addValue("Chunked", forHTTPHeaderField: "Transfer-Encoding")
        
        // Note: We do NOT set a value for the "Content-Length" header here.
        // This makes NSURLSession use "Transfer-Encoding: Chunked".
        
        class DataProviderDelegate: NSObject, NSURLSessionTaskDelegate, NSURLSessionDataDelegate {
            let expectation: XCTestExpectation?
            let testDataFilePath: String
            init(_ expectation: XCTestExpectation, _ testDataFilePath: String) {
                self.expectation = expectation
                self.testDataFilePath = testDataFilePath
            }
            
            @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, needNewBodyStream completionHandler: (NSInputStream?) -> Void) {
                completionHandler(NSInputStream(fileAtPath: testDataFilePath))
            }
            @objc func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
                print("bytesSent:\(bytesSent), totalBytesSent:\(totalBytesSent), totalBytesExpectedToSend:\(totalBytesExpectedToSend)");
            }
            @objc func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
                expectation?.fulfill()
                completionHandler(.Allow)
            }
        }
        
        let urlSession = NSURLSession(
            configuration: NSURLSessionConfiguration.defaultSessionConfiguration(),
            delegate: DataProviderDelegate(expectation, testDataFilePath),
            delegateQueue: nil)
        urlSession.uploadTaskWithStreamedRequest(request).resume()
        
        waitForExpectationsWithTimeout(10) { error in
            XCTAssertNil(error, "Request expectation timeout error: \(error)")
            
            if error == nil {
                let receivedData = self.server.lastRequest?.data
                
                XCTAssertEqual(self.server.lastRequest?.headers["Transfer-Encoding"], "Chunked")
                
                // Avoid failing on the data equality assertion (the file is so large
                // that the length of the error message in Xcode will bog down the whole editor.)
                //
                XCTAssertEqual(receivedData?.length, testData?.length)
                if receivedData?.length == testData?.length {
                    XCTAssertEqual(receivedData, testData)
                }
            }
        }
    }
    
}
