//
//  Refactorator.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/Refactorator.swift#19 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

let requestID = sourcekitd_uid_get_from_cstr("key.request")
let cursorRequestID = sourcekitd_uid_get_from_cstr("source.request.cursorinfo")
let indexRequestID = sourcekitd_uid_get_from_cstr("source.request.indexsource")
let offsetID = sourcekitd_uid_get_from_cstr("key.offset")
let sourceFileID = sourcekitd_uid_get_from_cstr("key.sourcefile")
let compilerArgsID = sourcekitd_uid_get_from_cstr("key.compilerargs")
let overridesID = sourcekitd_uid_get_from_cstr("key.overrides")
let entitiesID = sourcekitd_uid_get_from_cstr("key.entities")
let relatedID = sourcekitd_uid_get_from_cstr("key.entities")
let moduleID = sourcekitd_uid_get_from_cstr("key.modulename")
let kindID = sourcekitd_uid_get_from_cstr("key.kind")
let nameID = sourcekitd_uid_get_from_cstr("key.name")
let usrID = sourcekitd_uid_get_from_cstr("key.usr")
let lineID = sourcekitd_uid_get_from_cstr("key.line")
let colID = sourcekitd_uid_get_from_cstr("key.column")

struct Entity {
    let file: String
    let line: Int32
    let col: Int32

    func regex( text: String ) -> ByteRegex {
        var pattern = "^"
        var line = self.line
        while line > 100 {
            pattern += "(?:[^\n]*\n){100}"
            line -= 100
        }
        pattern += "(?:[^\n]*\n){\(line-1)}(.{\(col-1)}[^\n]*?)(\(text))([^\n]*)"
        return ByteRegex( pattern: pattern )
    }

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

    var usrToPatch: String!
    var patches = [Entity]()
    var patched = [String:NSMutableData]()

    public func refactorFile( filePath: String, byteOffset: Int32, oldValue: String, logDir: String, plugin: RefactoratorResponse ) -> Int32 {
        NSLog( "refactord -- refactorFile: \(filePath) \(byteOffset) \(logDir)")
        xcode = plugin

        guard let argv = LogParser( logDir: logDir ).argumentsMatching( { line in
                line.containsString( " -primary-file \(filePath) " ) ||
                line.containsString( " -primary-file \"\(filePath)\" " ) } ) else {
            xcode.error( "Could not find compiler arguments in \(logDir). Have you built the project?" )
            return -1
        }

        sourcekitd_initialize()
        patches = [Entity]()

        let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

        sourcekitd_request_dictionary_set_uid( req, requestID, cursorRequestID )
        sourcekitd_request_dictionary_set_string( req, sourceFileID, filePath )
        sourcekitd_request_dictionary_set_int64( req, offsetID, Int64(byteOffset) )

        let objects = argv.map { sourcekitd_request_string_create( $0 ) }
        let args = sourcekitd_request_array_create( objects, argv.count )
        sourcekitd_request_dictionary_set_value( req, compilerArgsID, args )

        if isatty( STDOUT_FILENO ) != 0 {
            sourcekitd_request_description_dump( req )
        }

        let resp = sourcekitd_send_request_sync( req )
        if sourcekitd_response_is_error( resp ) {
            xcode.error( "Cursor fetch error: \(String.fromCString( sourcekitd_response_error_get_description( resp ) ))" )
            exit(1)
        }

        if isatty( STDOUT_FILENO ) != 0 {
            sourcekitd_response_description_dump_filedesc( resp, STDOUT_FILENO )
        }

        let dict = sourcekitd_response_get_value( resp )
        let usr = sourcekitd_variant_dictionary_get_string( dict, usrID )
        if usr == nil {
            xcode.error( "Unable to locate public or internal symbol associated with selection. " +
                "cmd-click to go to the definition in case it is in a different target." )
            return -1
        }

//        let overrides = sourcekitd_variant_dictionary_get_value( dict, overridesID )
//        sourcekitd_variant_array_apply( overrides ) { (_,dict) in
//            usr = sourcekitd_variant_dictionary_get_string( dict, usrID )
//            return false
//        }

        usrToPatch = String.fromCString( usr )
        plugin.foundUSR( usrToPatch )

        processModuleSources( argv, args: args, oldValue: oldValue )

        let module = sourcekitd_variant_dictionary_get_string( dict, moduleID )
        if module != nil {
            let module = String.fromCString( module )!
            xcode.log( "<br><b>Framework '\(module)':</b><br>" )

            guard let argv = LogParser( logDir: logDir ).argumentsMatching( { line in
                line.containsString( " -module-name \(module) " ) || line.containsString( " -primary-file " ) } ) else {
                        xcode.error( "Could not find module compiler arguments in \(logDir). Have you built the project?" )
                        return -1
            }

            let objects = argv.map { sourcekitd_request_string_create( $0 ) }
            let args = sourcekitd_request_array_create( objects, argv.count )
            processModuleSources( argv, args: args, oldValue: oldValue )
        }

        return Int32(patches.count)
    }

