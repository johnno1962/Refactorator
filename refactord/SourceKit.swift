//
//  SourceKit.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/SourceKit.swift#8 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

let isTTY = isatty( STDERR_FILENO ) != 0

class SourceKit {

    /** request types */
    lazy var requestID = sourcekitd_uid_get_from_cstr("key.request")
    lazy var cursorRequestID = sourcekitd_uid_get_from_cstr("source.request.cursorinfo")
    lazy var indexRequestID = sourcekitd_uid_get_from_cstr("source.request.indexsource")

    /** request arguments */
    lazy var offsetID = sourcekitd_uid_get_from_cstr("key.offset")
    lazy var sourceFileID = sourcekitd_uid_get_from_cstr("key.sourcefile")
    lazy var compilerArgsID = sourcekitd_uid_get_from_cstr("key.compilerargs")

    /** sub entity lists */
    lazy var depedenciesID = sourcekitd_uid_get_from_cstr("key.dependencies")
    lazy var overridesID = sourcekitd_uid_get_from_cstr("key.overrides")
    lazy var entitiesID = sourcekitd_uid_get_from_cstr("key.entities")

    /** entity attributes */
    lazy var isSystemID = sourcekitd_uid_get_from_cstr("key.is_system")
    lazy var moduleID = sourcekitd_uid_get_from_cstr("key.modulename")
    lazy var kindID = sourcekitd_uid_get_from_cstr("key.kind")
    lazy var nameID = sourcekitd_uid_get_from_cstr("key.name")
    lazy var lineID = sourcekitd_uid_get_from_cstr("key.line")
    lazy var colID = sourcekitd_uid_get_from_cstr("key.column")
    lazy var usrID = sourcekitd_uid_get_from_cstr("key.usr")

    /** kinds */
    lazy var clangID = sourcekitd_uid_get_from_cstr("source.lang.swift.import.module.clang")

    /** declarations */
    lazy var structID = sourcekitd_uid_get_from_cstr("source.lang.swift.decl.struct")
    lazy var classID = sourcekitd_uid_get_from_cstr("source.lang.swift.decl.class")
    lazy var enumID = sourcekitd_uid_get_from_cstr("source.lang.swift.decl.enum")

    /** references */
    lazy var classVarID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.function.var.class")
    lazy var classMethodID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.function.method.class")
    lazy var initID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.function.constructor")
    lazy var varID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.var.instance")
    lazy var methodID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.function.method.instance")
    lazy var elementID = sourcekitd_uid_get_from_cstr("source.lang.swift.ref.enumelement")

    init() {
        sourcekitd_initialize()
    }

    func array( argv: [String] ) -> sourcekitd_object_t {
        let objects = argv.map { sourcekitd_request_string_create( $0 ) }
        return sourcekitd_request_array_create( objects, argv.count )
    }

    func error( resp: sourcekitd_response_t ) -> String? {
        if sourcekitd_response_is_error( resp ) {
            return String.fromCString( sourcekitd_response_error_get_description( resp ) )
        }
        return nil
    }

    func sendRequest( req: sourcekitd_object_t ) -> sourcekitd_response_t {

        if isTTY {
            sourcekitd_request_description_dump( req )
        }

        let resp = sourcekitd_send_request_sync( req )

        if isTTY && !sourcekitd_response_is_error( resp ) {
            sourcekitd_response_description_dump_filedesc( resp, STDERR_FILENO )
        }

        return resp
    }

    func cursorInfo( filePath: String, byteOffset: Int64, compilerArgs: sourcekitd_object_t ) -> sourcekitd_response_t {
        let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

        sourcekitd_request_dictionary_set_uid( req, requestID, cursorRequestID )
        sourcekitd_request_dictionary_set_string( req, sourceFileID, filePath )
        sourcekitd_request_dictionary_set_int64( req, offsetID, Int64(byteOffset) )
        sourcekitd_request_dictionary_set_value( req, compilerArgsID, compilerArgs )

        return sendRequest( req )
    }

    func indexFile( filePath: String, compilerArgs: sourcekitd_object_t ) -> sourcekitd_response_t {
        let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

        sourcekitd_request_dictionary_set_uid( req, requestID, indexRequestID )
        sourcekitd_request_dictionary_set_string( req, sourceFileID, filePath )
        sourcekitd_request_dictionary_set_value( req, compilerArgsID, compilerArgs )

        return sendRequest( req )
    }

    func recurseOver( childID: sourcekitd_uid_t, resp: sourcekitd_variant_t,
            indent: String = "", visualiser: Visualiser? = nil,
            block: ( dict: sourcekitd_variant_t ) -> ()) {

        let children = sourcekitd_variant_dictionary_get_value( resp, childID )
        if sourcekitd_variant_get_type( children ) == SOURCEKITD_VARIANT_TYPE_ARRAY {

            visualiser?.enter()
            sourcekitd_variant_array_apply( children ) { (_,dict) in

                block( dict: dict )
                visualiser?.present( dict, indent: indent )

                self.recurseOver( childID, resp: dict, indent: indent+"  ", visualiser: visualiser, block: block )
                return true
            }
            visualiser?.exit()
        }
    }

}

func disectUSR( usr: NSString ) -> [String]? {
    guard usr.hasPrefix( "s:" ) else { return nil }

    let digits = NSCharacterSet.decimalDigitCharacterSet()
    let scanner = NSScanner( string: usr as String )
    var out = [String]()
    var wasZero = false

    while !scanner.atEnd {

        var name: NSString?
        scanner.scanUpToCharactersFromSet( digits, intoString: &name )
        if name != nil, let name = name as? String {
            if wasZero {
                out[out.count-1] += "0" + name
                wasZero = false
            }
            else {
                out.append( name )
            }
        }

        var len = 0
        scanner.scanInteger( &len )
        wasZero = len == 0
        if wasZero {
            continue
        }

        if len > usr.length-scanner.scanLocation {
            len = usr.length-scanner.scanLocation
        }

        let range = NSMakeRange( scanner.scanLocation, len )
        out.append( usr.substringWithRange( range ) )
        scanner.scanLocation += len
    }

    return out
}
