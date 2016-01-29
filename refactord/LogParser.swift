//
//  LogParser.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LogParser.swift#19 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class LogParser {

    private let recentFirstLogs: [String]

    init( logDir: String ) {
        recentFirstLogs = TaskGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog" ).sequence.map { $0 }
    }

    func compilerArgumentsMatching( matcher: ( line: String ) -> Bool ) -> [String]? {

        for gzippedBuildLog in recentFirstLogs {
            for line in TaskGenerator( command: "gunzip <\"\(gzippedBuildLog)\"", lineSeparator: "\r" ).sequence {
                if matcher( line: line ) {
                    let spaceToTheLeftOfAnOddNumberOfQoutes = " (?=[^\"]*\"(([^\"]*\"){2})*[^\"]* -o )"
                    let line = line
                        .stringByTrimmingCharactersInSet( NSCharacterSet.whitespaceAndNewlineCharacterSet() )
                        .stringByReplacingOccurrencesOfString( "\\\"", withString: "---" )
                        .stringByReplacingOccurrencesOfString( spaceToTheLeftOfAnOddNumberOfQoutes,
                            withString: "___", options: .RegularExpressionSearch, range: nil )
                        .stringByReplacingOccurrencesOfString( "\"", withString: "" )
                    return cleanup( line.componentsSeparatedByString( " " )
                        .map { $0.stringByReplacingOccurrencesOfString( "___", withString: " " )
                                .stringByReplacingOccurrencesOfString( "---", withString: "\"" ) } )
                }
            }
        }

        return nil
    }

    private func cleanup( argv: [String] ) -> [String] {
        var out = [String]()

        var i=1
        while i<argv.count {
            let arg = argv[i]
            if arg == "-frontend" {
                out.append( "-Xfrontend" )
                out.append( "-j4" )
            }
            else if arg == "-primary-file" {
            }
            else if arg.hasPrefix( "-emit-" ) ||
                    arg == "-serialize-diagnostics-path" {
                i += 1
            }
            else if arg == "-o" {
                break
            }
            else {
                out.append( arg )
            }
            i += 1
        }

        return out
    }

}
