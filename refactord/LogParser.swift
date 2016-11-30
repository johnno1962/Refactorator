//
//  LogParser.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LogParser.swift#21 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class LogParser {

    private let recentFirstLogs: [String]

    init( logDir: String ) {
        recentFirstLogs = TaskGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog" ).sequence.map { $0 }
    }

    func compilerArgumentsMatching( matcher: ( _ line: String ) -> Bool ) -> [String]? {

        for gzippedBuildLog in recentFirstLogs {
            for line in TaskGenerator( command: "gunzip <\"\(gzippedBuildLog)\"", lineSeparator: "\r" ).sequence {
                if matcher( line ) {
                    return SK.compilerArgs( buildCommand: line )
                }
            }
        }

        return nil
    }

}
