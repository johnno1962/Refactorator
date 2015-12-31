//
//  Refactorator.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/Refactorator.swift#28 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

private let isTTY = isatty( STDERR_FILENO ) != 0

/** request types */
private let requestID = sourcekitd_uid_get_from_cstr("key.request")
private let cursorRequestID = sourcekitd_uid_get_from_cstr("source.request.cursorinfo")
private let indexRequestID = sourcekitd_uid_get_from_cstr("source.request.indexsource")

/** request arguments */
private let offsetID = sourcekitd_uid_get_from_cstr("key.offset")
private let sourceFileID = sourcekitd_uid_get_from_cstr("key.sourcefile")
private let compilerArgsID = sourcekitd_uid_get_from_cstr("key.compilerargs")

/** sub entity lists */
private let depedenciesID = sourcekitd_uid_get_from_cstr("key.dependencies")
private let overridesID = sourcekitd_uid_get_from_cstr("key.overrides")
private let entitiesID = sourcekitd_uid_get_from_cstr("key.entities")

/** entity attributes */
private let isSystemID = sourcekitd_uid_get_from_cstr("key.is_system")
private let moduleID = sourcekitd_uid_get_from_cstr("key.modulename")
private let kindID = sourcekitd_uid_get_from_cstr("key.kind")
private let nameID = sourcekitd_uid_get_from_cstr("key.name")
private let lineID = sourcekitd_uid_get_from_cstr("key.line")
private let colID = sourcekitd_uid_get_from_cstr("key.column")
private let usrID = sourcekitd_uid_get_from_cstr("key.usr")

/** kinds */
private let clangID = sourcekitd_uid_get_from_cstr("source.lang.swift.import.module.clang")

private func error( resp: sourcekitd_response_t ) -> String? {
    if sourcekitd_response_is_error( resp ) {
        return String.fromCString( sourcekitd_response_error_get_description( resp ) )
    }
    return nil
}

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
        var col = self.col, colextra = ""
        while col > 100 {
            colextra += ".{100}"
            col -= 100
        }
        pattern += "(?:[^\n]*\n){\(line-1)}(\(colextra).{\(col-1)}[^\n]*?)(\(text))([^\n]*)"
        return ByteRegex( pattern: pattern )
    }

    /** text logged to refactoring console */
    func patchText( contents: NSData, value: String ) -> String? {
        if let matches = regex( value ).match( contents ) {
            let out = NSMutableData()
            out.appendData( contents.subdataWithRange( matches[1].range ) )
            out.appendString( "<b>" )
            out.appendData( contents.subdataWithRange( matches[2].range ) )
            out.appendString( "</b>" )
            out.appendData( contents.subdataWithRange( matches[3].range ) )
            return String.fromData( out )
        }
        return "MATCH FAILED line:\(line) column:\(col)"
    }
}

var xcode: RefactoratorResponse!

@objc public class Refactorator: NSObject, RefactoratorRequest {

    private var usrToPatch: String!
    private var overrideUSR: String?

    private var indexes = [String:(__darwin_time_t,sourcekitd_response_t)]()

    private var modules = Set<String>()
    private var patches = [Entity]()

    private var backups = [String:NSData]()
    private var patched = [String:NSData]()

