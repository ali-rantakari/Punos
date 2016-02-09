//
//  HTTPRequestTests.swift
//  Punos
//
//  Created by Ali Rantakari on 9.2.16.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
import GCDWebServers
@testable import Punos

class HTTPRequestTests: XCTestCase {
    
    func testInitFromGCDWebServerRequest_empty() {
        let gr = GCDWebServerRequest()
        let req = HTTPRequest(gr)
        XCTAssertEqual(req.method, "")
        XCTAssertEqual(req.path, "")
        XCTAssertEqual(req.query, [:])
        XCTAssertEqual(req.headers, [:])
        XCTAssertNil(req.data)
    }
    
    func testInitFromGCDWebServerRequest_noData() {
        let gr = GCDWebServerRequest(
            method: "POST",
            url: NSURL(string: "http://localhost:1234/foo/bar/baz"),
            headers: ["X-Foo":"hey there"],
            path: "/foo/bar/baz",
            query: ["wop":"doo"])
        
        let req = HTTPRequest(gr)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/foo/bar/baz")
        XCTAssertEqual(req.query, ["wop":"doo"])
        XCTAssertEqual(req.headers, ["X-Foo":"hey there"])
        XCTAssertNil(req.data)
    }
    
    // TODO: Test GCDWebServerDataRequest (not easy because it doesn't have a public setter for .data)
    
}
