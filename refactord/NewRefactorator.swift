//
//  NewRefactorator.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/NewRefactorator.swift#3 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

@objc public class NewRefactorator : Refactorator, RefactoratorRequest {

    var indexdb: IndexDB!

    public func refactorFile( filePath: String, byteOffset: Int32, oldValue: String,
            logDir: String, graph: String?, indexDB: String, plugin: RefactoratorResponse ) -> Int32 {

        xcode = plugin

        modules.removeAll()
        patches.removeAll()
        overrideUSR = nil
        usrToPatch = nil

        let url = NSURL( fileURLWithPath: filePath )
        if let directory = url.URLByDeletingLastPathComponent?.path,
                fileName = url.lastPathComponent, data = NSData( contentsOfFile: filePath ) {
            let filename = fileName.lowercaseString
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

            indexdb = IndexDB( dbPath: indexDB )

            usrToPatch = indexdb.usrInFile( fileName, filename: filename, directory: directory, line: line, col: col )

            if usrToPatch != nil {
                xcode.foundUSR( usrToPatch )

                patches = indexdb.entitiesForUSR( usrToPatch, oldValue: oldValue )
                Entity.sort( &patches )
                for entity in patches {
                    if let contents = NSData( contentsOfFile: entity.file ), patch = entity.patchText( contents, value: oldValue ) {
                        xcode.willPatchFile( entity.file, line:entity.line, col: entity.col, text: patch )
                    }
                }

                return Int32(patches.count)
//
//                xcode.log( "<p>" )
//
//                SK = SourceKit()
//                let xcodeBuildLogs = LogParser( logDir: logDir )
//                guard let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
//                    line.containsString( " -primary-file \(filePath) " ) ||
//                        line.containsString( " -primary-file \"\(filePath)\" " ) } ) else {
//                            xcode.error( "Could not find compiler arguments in \(logDir). Have you built all files in the project?" )
//                            return -1
//                }
//                return searchUSR( xcodeBuildLogs, argv: argv, compilerArgs: SK.array( argv ), oldValue: oldValue, graph: graph )
            }
            else {
                xcode.error( "Unable to locate public or internal symbol associated with selection. " +
                                "Has the project completed Indexing?" )
            }
        }

        return -1//super.refactorFile( filePath, byteOffset: byteOffset, oldValue: oldValue, logDir: logDir, graph: graph, plugin: plugin )
    }

}