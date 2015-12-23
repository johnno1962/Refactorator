//
//  LogParser.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Swifactor/refactord/LogParser.swift#1 $
//
//  Repo: https://github.com/johnno1962/Swifactor
//

import Foundation

class LogParser {

    private let logs: [String]

    init( logDir: String ) {
        logs = LineGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog", eol: "\n" ).sequence().map { $0 }
    }

    func argumentsMatching( matcher: ( line: String ) -> Bool ) -> [String]? {

        for log in logs {
            for line in LineGenerator( command: "gunzip <\"\(log)\"", eol:"\r" ).sequence() {
                if matcher( line: line ) {
                    let spaceToTheLeftOfAnOddNumberOfQoutes = " (?=[^\"]*\"(([^\"]*\"){2})*[^\"]* -o )"
                    var line = line.stringByReplacingOccurrencesOfString( spaceToTheLeftOfAnOddNumberOfQoutes,
                        withString: "___", options: .RegularExpressionSearch, range: nil )
                    line = line.stringByReplacingOccurrencesOfString( "\"", withString: "" )
                    return cleanup( line.componentsSeparatedByString( " " )
                        .map { $0.stringByReplacingOccurrencesOfString( "___", withString: " " ) } )
                }
            }
        }

        return nil
    }

    private func cleanup( args: [String] ) -> [String] {
        var out = [String]()

        var i = 3
        while i < args.count {
            if args[i] == "-o" {
                break
            }

            out.append( args[i] )
            i += 1
        }

        return out
    }

}
