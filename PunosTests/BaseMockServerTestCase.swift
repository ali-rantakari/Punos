//
//  BaseMockServerTestCase.swift
//  Punos
//
//  Created by Ali Rantakari on 12.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import Punos

extension HTTPURLResponse {
    func headerWithName(_ name: String) -> String? {
        return allHeaderFields[name] as? String
    }
    var allHeaderNames: Set<String> {
        return Set(allHeaderFields.keys.compactMap { $0 as? String })
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
    
    
    func requestThatCanFail(_ method: String, _ path: String, host: String = "localhost", port: in_port_t? = nil, data: Data? = nil, headers: [String:String]? = nil, timeout: TimeInterval = 2, wait: Bool = true, completionHandler: ((Data?, HTTPURLResponse?, NSError?) -> Void)? = nil) {
        let expectation: XCTestExpectation = self.expectation(description: "Request \(method) \(path)")
        
        // Note: "localhost" will automatically map to either "127.0.0.1" (IPv4) or
        // "::1" (IPv6) even if only one of the two is available.
        //
        let request = NSMutableURLRequest(url: URL(string: "http://\(host):\(port ?? server.port)\(path)")!)
        request.httpMethod = method
        if let headers = headers {
            #if swift(>=4)
                headers.forEach { request.addValue($0.value, forHTTPHeaderField: $0.key) }
            #else
                headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
            #endif
        }
        if let data = data {
            request.httpBody = data
        }
        
        URLSession.shared.dataTask(with: request as URLRequest) { data, maybeResponse, error in
            completionHandler?(data, maybeResponse as? HTTPURLResponse, error as NSError?)
            expectation.fulfill()
            }.resume()
        
        if wait {
            waitForExpectations(timeout: timeout) { error in
                XCTAssertNil(error, "Request expectation timeout error: \(String(describing: error))")
            }
        }
    }
    
    func request(_ method: String, _ path: String, host: String = "localhost", port: in_port_t? = nil, data: Data? = nil, headers: [String:String]? = nil, timeout: TimeInterval = 2, wait: Bool = true, completionHandler: ((Data, HTTPURLResponse, NSError?) -> Void)? = nil) {
        requestThatCanFail(method, path, host: host, port: port, data: data, headers: headers, timeout: timeout, wait: wait) { maybeData, maybeResponse, maybeError in
            guard let data = maybeData else {
                XCTFail("Data is expected to be non-nil. Error: \(String(describing: maybeError))")
                return
            }
            guard let response = maybeResponse else {
                XCTFail("Response is expected to be non-nil. Error: \(String(describing: maybeError))")
                return
            }
            completionHandler?(data, response, maybeError)
        }
    }
    
}
