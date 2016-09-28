//
//  Extensions.swift
//
// Copyright © 2016 Peter Zignego,  All rights reserved.
// Adapted to use Vapor by Philip Sidell
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Jay

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

public typealias Time=Double

public extension Double {

    static func slackTimestamp() -> Double {
        #if os(Linux)
            return Double(time(nil))
        #else
            var clock: clock_serv_t = clock_serv_t()
            var timeSpecBuffer: mach_timespec_t = mach_timespec_t(tv_sec: 0, tv_nsec: 0)

            host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &clock)
            clock_get_time(clock, &timeSpecBuffer)
            mach_port_deallocate(mach_task_self_, clock)

            return Double(timeSpecBuffer.tv_sec) + Double(timeSpecBuffer.tv_nsec) * 0.000000001
        #endif
    }

}

internal extension String {

    func slackFormatEscaping() -> String {
        var escapedString = self
        escapedString = escapedString.replacingOccurrences(of: "&", with: "&amp;")
        //escapedString.replace(string: "&", with: "&amp;")
        escapedString = escapedString.replacingOccurrences(of: "<", with: "&lt;")
        //escapedString.replace(string: "<", with: "&lt;")
        escapedString = escapedString.replacingOccurrences(of: ">", with: "&gt;")
        //escapedString.replace(string: ">", with: "&gt;")
        return escapedString
    }

}

public extension String {

    func contains(query: String, caseSensitive: Bool = false) -> Bool {
        if query.isEmpty { return true }
        let (s, q) = caseSensitive ? (self, query) : (self.lowercased(), query.lowercased())
        var chars = s.characters; let qchars = q.characters

        while !chars.isEmpty {
            if chars.starts(with: qchars) { return true }
            chars.removeFirst()
        }

        return false
    }

    func prefixedBy(query: String, caseSensitive: Bool = false) -> Bool {
        let (s, q) = caseSensitive ? (self, query) : (self.lowercased(), query.lowercased())
        return s.characters.starts(with: q.characters)
    }
}

internal extension Array {

    func objectArrayFromDictionaryArray<T>(intializer:([String: Any])->T?) -> [T] {
        var returnValue = [T]()
        for object in self {
            if let dictionary = object as? [String: Any] {
                if let value = intializer(dictionary) {
                    returnValue.append(value)
                }
            }
        }
        return returnValue
    }

}



internal extension Dictionary where Key: ExpressibleByStringLiteral, Value: Any {

    var requestStringFromParameters: String {
        var requestString = ""
        for key in self.keys {
            if let value = self[key] as? String, let encodedValue = value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed) {
                requestString += "&\(key)=\(encodedValue)"
            } else if let value = self[key] as? Int {
                requestString += "&\(key)=\(value)"
            }
        }

        return requestString
    }
}
