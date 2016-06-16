//
//  Assertions.swift
//  Punos
//
//  Created by Ali Rantakari on 16/06/2016.
//  Copyright © 2016 Ali Rantakari. All rights reserved.
//

import XCTest


func AssertDoesNotThrowError<T>(@autoclosure expression: () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do {
        try expression()
    } catch {
        XCTFail("Expression threw error - \(message) - \(error)", file: file, line: line)
    }
}
