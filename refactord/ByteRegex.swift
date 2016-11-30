//
//  ByteRegex.swift
//  refactord
//
//  Created by John Holdsworth on 20/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/ByteRegex.swift#12 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

extension regmatch_t {

    var range: NSRange {
        return NSMakeRange( Int(rm_so), Int(rm_eo-rm_so) )
    }

}

class ByteRegex {

    var regex = regex_t()
    let groups: Int

    init( pattern: String, cflags: Int32 = REG_EXTENDED|REG_ENHANCED ) {
        let error = regcomp( &regex, pattern, cflags )
        if error != 0 {
            var errbuff = [Int8]( repeating: 0, count: 1024 )
            regerror( error, &regex, &errbuff, errbuff.count )
            print( "ByteRegex: Error in regex '\(pattern)': \(String( cString: errbuff ))" )
        }
        groups = 1 + pattern.characters.filter { $0 == "(" } .count
    }

    func match( input: NSData, mflags: Int32 = 0 ) -> [regmatch_t]? {
        var matches = [regmatch_t]( repeating: regmatch_t(), count: groups )
        let error = regexec( &regex, input.bytes.assumingMemoryBound(to: Int8.self), matches.count, &matches, mflags )
        if error != 0 && error != REG_NOMATCH {
            var errbuff = [Int8]( repeating: 0, count: 1024 )
            regerror( error, &regex, &errbuff, errbuff.count )
            print( "ByteRegex: Error in match: \(String( cString: errbuff ))" )
        }
        return error == 0 ? matches : nil
    }

    deinit {
        regfree( &regex )
    }

}
