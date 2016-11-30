//
//  Refactorator.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/Refactorator.swift#61 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

var xcode: RefactoratorResponse!
var SK: SourceKit!

/** instance published as Distributed Objects service */
@objc public class Refactorator: NSObject {

    var usrToPatch: String!
    var overrideUSR: String?

    /** indexes cached for the life of the daemon */
    private var indexes = [String:(__darwin_time_t,sourcekitd_response_t)]()

    var modules = Set<String>()
    var patches = [Entity]()

    private var backups = [String:NSData]()
    private var patched = [String:NSData]()

    func demangle( usr: String ) -> String {
        return usr.hasPrefix( "s:" ) ? _stdlib_demangleName( (usr.hasPrefix("_T") ? "" : "_T") +
            usr.substring(from: usr.index( usr.startIndex, offsetBy: 2 ) ) ) : usr
    }

    public func refactorFile( _ filePath: String, byteOffset: Int32, oldValue: String,
                logDir: String, graph: String?, plugin: RefactoratorResponse ) -> Int32 {
        NSLog( "refactord -- refactorFile: \(filePath) \(byteOffset) \(logDir)")

        xcode = plugin

        if let (xcodeBuildLogs, argv, compilerArgs) = parseForUSR( filePath: filePath, byteOffset: byteOffset, logDir: logDir ) {
            return searchUSR( xcodeBuildLogs, argv: argv, compilerArgs: compilerArgs, oldValue: oldValue, graph: graph )
        }

        return -1
    }

    func parseForUSR( filePath: String, byteOffset: Int32, logDir: String ) -> (LogParser, [String], sourcekitd_object_t)? {

        SK = SourceKit()

        modules.removeAll()
        patches.removeAll()
        overrideUSR = nil
        usrToPatch = nil

        /** find command line arguments for file from build logs */
        let xcodeBuildLogs = LogParser( logDir: logDir )
        guard let argv = xcodeBuildLogs.compilerArgumentsMatching( matcher: { line in
                line.contains( " -primary-file \(filePath) " ) ||
                line.contains( " -primary-file \"\(filePath)\" " ) } ) else {
            xcode.error( "Could not find compiler arguments in \(logDir). Have you built all files in the project?" )
            return nil
        }

        let compilerArgs = SK.array( argv: argv )

        /** fund "USR" for current selection */
        let resp = SK.cursorInfo( filePath: filePath, byteOffset: byteOffset, compilerArgs: compilerArgs )
        if let error = SK.error( resp: resp ) {
            xcode.error( "Cursor fetch error: \(error)" )
            exit(1)
        }

        let dict = sourcekitd_response_get_value( resp )
        guard var usr = dict.getString( key: SK.usrID ) else {
            xcode.error( "Unable to locate public or internal symbol associated with selection. " +
                "Has the project completed Indexing?" )
            return nil
        }

        /** if function is override refactor function and overridden function */
        let overrides = sourcekitd_variant_dictionary_get_value( dict, SK.overridesID )
        if sourcekitd_variant_get_type( overrides ) == SOURCEKITD_VARIANT_TYPE_ARRAY {
            sourcekitd_variant_array_apply( overrides ) { (_,dict) in
                self.overrideUSR = usr
                usr = dict.getString( key: SK.usrID )!
                return false
            }
        }

        usrToPatch = usr
        xcode.foundUSR( usrToPatch, text: demangle( usr: usrToPatch ) )

        /** if entity is in a framework, index each source of that module as well */
        if let module = dict.getString( key: SK.moduleID ) {
            modules.insert( module )
        }

        return (xcodeBuildLogs, argv, compilerArgs)
    }

    func searchUSR( _ xcodeBuildLogs: LogParser, argv: [String], compilerArgs: sourcekitd_object_t, oldValue: String, graph: String? ) -> Int32 {

        let visualiser: Grapher? = graph != nil ? Grapher() : nil

        /** index all sources included in selection's module */
        processModuleSources( argv, args: compilerArgs, oldValue: oldValue, visualiser: visualiser )

        for module in modules {
            xcode.log( "<b>Framework '\(module)':</b><br>" )

            if let argv = xcodeBuildLogs.compilerArgumentsMatching( matcher: { line in
                line.contains( " -module-name \(module) " ) && line.contains( " -primary-file " ) } ) {
                    processModuleSources( argv, args: SK.array( argv: argv ), oldValue: oldValue, visualiser: nil )
            }
        }

        _ = visualiser?.render( outPath: graph! )

        xcode.indexing( nil )
        return Int32(patches.count)
    }

