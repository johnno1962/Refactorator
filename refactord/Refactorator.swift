//
//  Refactorator.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/Refactorator.swift#42 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

/** occurrence of a matching "Unified Symbol Resolution" */
private struct Entity {

    let file: String
    let line: Int32
    let col: Int32

    /** char based regex to find line, column and text in source */
    func regex( text: String ) -> ByteRegex {
        var pattern = "^"
        var line = self.line
        while line > 100 {
            pattern += "(?:[^\n]*\n){100}"
            line -= 100
        }
        var col = self.col, largecol = ""
        while col > 100 {
            largecol += ".{100}"
            col -= 100
        }
        pattern += "(?:[^\n]*\n){\(line-1)}(\(largecol).{\(col-1)}[^\n]*?)(\(text))([^\n]*)"
        return ByteRegex( pattern: pattern )
    }

    /** text logged to refactoring console */
    func patchText( contents: NSData, value: String ) -> String? {
        if let matches = regex( value ).match( contents ) {
            return
                htmlClean( contents, match: matches[1] ) + "<b>" +
                htmlClean( contents, match: matches[2] ) + "</b>" +
                htmlClean( contents, match: matches[3] )
        }
        return "MATCH FAILED line:\(line) column:\(col)"
    }

    func htmlClean( contents: NSData, match: regmatch_t ) -> String {
        return String.fromData( contents.subdataWithRange( match.range ) )?
            .stringByReplacingOccurrencesOfString( "&", withString: "&amp;" )
            .stringByReplacingOccurrencesOfString( "<", withString: "&lt;" ) ?? "CONVERSION FAILED"
    }

}

var xcode: RefactoratorResponse!
var SK: SourceKit!

/** instance published as Distributed Objects service */
@objc public class Refactorator: NSObject, RefactoratorRequest {

    private var usrToPatch: String!
    private var overrideUSR: String?

    /** indexes cached for the life of the daemon */
    private var indexes = [String:(__darwin_time_t,sourcekitd_response_t)]()

    private var modules = Set<String>()
    private var patches = [Entity]()

    private var backups = [String:NSData]()
    private var patched = [String:NSData]()

