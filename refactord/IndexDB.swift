//
//  IndexDB.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/IndexDB.swift#2 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

class IndexDB {

    var handle: COpaquePointer { return _handle }
    private var _handle: COpaquePointer = nil

    let filenames: IndexStrings
    let directories: IndexStrings
    let resolutions: IndexStrings

    init( dbPath: String ) {
        filenames = IndexStrings( path: dbPath+".strings-file" )
        directories = IndexStrings( path: dbPath+".strings-dir" )
        resolutions = IndexStrings( path: dbPath+".strings-res" )
        guard sqlite3_open_v2( dbPath, &_handle, SQLITE_OPEN_READONLY, nil ) == SQLITE_OK else {
            print( "BAD DB OPEN \(dbPath)" )
            return
        }
    }

    deinit {
        sqlite3_close( handle )
    }

    func usrInFile( fileName: String, filename: String, directory: String, line: Int, col: Int ) -> String? {

        var usr: String? = nil

        if let fileID = filenames[fileName],  fileid = filenames[filename], dirID = directories[directory] {

            var stmt: COpaquePointer = nil
            guard sqlite3_prepare_v2( handle,
                "select r.resolution from file f" +
                    " inner join group_ g on (f.id = g.file)" +
                    " inner join reference r on (g.id = r.group_)" +
                " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
                " and r.lineNumber = ? and r.column = ?" +
                "union " +
                "select s.resolution from file f" +
                    " inner join group_ g on (f.id = g.file)" +
                    " inner join symbol s on (g.id = s.group_)" +
                " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
                " and s.lineNumber = ? and s.column = ?",
                -1, &stmt, nil ) == SQLITE_OK else { return String.fromCString( sqlite3_errmsg( handle ) )! }

            guard sqlite3_bind_int64(stmt, 1, Int64(fileid)) == SQLITE_OK else { return "!BIND1" }
            guard sqlite3_bind_int64(stmt, 2, Int64(fileID)) == SQLITE_OK else { return "!BIND2" }
            guard sqlite3_bind_int64(stmt, 3, Int64(dirID)) == SQLITE_OK else { return "!BIND3" }
            guard sqlite3_bind_int64(stmt, 4, Int64(line)) == SQLITE_OK else { return "!BIND4" }
            guard sqlite3_bind_int64(stmt, 5, Int64(col)) == SQLITE_OK else { return "!BIND5" }

            guard sqlite3_bind_int64(stmt, 6, Int64(fileid)) == SQLITE_OK else { return "!BIND6" }
            guard sqlite3_bind_int64(stmt, 7, Int64(fileID)) == SQLITE_OK else { return "!BIND7" }
            guard sqlite3_bind_int64(stmt, 8, Int64(dirID)) == SQLITE_OK else { return "!BIND8" }
            guard sqlite3_bind_int64(stmt, 9, Int64(line)) == SQLITE_OK else { return "!BIND9" }
            guard sqlite3_bind_int64(stmt, 10, Int64(col)) == SQLITE_OK else { return "!BIND10" }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let usrID = Int(sqlite3_column_int64(stmt,0))
                if let utmp = resolutions[usrID] where usr == nil ||
                        utmp.characters.count < usr!.characters.count {
                    usr = resolutions[usrID]
                }
                print( "Found USR: \(usrID) -- \(usr)" )
            }

            sqlite3_finalize( stmt )
        }

        return usr
    }

    func entitiesForUSR( usr: String, oldValue: String ) -> [Entity] {
        var entities = [Entity]()

        if let resID = resolutions[usr] {
            var stmt: COpaquePointer = nil
            guard sqlite3_prepare_v2( handle,
                "select f.filename, f.directory, r.lineNumber, r.column" +
                " from reference r " +
                " inner join group_ g on (g.id = r.group_)" +
                " inner join file f on (f.id = g.file)" +
                "where r.resolution = ? " +
                "union " +
                "select f.filename, f.directory, s.lineNumber, s.column" +
                " from symbol s " +
                " inner join group_ g on (g.id = s.group_)" +
                " inner join file f on (f.id = g.file)" +
                "where s.resolution = ? ",
                -1, &stmt, nil ) == SQLITE_OK else { print( String.fromCString( sqlite3_errmsg( handle ) )! ); return entities }

            guard sqlite3_bind_int64(stmt, 1, Int64(resID)) == SQLITE_OK else { return entities }
            guard sqlite3_bind_int64(stmt, 2, Int64(resID)) == SQLITE_OK else { return entities }

            while sqlite3_step(stmt) == SQLITE_ROW {

                let fileID = Int(sqlite3_column_int64(stmt,0))
                let dirID = Int(sqlite3_column_int64(stmt,1))
                let line = Int32(sqlite3_column_int64(stmt,2))
                let col = Int32(sqlite3_column_int64(stmt,3))

                if line != 0, let file = filenames[fileID], dir = directories[dirID] {
                    let file = dir+"/"+file, entity = Entity( file: file, line: line, col: col )
                    entities.append( entity )
                }

            }

            sqlite3_finalize( stmt )
        }

        return entities
    }



}