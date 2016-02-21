//
//  SourceKit.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/SourceKit.swift#14 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

var isTTY = isatty( STDERR_FILENO ) != 0

protocol Visualiser {

    func enter()
    func present( dict: sourcekitd_variant_t, indent: String )
    func exit()

}

extension sourcekitd_variant_t {

    func getInt( key: sourcekitd_uid_t ) -> Int {
        return Int(sourcekitd_variant_dictionary_get_int64( self, key ))
    }

    func getString( key: sourcekitd_uid_t ) -> String? {
        let cstr = sourcekitd_variant_dictionary_get_string( self, key )
        if cstr != nil {
            return String.fromCString( cstr )
        }
        return nil
    }

    func getUUIDString( key: sourcekitd_uid_t ) -> String {
        let uuid = sourcekitd_variant_dictionary_get_uid( self, key )
        return String.fromCString( sourcekitd_uid_get_string_ptr( uuid ) ) ?? "NOUUID"
    }

}

class SourceKit {

    /** request types */
    private lazy var requestID = sourcekitd_uid_get_from_cstr("key.request")
    private lazy var cursorRequestID = sourcekitd_uid_get_from_cstr("source.request.cursorinfo")
    private lazy var indexRequestID = sourcekitd_uid_get_from_cstr("source.request.indexsource")
    private lazy var editorOpenID = sourcekitd_uid_get_from_cstr("source.request.editor.open")

    private lazy var enableMapID = sourcekitd_uid_get_from_cstr("key.enablesyntaxmap")
    private lazy var enableSubID = sourcekitd_uid_get_from_cstr("key.enablesubstructure")
    private lazy var syntaxOnlyID = sourcekitd_uid_get_from_cstr("key.syntactic_only")

    /** request arguments */
    lazy var offsetID = sourcekitd_uid_get_from_cstr("key.offset")
    lazy var sourceFileID = sourcekitd_uid_get_from_cstr("key.sourcefile")
    lazy var compilerArgsID = sourcekitd_uid_get_from_cstr("key.compilerargs")

    /** sub entity lists */
    lazy var depedenciesID = sourcekitd_uid_get_from_cstr("key.dependencies")
    lazy var overridesID = sourcekitd_uid_get_from_cstr("key.overrides")
    lazy var entitiesID = sourcekitd_uid_get_from_cstr("key.entities")
    lazy var syntaxID = sourcekitd_uid_get_from_cstr("key.syntaxmap")

    /** entity attributes */
    lazy var receiverID = sourcekitd_uid_get_from_cstr("key.receiver_usr")
    lazy var isDynamicID = sourcekitd_uid_get_from_cstr("key.is_dynamic")
    lazy var isSystemID = sourcekitd_uid_get_from_cstr("key.is_system")
    lazy var moduleID = sourcekitd_uid_get_from_cstr("key.modulename")
    lazy var lengthID = sourcekitd_uid_get_from_cstr("key.length")
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
        return sourcekitd_request_array_create( objects, objects.count )
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

    func cursorInfo( filePath: String, byteOffset: Int32, compilerArgs: sourcekitd_object_t ) -> sourcekitd_response_t {
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

    func syntaxMap( filePath: String, compilerArgs: sourcekitd_object_t ) -> sourcekitd_response_t {
        let req = sourcekitd_request_dictionary_create( nil, nil, 0 )

        sourcekitd_request_dictionary_set_uid( req, requestID, editorOpenID )
        sourcekitd_request_dictionary_set_string( req, nameID, filePath )
        sourcekitd_request_dictionary_set_string( req, sourceFileID, filePath )
        sourcekitd_request_dictionary_set_value( req, compilerArgsID, compilerArgs )
        sourcekitd_request_dictionary_set_int64( req, enableMapID, 1 )
        sourcekitd_request_dictionary_set_int64( req, enableSubID, 0 )
        sourcekitd_request_dictionary_set_int64( req, syntaxOnlyID, 1 )

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

    func compilerArgs( buildCommand: String ) -> [String] {
        let spaceToTheLeftOfAnOddNumberOfQoutes = " (?=[^\"]*\"[^\"]*(?:(?:\"[^\"]*){2})* -o )"
        let line = buildCommand
            .stringByTrimmingCharactersInSet( NSCharacterSet.whitespaceAndNewlineCharacterSet() )
            .stringByReplacingOccurrencesOfString( "\\\"", withString: "---" )
            .stringByReplacingOccurrencesOfString( spaceToTheLeftOfAnOddNumberOfQoutes,
                withString: "___", options: .RegularExpressionSearch, range: nil )
            .stringByReplacingOccurrencesOfString( "\"", withString: "" )

        let argv = line.componentsSeparatedByString( " " )
            .map { $0.stringByReplacingOccurrencesOfString( "___", withString: " " )
                .stringByReplacingOccurrencesOfString( "---", withString: "\"" ) }

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
            else {
                out.append( arg )
            }
            i += 1
        }

        return out
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

}
