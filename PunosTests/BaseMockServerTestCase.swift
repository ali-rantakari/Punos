//
//  BaseMockServerTestCase.swift
//  Punos
//
//  Created by Ali Rantakari on 12.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import Punos

extension NSHTTPURLResponse {
    func headerWithName(name: String) -> String? {
        return (allHeaderFields as? [String:String])?[name]
    }
    var allHeaderNames: Set<String> {
        guard let headers = allHeaderFields as? [String:String] else { return [] }
        return Set(headers.keys) ?? []
    }
}

private let sharedServer = Punos.MockHTTPServer()

/// Base class for test cases that use a mock HTTP server.
///
class MockServerTestCase: XCTestCase {
    
    var server: Punos.MockHTTPServer { return sharedServer }
    
    override class func setUp() {
        super.setUp()
        do {
            if !sharedServer.isRunning {
                try sharedServer.start()
            }
        } catch let error {
            fatalError("Could not start mock server: \(error)")
        }
    }
    
    override func tearDown() {
        super.tearDown()
        server.clearAllMockingState()
    }
    
    
    func requestThatCanFail(method: String, _ path: String, port: in_port_t? = nil, data: NSData? = nil, headers: [String:String]? = nil, timeout: NSTimeInterval = 2, wait: Bool = true, completionHandler: ((NSData?, NSHTTPURLResponse?, NSError?) -> Void)? = nil) {
        let expectation: XCTestExpectation = expectationWithDescription("Request \(method) \(path)")
        
        let request = NSMutableURLRequest(URL: NSURL(string: "http://localhost:\(port ?? server.port)\(path)")!)
        request.HTTPMethod = method
        if let headers = headers {
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        }
        if let data = data {
            request.HTTPBody = data
        }
        
        NSURLSession.sharedSession().dataTaskWithRequest(request) { data, maybeResponse, error in
            completionHandler?(data, maybeResponse as? NSHTTPURLResponse, error)
            expectation.fulfill()
            }.resume()
        
        if wait {
            waitForExpectationsWithTimeout(timeout) { error in
                XCTAssertNil(error, "Request expectation timeout error: \(error)")
            }
        }
    }
    
    func request(method: String, _ path: String, port: in_port_t? = nil, data: NSData? = nil, headers: [String:String]? = nil, timeout: NSTimeInterval = 2, wait: Bool = true, completionHandler: ((NSData, NSHTTPURLResponse, NSError?) -> Void)? = nil) {
        requestThatCanFail(method, path, port: port, data: data, headers: headers, timeout: timeout, wait: wait) { maybeData, maybeResponse, maybeError in
            guard let data = maybeData else {
                XCTFail("Data is expected to be non-nil. Error: \(maybeError)")
                return
            }
            guard let response = maybeResponse else {
                XCTFail("Response is expected to be non-nil. Error: \(maybeError)")
                return
            }
            completionHandler?(data, response, maybeError)
        }
    }
    
}