    public func refactorFile( filePath: String, byteOffset: Int32, oldValue: String, logDir: String, plugin: RefactoratorResponse ) -> Int32 {
        NSLog( "refactord -- refactorFile: \(filePath) \(byteOffset) \(logDir)")

        sourcekitd_initialize()
        modules.removeAll()
        patches.removeAll()
        overrideUSR = nil
        usrToPatch = nil

        xcode = plugin

        /** find command line arguments for file from build logs */
        let xcodeBuildLogs = LogParser( logDir: logDir )
        guard let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
                line.containsString( " -primary-file \(filePath) " ) ||
                line.containsString( " -primary-file \"\(filePath)\" " ) } ) else {
            xcode.error( "Could not find compiler arguments in \(logDir). Have you built the project?" )
            return -1
        }

        /** prepare compiler arguments for sourcekit */
        func args( argv: [String] ) -> sourcekitd_object_t {
            let objects = argv.map { sourcekitd_request_string_create( $0 ) }
            return sourcekitd_request_array_create( objects, argv.count )
        }

        /** prepare request to find entity at current selection */
        let req = sourcekitd_request_dictionary_create( nil, nil, 0 )
        let compiplerArgs = args( argv )

        sourcekitd_request_dictionary_set_uid( req, requestID, cursorRequestID )
        sourcekitd_request_dictionary_set_string( req, sourceFileID, filePath )
        sourcekitd_request_dictionary_set_int64( req, offsetID, Int64(byteOffset) )
        sourcekitd_request_dictionary_set_value( req, compilerArgsID, compiplerArgs )

        if isTTY {
            sourcekitd_request_description_dump( req )
        }

        let resp = sourcekitd_send_request_sync( req )
        if let error = error( resp ) {
            xcode.error( "Cursor fetch error: \(error)" )
            exit(1)
        }

        if isTTY {
            sourcekitd_response_description_dump_filedesc( resp, STDERR_FILENO )
        }

        let dict = sourcekitd_response_get_value( resp )
        var usr = sourcekitd_variant_dictionary_get_string( dict, usrID )
        if usr == nil {
            xcode.error( "Unable to locate public or internal symbol associated with selection. " )
            return -1
        }

        let overrides = sourcekitd_variant_dictionary_get_value( dict, overridesID )
        sourcekitd_variant_array_apply( overrides ) { (_,dict) in
            self.overrideUSR = String.fromCString( usr )
            usr = sourcekitd_variant_dictionary_get_string( dict, usrID )
            return false
        }

        usrToPatch = String.fromCString( usr )
        xcode.foundUSR( usrToPatch )

        /** index all sources included in selection's module */
        processModuleSources( argv, args: compiplerArgs, oldValue: oldValue )

        /** if entity is in a framework, index each source of that module as well */
        let module = sourcekitd_variant_dictionary_get_string( dict, moduleID )
        if module != nil {
            modules.insert( String.fromCString( module )! )
        }

        for module in modules {
            xcode.log( "<b>Framework '\(module)':</b><br>" )

            if let argv = xcodeBuildLogs.compilerArgumentsMatching( { line in
                line.containsString( " -module-name \(module) " ) && line.containsString( " -primary-file " ) } ) {
                    processModuleSources( argv, args: args( argv ), oldValue: oldValue )
            }
        }

        xcode.indexing( nil )
        return Int32(patches.count)
    }

    private func processModuleSources( argv: [String], args: sourcekitd_object_t, oldValue: String ) {

        for file in argv.filter( { $0.hasSuffix( ".swift" ) } ) {

            let resp: sourcekitd_response_t
            var info = stat()
            stat( file, &info )
            let modified = info.st_mtimespec.tv_sec

            if let (indexTime,lastResp) = indexes[file] where indexTime >= modified {
                resp = lastResp
            }
            else {
                xcode.indexing( file )
                let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

                sourcekitd_request_dictionary_set_uid( req, requestID, indexRequestID )
                sourcekitd_request_dictionary_set_string( req, sourceFileID, file )
                sourcekitd_request_dictionary_set_value( req, compilerArgsID, args )

                if isTTY {
                    sourcekitd_request_description_dump( req )
                }

                resp = sourcekitd_send_request_sync( req )
                if let error = error( resp ) {
                    xcode.log( "Source index error for \(file): \(error)" )
                    sourcekitd_initialize()
                    continue
                }

                if isTTY {
                    sourcekitd_response_description_dump_filedesc( resp, STDERR_FILENO )
                }

                indexes[file] = (modified, resp)
            }

            let dict = sourcekitd_response_get_value( resp )
            if overrideUSR != nil  {
                /** ideally override would give us the module */
                traceDependencies( dict )
            }
            traceEntities( dict, oldValue: oldValue, file: file, contents: NSMutableData( contentsOfFile: file ) )
        }
    }

    private func traceDependencies( resp: sourcekitd_variant_t ) {

        let dependencies = sourcekitd_variant_dictionary_get_value( resp, depedenciesID )

        sourcekitd_variant_array_apply( dependencies ) { (_,dict) in

            if sourcekitd_variant_dictionary_get_uid( dict, kindID ) == clangID &&
                    !sourcekitd_variant_dictionary_get_bool( dict, isSystemID ) {
                let module = sourcekitd_variant_dictionary_get_string( dict, nameID )
                if module != nil {
                    self.modules.insert( String.fromCString( module )! )
                }
            }

            self.traceDependencies( dict )
            return true
        }
    }

    private func traceEntities( resp: sourcekitd_variant_t, oldValue: String, file: String, contents: NSMutableData? ) {

        let entities = sourcekitd_variant_dictionary_get_value( resp, entitiesID )

        sourcekitd_variant_array_apply( entities ) { (_,dict) in

            let usrString = sourcekitd_variant_dictionary_get_string( dict, usrID )
            if usrString != nil {

                let entityUSR = String.fromCString( usrString )

                /** if entity == current selection's entity, log and store for patching later */
                if entityUSR == self.usrToPatch || entityUSR == self.overrideUSR {

                    let entity = Entity( file: file,
                        line: Int32(sourcekitd_variant_dictionary_get_int64( dict, lineID )),
                        col: Int32(sourcekitd_variant_dictionary_get_int64( dict, colID )) )

                    if isTTY {
                        let kind = sourcekitd_variant_dictionary_get_uid( dict, kindID )
                        print( "\(String.fromCString( sourcekitd_uid_get_string_ptr( kind) )!) " +
                            "\(String.fromCString( sourcekitd_variant_dictionary_get_string( dict, nameID) )!) " +
                            "\(entityUSR!) \(entity.line) \(entity.col)" )
                    }

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

extension String  {

    static func fromData( data: NSData ) -> String? {
        return NSString( data: data, encoding: NSUTF8StringEncoding ) as? String
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
