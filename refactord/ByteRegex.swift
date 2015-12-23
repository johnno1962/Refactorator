//
//  ByteRegex.swift
//  refactord
//
//  Created by John Holdsworth on 20/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/ByteRegex.swift#4 $
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

    init( pattern: String ) {
        let error = regcomp( &regex, pattern, REG_EXTENDED|REG_ENHANCED )
        if error != 0 {
            var errbuff = [Int8]( count: 1024, repeatedValue: 0 )
            regerror( error, &regex, &errbuff, errbuff.count )
            xcode.error( "Error in regex '\(pattern)': \(String.fromCString( errbuff ))" )
        }
        groups = 1 + pattern.characters.filter { $0 == "(" } .count
    }

    func match( input: NSData ) -> [regmatch_t]? {
        var matches = [regmatch_t]( count: groups, repeatedValue: regmatch_t() )
        let error = regexec( &regex, UnsafePointer<Int8>(input.bytes), matches.count, &matches, 0 )
        if error != 0 && error != REG_NOMATCH {
            var errbuff = [Int8]( count: 1024, repeatedValue: 0 )
            regerror( error, &regex, &errbuff, errbuff.count )
            xcode.error( "Error in match: \(String.fromCString( errbuff ))" )
        }
        return error == 0 ? matches : nil
    }

    deinit {
        regfree( &regex )
    }

}
