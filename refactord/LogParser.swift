//
//  LogParser.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LogParser.swift#23 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class LogParser {

    let recentFirstLogs: [String]

    init( logDir: String ) {
        recentFirstLogs = TaskGenerator( command: "ls -t \"\(logDir)\"/*.xcactivitylog" ).sequence.map { $0 }
    }

    func compilerArgumentsMatching( matcher: ( _ line: String ) -> Bool ) -> [String]? {

        for gzippedBuildLog in recentFirstLogs {
            for line in TaskGenerator( command: "gunzip <\"\(gzippedBuildLog)\"", lineSeparator: "\r" ).sequence {
                if matcher( line ) {
                    return compilerArgs( buildCommand: line )
                }
            }
        }

        return nil
    }

    func compilerArgs( buildCommand: String, filelist: [String]? = nil ) -> [String] {
        let spaceToTheLeftOfAnOddNumberOfQoutes = " (?=[^\"]*\"[^\"]*(?:(?:\"[^\"]*){2})* -o )"
        let line = buildCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences( of:"\\\"", with: "---" )
            .replacingOccurrences( of: spaceToTheLeftOfAnOddNumberOfQoutes, with: "___",
                                   options: .regularExpression, range: nil )
            .replacingOccurrences( of:"\"", with: "" )

        let argv = line.components(separatedBy:" " )
                .map { $0.replacingOccurrences( of:"___", with: " " )
                .replacingOccurrences( of:"---", with: "\"" ) }

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
            else if arg == "-filelist" && filelist != nil {
                out += filelist!
                i += 1
            }
            else {
                out.append( arg )
            }
            i += 1
        }

        return out
    }

}
