//
//  UtilityTests.swift
//  Punos
//
//  Created by Ali Rantakari on 16/06/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest
@testable import Punos

class UtilityTests: XCTestCase {
    
    func testPercentDecoding() {
        XCTAssertEqual("".removePercentEncoding(), "")
        XCTAssertEqual("abc".removePercentEncoding(), "abc")
        XCTAssertEqual("𝄞💩".removePercentEncoding(), "𝄞💩")
        XCTAssertEqual("%3A%2F%3Ffoo%26bar".removePercentEncoding(), ":/?foo&bar")
        XCTAssertEqual("%C3%A5%C3%A4%C3%B6".removePercentEncoding(), "åäö")
        XCTAssertEqual("%F0%9D%84%9E%F0%9F%92%A9".removePercentEncoding(), "𝄞💩")
    }
}