    public func refactorFile( filePath: String, byteOffset: Int32, oldValue: String, logDir: String, plugin: RefactoratorResponse ) -> Int32 {
        NSLog( "refactord -- refactorFile: \(filePath) \(byteOffset) \(logDir)")

        SK = SourceKit()
        xcode = plugin

        modules.removeAll()
        patches.removeAll()
        overrideUSR = nil
        usrToPatch = nil

        /** find command line arguments for file from build logs */
        let xcodeBuildLogs = LogParser( logDir: logDir )
        guard let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
                line.containsString( " -primary-file \(filePath) " ) ||
                line.containsString( " -primary-file \"\(filePath)\" " ) } ) else {
            xcode.error( "Could not find compiler arguments in \(logDir). Have you built the project?" )
            return -1
        }

        let compilerArgs = SK.array( argv )

        /** fund "USR" for current selection */
        let resp = SK.cursorInfo( filePath, byteOffset: Int64(byteOffset), compilerArgs: compilerArgs )
        if let error = SK.error( resp ) {
            xcode.error( "Cursor fetch error: \(error)" )
            exit(1)
        }

        let dict = sourcekitd_response_get_value( resp )
        var usr = sourcekitd_variant_dictionary_get_string( dict, SK.usrID )
        if usr == nil {
            xcode.error( "Unable to locate public or internal symbol associated with selection." )
            return -1
        }

        /** if function is override refactor function and overridden function */
        let overrides = sourcekitd_variant_dictionary_get_value( dict, SK.overridesID )
        if sourcekitd_variant_get_type( overrides ) == SOURCEKITD_VARIANT_TYPE_ARRAY {
            sourcekitd_variant_array_apply( overrides ) { (_,dict) in
                self.overrideUSR = String.fromCString( usr )
                usr = sourcekitd_variant_dictionary_get_string( dict, SK.usrID )
                return false
            }
        }

        usrToPatch = String.fromCString( usr )
        xcode.foundUSR( usrToPatch )

        /** index all sources included in selection's module */
        processModuleSources( argv, args: compilerArgs, oldValue: oldValue )

        /** if entity is in a framework, index each source of that module as well */
        let module = sourcekitd_variant_dictionary_get_string( dict, SK.moduleID )
        if module != nil {
            modules.insert( String.fromCString( module )! )
        }

        for module in modules {
            xcode.log( "<b>Framework '\(module)':</b><br>" )

            if let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
                line.containsString( " -module-name \(module) " ) && line.containsString( " -primary-file " ) } ) {
                    processModuleSources( argv, args: SK.array( argv ), oldValue: oldValue )
            }
        }

        xcode.indexing( nil )
        return Int32(patches.count)
    }

    private func processModuleSources( argv: [String], args: sourcekitd_object_t, oldValue: String ) {

        for file in argv.filter( { $0.hasSuffix( ".swift" ) } ) {

            let resp: sourcekitd_response_t
            var info = stat()
            if stat( file, &info ) != 0 {
                xcode.log( "Could not stat file: \(file)" )
                continue
            }

            /** use cache if file has not been modified */
            let lastModified = info.st_mtimespec.tv_sec
            if let (lastIndexed,lastResp) = indexes[file] where lastIndexed >= lastModified {
                resp = lastResp
            }
            else {
                xcode.indexing( file )

                resp = SK.indexFile( file, compilerArgs: args )
                if let error = SK.error( resp ) {
                    xcode.log( "Source index error for \(file): \(error)" )
                    SK = SourceKit()
                    continue
                }

                indexes[file] = (lastModified, resp)
            }

            let dict = sourcekitd_response_get_value( resp )

            if overrideUSR != nil  {
                /** ideally override would give us its module */
                traceDependencies( dict )
            }

            traceEntities( dict, oldValue: oldValue, file: file, contents: NSMutableData( contentsOfFile: file ) )
        }
    }

    private func traceDependencies( resp: sourcekitd_variant_t ) {

        let dependencies = sourcekitd_variant_dictionary_get_value( resp, SK.depedenciesID )

        sourcekitd_variant_array_apply( dependencies ) { (_,dict) in

            if sourcekitd_variant_dictionary_get_uid( dict, SK.kindID ) == SK.clangID &&
                    !sourcekitd_variant_dictionary_get_bool( dict, SK.isSystemID ) {
                let module = sourcekitd_variant_dictionary_get_string( dict, SK.nameID )
                if module != nil {
                    self.modules.insert( String.fromCString( module )! )
                }
            }

            self.traceDependencies( dict )
            return true
        }
    }

    private func traceEntities( resp: sourcekitd_variant_t, oldValue: String, file: String, contents: NSMutableData? ) {

        let entities = sourcekitd_variant_dictionary_get_value( resp, SK.entitiesID )

        sourcekitd_variant_array_apply( entities ) { (_,dict) in

            let usrString = sourcekitd_variant_dictionary_get_string( dict, SK.usrID )
            if usrString != nil {

                let entityUSR = String.fromCString( usrString )

                /** if entity == current selection's entity, log and store for patching later */
                if entityUSR == self.usrToPatch || entityUSR == self.overrideUSR {

                    let entity = Entity( file: file,
                        line: Int32(sourcekitd_variant_dictionary_get_int64( dict, SK.lineID )),
                        col: Int32(sourcekitd_variant_dictionary_get_int64( dict, SK.colID )) )

                    if let contents = contents, patch = entity.patchText( contents, value: oldValue ) {
                        xcode.willPatchFile( file, line:entity.line, col: entity.col, text: patch )
                        self.patches.append( entity )
                    }
               }
            }

            self.traceEntities( dict, oldValue: oldValue, file: file, contents: contents )
            return true
        }
    }

    public func refactorFrom( oldValue: String, to newValue: String ) -> Int32 {
        NSLog( "refactorFrom( \(oldValue) to: \(newValue) )")
        backups.removeAll()
        patched.removeAll()

        typealias Closure = () -> ()
        var blocks = [Closure]()

        /** patches performed in reverse in case offsets changed */
        for entity in patches.reverse() {
            if patched[entity.file] == nil {
                backups[entity.file] = NSData( contentsOfFile: entity.file )
                patched[entity.file] = backups[entity.file]
            }

            if let contents = patched[entity.file], matches = entity.regex( oldValue ).match( contents ) {

                /** apply patch, substituting newValue for entity reference */
                let out = NSMutableData()
                out.appendData( contents.subdataWithRange( NSMakeRange( 0, Int(matches[2].rm_so) ) ) )
                out.appendString( newValue )
                out.appendData( contents.subdataWithRange( NSMakeRange( Int(matches[2].rm_eo),
                                                        contents.length-Int(matches[2].rm_eo) ) ) )

                /** log and update in-memory version of source file */
                if let patch = entity.patchText( out, value: newValue ) {
                    blocks.append( { xcode.willPatchFile( entity.file, line:entity.line, col: entity.col, text: patch ) } )
                    patched[entity.file] = out
                }
            }
        }

        for block in blocks.reverse() {
            block()
        }

        return Int32(patches.count)
    }

    public func confirmRefactor() -> Int32 {
        for (file,data) in patched {
            if !data.writeToFile( file, atomically: true ) {
                xcode.error( "Could not save to file: \(file)" )
            }
        }
        let modified = patched.count
        patched.removeAll()
        return Int32(modified)
    }

    public func revertRefactor() -> Int32 {
        for (file,data) in backups {
            if !data.writeToFile( file, atomically: true ) {
                xcode.error( "Could not revert file: \(file)" )
            }
        }
        let modified = backups.count
        backups.removeAll()
        return Int32(modified)
    }

}

extension NSMutableData {

    func appendString( str: String ) -> NSMutableData {
        str.withCString { bytes in
            appendBytes( bytes, length: Int(strlen(bytes)) )
        }
        return self
    }

}