    private func processModuleSources( _ argv: [String], args: sourcekitd_object_t, oldValue: String, visualiser: Visualiser? ) {

        for file in argv.filter( { $0.hasSuffix( ".swift" ) } ) {

            let resp: sourcekitd_response_t
            var info = stat()
            if stat( file, &info ) != 0 {
                xcode.log( "Could not stat file: \(file)" )
                continue
            }

            /** use cache if file has not been modified */
            let lastModified = info.st_mtimespec.tv_sec
            if let (lastIndexed,lastResp) = indexes[file], lastIndexed >= lastModified {
                resp = lastResp
            }
            else {
                xcode.indexing( file )

                resp = SK.indexFile( filePath: file, compilerArgs: args )
                if let error = SK.error( resp: resp ) {
                    xcode.log( "Source index error for \(file): \(error)" )
                    sleep( 2 )
                    SK = SourceKit()
                    continue
                }

                indexes[file] = (lastModified, resp)
            }

            let dict = sourcekitd_response_get_value( resp )

            if overrideUSR != nil  {
                /** ideally override would give us its module */
                SK.recurseOver( childID: SK.depedenciesID, resp: dict, block: { dict in

                    if sourcekitd_variant_dictionary_get_uid( dict, SK.kindID ) == SK.clangID &&
                            !sourcekitd_variant_dictionary_get_bool( dict, SK.isSystemID ) {
                        if let module = dict.getString( key: SK.nameID ) {
                            self.modules.insert( module )
                        }
                    }
                } )
            }

            if let contents = NSData( contentsOfFile: file ) {
                SK.recurseOver( childID: SK.entitiesID, resp: dict, visualiser: visualiser, block: { dict in

                    if let entityUSR = dict.getString( key: SK.usrID ) {

                        /** if entity == current selection's entity, log and store for patching later */
                        if entityUSR == self.usrToPatch || entityUSR == self.overrideUSR {
                            let kind = dict.getUUIDString( key: SK.kindID )

                            let entity = Entity( file: file,
                                line: dict.getInt( key: SK.lineID ),
                                col: dict.getInt( key: SK.colID ),
                                //kind: kind,
                                decl: kind.contains( ".decl" ) )

                            if let patch = entity.patchText( contents: contents, value: oldValue ) {
                                xcode.willPatchFile( file, line:Int32(entity.line), col: Int32(entity.col), text: patch )
                                self.patches.append( entity )
                            }
                        }
                    }
                } )
            }
        }
    }

    public func refactor( from oldValue: String, to newValue: String ) -> Int32 {
        NSLog( "refactorFrom( \(oldValue) to: \(newValue) )")
        backups.removeAll()
        patched.removeAll()

        typealias Closure = () -> ()
        var blocks = [Closure]()

        /** patches performed in reverse in case offsets changed */
        for entity in patches.reversed() {
            if patched[entity.file] == nil {
                backups[entity.file] = NSData( contentsOfFile: entity.file )
                patched[entity.file] = backups[entity.file]
            }

            if let contents = patched[entity.file], let matches = entity.regex( text: oldValue ).match( input: contents ) {

                /** apply patch, substituting newValue for entity reference */
                let out = NSMutableData()
                out.append( contents.subdata( with: NSMakeRange( 0, Int(matches[2].rm_so) ) ) )
                out.appendString( str: newValue )
                out.append( contents.subdata( with: NSMakeRange( Int(matches[2].rm_eo),
                                                        contents.length-Int(matches[2].rm_eo) ) ) )

                /** log and update in-memory version of source file */
                if let patch = entity.patchText( contents: out, value: newValue ) {
                    blocks.append( { xcode.willPatchFile( entity.file,
                        line: Int32(entity.line), col: Int32(entity.col), text: patch ) } )
                    patched[entity.file] = out
                }
            }
        }

        for block in blocks.reversed() {
            block()
        }

        return Int32(patches.count)
    }

    public func confirmRefactor() -> Int32 {
        for (file,data) in patched {
            if !data.write( toFile: file, atomically: true ) {
                xcode.error( "Could not save to file: \(file)" )
            }
        }
        let modified = patched.count
        patched.removeAll()
        return Int32(modified)
    }

    public func revertRefactor() -> Int32 {
        for (file,data) in backups {
            if !data.write( toFile: file, atomically: true ) {
                xcode.error( "Could not revert file: \(file)" )
            }
        }
        let modified = backups.count
        backups.removeAll()
        return Int32(modified)
    }

}

extension NSMutableData {

    @discardableResult
    func appendString( str: String ) -> NSMutableData {
        str.withCString { bytes in
            append( bytes, length: Int(strlen(bytes)) )
        }
        return self
    }

}
