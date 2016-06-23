//
//  HttpRequest.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

internal class HttpRequest {
    internal var path: String = ""
    internal var queryParams: [(String, String)] = []
    internal var method: String = ""
    internal var headers: [String: String] = [:]
    internal var body: [UInt8] = []
    internal var address: String? = ""
    internal var params: [String: String] = [:]
}
