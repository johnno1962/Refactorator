//
//  NewRefactorator.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/NewRefactorator.swift#10 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

@objc public class NewRefactorator : Refactorator, RefactoratorRequest {

    public func refactorFile( filePath: String, byteOffset: Int32, oldValue: String,
            logDir: String, graph: String?, indexDB: String, plugin: RefactoratorResponse ) -> Int32 {

        xcode = plugin

        patches.removeAll()
        modules.removeAll()
        overrideUSR = nil
        usrToPatch = nil

        if graph == nil, let data = NSData( contentsOfFile: filePath ), indexdb = IndexDB( dbPath: indexDB ) {
            let bytes = UnsafePointer<UInt8>( data.bytes )

            var line = 1, col = 1, pos = 0, end = Int(byteOffset), nl = "\n".utf8.first!

            while pos < end {
                if bytes[pos] == nl {
                    line += 1
                    col = 1
                }
                else {
                    col += 1
                }
                pos += 1
            }

            usrToPatch = indexdb.usrInFile( filePath, line: line, col: col )

            if usrToPatch != nil {
                xcode.foundUSR( usrToPatch )

                if graph != nil {
                    SK = SourceKit()
                    let xcodeBuildLogs = LogParser( logDir: logDir )
                    guard let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
                        line.containsString( " -primary-file \(filePath) " ) ||
                            line.containsString( " -primary-file \"\(filePath)\" " ) } ) else {
                                xcode.error( "Could not find compiler arguments in \(logDir). Have you built all files in the project?" )
                                return -1
                    }
                    return searchUSR( xcodeBuildLogs, argv: argv, compilerArgs: SK.array( argv ), oldValue: oldValue, graph: graph )
                }

                patches = indexdb.entitiesForUSR( usrToPatch, oldValue: oldValue )

                Entity.sort( &patches )
                for entity in patches {
                    if let contents = NSData( contentsOfFile: entity.file ), patch = entity.patchText( contents, value: oldValue ) {
                        xcode.willPatchFile( entity.file, line: entity.line, col: entity.col, text: patch )
                    }
                }

                return Int32(patches.count)
            }
            else {
                xcode.error( "Unable to locate public or internal symbol associated with selection. " +
                                "Has the project completed Indexing?" )
            }
        }
        else {
            if graph == nil {
                xcode.log( "Error initialising, falling back to previous code" )
            }
            return refactorFile( filePath, byteOffset: byteOffset, oldValue: oldValue, logDir: logDir, graph: graph, plugin: plugin )
        }

        return -1
    }

}
