//
//  LogParser.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LogParser.swift#15 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class LogParser {

    private let recentFirstLogs: [String]

    init( logDir: String ) {
        recentFirstLogs = LineGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog" ).sequence.map { $0 }
    }

    func compilerArgumentsMatching( matcher: ( line: String ) -> Bool ) -> [String]? {

        for gzippedBuildLog in recentFirstLogs {
            for line in LineGenerator( command: "gunzip <\"\(gzippedBuildLog)\"", lineSeparator: "\r" ).sequence {
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

    private func cleanup( argv: [String] ) -> [String] {
        var out = [String]()

        for i in 3..<argv.count {
            if argv[i] == "-o" {
                break
            }

            out.append( argv[i] )
        }

        return out
    }

}
