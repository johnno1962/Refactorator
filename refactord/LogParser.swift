//
//  LogParser.swift
//  refactoratord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LogParser.swift#4 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class LogParser {

    private let logs: [String]

    init( logDir: String ) {
        logs = LineGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog", eol: "\n" ).sequence().map { $0 }
    }

    func argumentsForFile( filePath: String ) -> [String]? {

        for log in logs {
            for line in LineGenerator( command: "gunzip <\"\(log)\"", eol:"\r" ).sequence() {
                print( line )
                if line.containsString( " -primary-file \(filePath) " ) {
                    return cleanup( line.componentsSeparatedByString( " " ) )
                }
                else if line.containsString( " -primary-file \"\(filePath)\" " ) {
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

    func cleanup( args: [String] ) -> [String] {
        var out = [String]()

        var i = 2
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix( "-target" ) || arg.hasPrefix( "-emit-" ) {
                i += 2
                continue
            }
            else if arg == "-o" {
                break
            }

            out.append( arg )
            i += 1
        }

        return out
    }

}