    private func processModuleSources( argv: [String], args: sourcekitd_object_t, oldValue: String ) {

        for file in argv.filter( { $0.hasSuffix( ".swift" ) } ) {
            let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

            sourcekitd_request_dictionary_set_uid( req, requestID, indexRequestID )
            sourcekitd_request_dictionary_set_string( req, sourceFileID, file )
            sourcekitd_request_dictionary_set_value( req, compilerArgsID, args )

            let resp = sourcekitd_send_request_sync( req )
            if sourcekitd_response_is_error( resp ) {
                xcode.error( "Source index error: \(String.fromCString( sourcekitd_response_error_get_description( resp ) ))" )
                exit(1)
            }

            if isatty( STDOUT_FILENO ) != 0 {
                sourcekitd_response_description_dump_filedesc( resp, STDOUT_FILENO )
            }

            traceEntities( sourcekitd_response_get_value( resp ), oldValue: oldValue,
                file: file, contents: NSMutableData( contentsOfFile: file ) )
        }
    }

    private func traceEntities( resp: sourcekitd_variant_t, oldValue: String, file: String, contents: NSMutableData? ) {
        let entities = sourcekitd_variant_dictionary_get_value( resp, entitiesID )

        sourcekitd_variant_array_apply( entities ) { (_,dict) in

            let entityUSR = String.fromCString( sourcekitd_variant_dictionary_get_string( dict, usrID ) )
//            let related = sourcekitd_variant_dictionary_get_value( dict, relatedID )
//            sourcekitd_variant_array_apply( related ) { (_,dict) in
//                thisUSR = String.fromCString( sourcekitd_variant_dictionary_get_string( dict, usrID ) )?
//                    .stringByReplacingOccurrencesOfString( "FS0_F", withString: "F" )
//                print( "\n\n\(thisUSR)\n\n\n" )
//                return false
//            }

            if entityUSR == self.usrToPatch {
                let entity = Entity( file: file,
                    line: Int32(sourcekitd_variant_dictionary_get_int64( dict, lineID )),
                    col: Int32(sourcekitd_variant_dictionary_get_int64( dict, colID )) )

                if isatty( STDOUT_FILENO ) != 0 {
                    let kind = sourcekitd_uid_get_string_ptr( sourcekitd_variant_dictionary_get_uid( dict, kindID ) )
                    print( "\(String.fromCString( kind)) " +
                        "\(String.fromCString( sourcekitd_variant_dictionary_get_string( dict, nameID) )) " +
                        "\(entityUSR) \(entity.line) \(entity.col)" )
                }

                if let contents = contents, patch = entity.patchText( contents, value: oldValue ) {
                    xcode.willPatchFile( file, line:entity.line, col: entity.col, text: patch )
                    self.patches.append( entity )
                }
           }

            self.traceEntities( dict, oldValue: oldValue, file: file, contents: contents )
            return true
        }
    }

    public func refactorFrom( oldValue: String, to newValue: String ) -> Int32 {
        NSLog( "refactorFrom( \(oldValue) to: \(newValue) )")
        patched = [String:NSMutableData]()

        typealias Closure = () -> ()
        var blocks = [Closure]()

        for entity in patches.reverse() {
            if patched[entity.file] == nil {
                patched[entity.file] = NSMutableData( contentsOfFile: entity.file )!
            }
            if let contents = patched[entity.file], matches = entity.regex( oldValue ).match( contents ) {

                let out = NSMutableData()
                out.appendData( contents.subdataWithRange( NSMakeRange( 0, Int(matches[2].rm_so) ) ) )
                out.appendString( newValue )
                out.appendData( contents.subdataWithRange( NSMakeRange( Int(matches[2].rm_eo),
                                                        contents.length-Int(matches[2].rm_eo) ) ) )

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
        return Int32(patched.count)
    }

}

extension String  {

    static func fromData( data: NSData ) -> String? {
        return NSString( data:data, encoding:NSUTF8StringEncoding ) as? String
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
