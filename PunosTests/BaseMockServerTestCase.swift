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
    
    
    func request(method: String, _ path: String, data: NSData? = nil, headers: [String:String]? = nil, timeout: NSTimeInterval = 2, wait: Bool = true, completionHandler: ((NSData, NSHTTPURLResponse, NSError?) -> Void)? = nil) {
        let expectation: XCTestExpectation = expectationWithDescription("Request \(method) \(path)")
        
        let request = NSMutableURLRequest(URL: NSURL(string: "\(server.baseURLString ?? "")\(path)")!)
        request.HTTPMethod = method
        if let headers = headers {
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        }
        if let data = data {
            request.HTTPBody = data
        }
        
        NSURLSession.sharedSession().dataTaskWithRequest(request) { data, response, error in
            guard let response = response as? NSHTTPURLResponse else {
                XCTFail("The response should always be an NSHTTPURLResponse")
                return
            }
            completionHandler?(data!, response, error)
            expectation.fulfill()
            }.resume()
        
        if wait {
            waitForExpectationsWithTimeout(timeout) { error in
                if error != nil {
                    XCTFail("Request error: \(error)")
                }
            }
        }
    }
    
}
