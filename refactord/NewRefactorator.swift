//
//  NewRefactorator.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/NewRefactorator.swift#24 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

@objc public class NewRefactorator: Refactorator, RefactoratorRequest {

    public func refactorFile( _ filePath: String, byteOffset: Int32, oldValue: String,
            logDir: String, graph: String?, indexDB: String, plugin: RefactoratorResponse ) -> Int32 {

        if graph == nil {

            xcode = plugin

            if let data = NSData( contentsOfFile: filePath ), let indexdb = IndexDB( dbPath: indexDB ) {

                let bytes = data.bytes.assumingMemoryBound(to: UInt8.self), end = Int(byteOffset), nl = "\n".utf8.first!
                var pos = 0, line = 1, col = 1

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

                usrToPatch = indexdb.usrInFile( filePath: filePath, line: line, col: col )

                if usrToPatch == nil && parseForUSR( filePath: filePath, byteOffset: byteOffset, logDir: logDir ) == nil {
                    return -1
                }

                if usrToPatch != nil {
                    xcode.foundUSR( usrToPatch, text: demangle( usr: usrToPatch ) )

                    patches = indexdb.entitiesForUSR( usr: usrToPatch, oldValue: oldValue ).sorted(by: <)

                    for entity in patches {
                        if let contents = NSData( contentsOfFile: entity.file ), let patch = entity.patchText( contents: contents, value: oldValue ) {
                            xcode.willPatchFile( entity.file, line: Int32(entity.line), col: Int32(entity.col), text: patch )
                        }
                    }

                    if patches.count != 0 {
                        return Int32(patches.count)
                    }
                }
            }
            else {
                xcode.log( "Error initialising, falling back to previous code" )
            }
        }

        return refactorFile( filePath, byteOffset: byteOffset, oldValue: oldValue, logDir: logDir, graph: graph, plugin: plugin )
    }

}
