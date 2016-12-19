//
//  IndexDB.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/IndexDB.swift#67 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

class IndexDB {

    private var handle: OpaquePointer? = nil

    var error: String {
        return String( cString: sqlite3_errmsg( handle ) )
    }

    static var resolutions: IndexStrings!
    static var projectDirs = [String:Bool]()

    static var kinds = [Int:String]()
    static var kindSuffixies = [Int:String]()

    let filenames: IndexStrings
    let directories: IndexStrings

    var projectDirIDs = [Int:Bool]()
    var podDirIDs = [Int:Bool]()

    static func projectIncludes(file: String) -> Bool {
        return IndexDB.projectDirs[file.url.deletingLastPathComponent().path] != nil
    }

    let roleIsDecl = "role in (1,2)"
    let relatedsDB: String
    var relateds: [Int:[Int]]?

    init?( dbPath: String ) {
        filenames = IndexStrings.load( path: dbPath+".strings-file" )
        directories = IndexStrings.load( path: dbPath+".strings-dir" )
        IndexDB.resolutions = IndexStrings.load( path: dbPath+".strings-res" )
        IndexDB.projectDirs.removeAll()
        for (dir,dirID) in directories.backward {
            IndexDB.projectDirs[dir] = true
            if !(dir.contains("/Developer/Platforms/") ||
                dir.contains("/Developer/Toolchains/") ||
                dir.contains("/DerivedData/")) {
                projectDirIDs[dirID] = true
                if dir.contains("/Pods/") {
                    podDirIDs[dirID] = true
                }
            }
        }

        relatedsDB = dbPath+"-relateds.txt"
        if let relatedData = try? String(contentsOfFile: relatedsDB) {
            relateds = [Int:[Int]]()
            for pairLine in relatedData.components(separatedBy: "\n") {
                let pair = pairLine.components(separatedBy: "\t")
                if let from = IndexDB.resolutions[pair[0]],
                    let to = IndexDB.resolutions[pair[1]] {
                    for (from, to) in [(from, to), (to, from)] {
                        if relateds![from] == nil {
                            relateds![from] = [Int]()
                        }
                        relateds![from]!.append( to )
                    }
                }
            }
        }

        guard sqlite3_open_v2( dbPath, &handle, SQLITE_OPEN_READONLY, nil ) == SQLITE_OK else {
            xcode.error( "Unable to open Index DB at \(dbPath): \(error)" )
            return nil
        }

        IndexDB.kinds.removeAll()
        IndexDB.kindSuffixies.removeAll()
        guard select( sql: "select id, identifier from kind", ids: [], row: {
            (stmt) in
            let id = Int(sqlite3_column_int64(stmt, 0))
            sqlite3_column_text(stmt, 1)!.withMemoryRebound(to: CChar.self, capacity: 1 ) {
                (kind) in
                IndexDB.kinds[id] = String( cString: kind )
                IndexDB.kindSuffixies[id] = IndexDB.kinds[id]!.url.pathExtension
            }
        } ) else {
            xcode.error( "Could not select kinds" )
            return nil
        }
    }

    deinit {
        if handle != nil {
            sqlite3_close( handle )
        }
    }

    func select( sql: String, ids: [Int], row: (_ stmt: OpaquePointer) -> () ) -> Bool {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2( handle, sql, -1, &stmt, nil ) == SQLITE_OK else { return false }
        defer {
            sqlite3_finalize(stmt)
        }

        for p in 0..<ids.count {
            guard sqlite3_bind_int64(stmt, Int32(p+1), Int64(ids[p])) == SQLITE_OK else { return false }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            row( stmt! )
        }

        return true
    }

    func files(inDirectory dir: String) -> [String] {
        guard let dirID = directories[dir] else { return [] }
        var files = [String]()

        _ = select(sql: "select distinct filename from file where directory = ?", ids: [dirID] ) {
            (stmt) in
            files.append( filenames[Int(sqlite3_column_int64(stmt, 0))] ?? "??" )
        }

        return files
    }

    func lookup( filePath: String ) -> (Int, Int, Int)? {
        let url = filePath.url
        let fileName = url.lastPathComponent
        let filename = fileName.lowercased()
        let directory = url.deletingLastPathComponent().path
        guard let fileid = filenames[filename], let fileID = filenames[fileName],  let dirID = directories[directory] else {
            print("Could not lookup \(filename) \(filenames[filename]) - \(fileName) \(filenames[fileName]) - \(directory) \(directories[directory])")
            return nil
        }
        return (fileid, fileID, dirID)
    }

    func usrInFile( filePath: String, line: Int, col: Int ) -> String? {
        guard let (fileid, fileID, dirID) = lookup( filePath: filePath ) else { return nil }
        var usr: String?

        let referenceSQL = "select r.resolution from file f" +
            " inner join group_ g on (f.id = g.file)" +
            " inner join reference r on (g.id = r.group_)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            " and r.lineNumber = ? and r.column = ?"
        let symbolSQL = "select s.resolution from file f" +
            " inner join group_ g on (f.id = g.file)" +
            " inner join symbol s on (g.id = s.group_)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            " and s.lineNumber = ? and s.column = ?"

        guard select( sql: referenceSQL + " union " + symbolSQL,
                ids: [fileid, fileID, dirID, line, col, fileid, fileID, dirID, line, col], row: {
            (stmt) in
            let usrID = Int(sqlite3_column_int64(stmt, 0))
            if let utmp = IndexDB.resolutions[usrID], usr == nil ||
                    utmp.utf16.count < usr!.utf16.count {
                usr = utmp
            }
            print( "Refactorator: Found USR #\(usrID) -- \(usr)\n\(demangle( usr )) : usr)" )
        } ) else {
            xcode.error( "USR prepare error: \(error)" )
            return nil
        }

        return usr
    }

    func entitiesFor( filePath: String ) -> [Entity]? {
        guard let (fileid, fileID, dirID) = lookup( filePath: filePath ) else { return nil }

        let referenceSQL = "select __ENTITYCOLS__, 0" +
            " from reference t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?"
        let symbolSQL = "select __ENTITYCOLS__, 1" +
            " from symbol t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?"

        var entities: [Entity]?
        execute(sql: "\(referenceSQL) union \(symbolSQL)",
        with: [fileid, fileID, dirID, fileid, fileID, dirID] ) {
            entities = $0
        }

        return entities
    }

    func usrIDsFor( filePath: String, line: Int, col: Int ) -> [Int]? {
        guard let (fileid, fileID, dirID) = lookup( filePath: filePath ) else { return [] }

        let referenceSQL = "select r.resolution from file f" +
            " inner join group_ g on (f.id = g.file)" +
            " inner join reference r on (g.id = r.group_)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            " and r.lineNumber = ? and r.column = ? and r.resolution != 0"
        let symbolSQL = "select s.resolution from file f" +
            " inner join group_ g on (f.id = g.file)" +
            " inner join symbol s on (g.id = s.group_)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            " and s.lineNumber = ? and s.column = ? and s.resolution != 0"

        var usrIDs = Set<Int>()
        _ = select(sql: "\(referenceSQL) union \(symbolSQL)", ids: [fileid, fileID, dirID, line, col, fileid, fileID, dirID, line, col] ) {
            (stmt) in
            usrIDs.insert(Int(sqlite3_column_int64(stmt, 0)))
        }

        var newIDs = usrIDs
        while relateds != nil {
            var nextIDs = Set<Int>()
            for id in newIDs {
                if let to = relateds![id] {
                    nextIDs.formUnion(to)
                }
            }
            let usrCount = usrIDs.count
            usrIDs.formUnion(nextIDs)
            if usrIDs.count == usrCount {
                break
            }
            newIDs = nextIDs
        }

//        print(usrIDs)

        return usrIDs.count != 0 ? usrIDs.map { $0 } : nil
    }

    func entitiesFor( usrIDs: [Int], callback: (_ entities: [Entity]) -> Void ) {
        let usrIn = usrIDs.map { String($0) }.joined(separator: ",")
        let dirIDs = projectDirIDs.keys.map { String($0) }.joined(separator: ",")

        let referenceSQL2 = "select __ENTITYCOLS__, 0" +
            " from reference t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where t.resolution in(\(usrIn)) and (f.directory in(\(dirIDs)) or t.\(roleIsDecl))"
        let symbolSQL2 = "select __ENTITYCOLS__, 1" +
            " from symbol t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where t.resolution in(\(usrIn)) and (f.directory in(\(dirIDs)) or t.\(roleIsDecl))"

        execute(sql: "\(referenceSQL2) union \(symbolSQL2)", with: [], callback: callback)
    }

    func declarationFor( filePath: String, line: Int, col: Int ) -> Entity? {
        guard let (fileid, fileID, dirID) = lookup( filePath: filePath ) else { return nil }
        var entities = [Entity]()

        let symbolSQL = "select __ENTITYCOLS__, 1" +
            " from symbol t" +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " inner join (select r.resolution " +
            " from reference r " +
            " inner join group_ g on (g.id = r.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            " and r.lineNumber = ? and r.column = ?" +
            " union " +
            " select s.resolution " +
            " from symbol s " +
            " inner join group_ g on (g.id = s.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ?" +
            "  and s.lineNumber = ? and s.column = ?) x " +
            "   on (x.resolution = t.resolution and x.resolution != 0 and t.\(roleIsDecl))"

        execute(sql: symbolSQL, with: [fileid, fileID, dirID, line, col, fileid, fileID, dirID, line, col] ) {
            _ = $0.map { entities.append( $0 ) }
        }

        dump(entities)
        guard !entities.isEmpty else {
            xcode.error("Could not find declaration")
            return nil
        }
        return entities[0]
    }

    func entitiesFor( pattern: String ) -> [[Entity]] {
        var entitiesByFile = [[Entity]]()

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let ids = IndexDB.resolutions.backward.keys.filter {
                (usr) -> Bool in
                let demangled = demangle( usr )!, range = NSMakeRange(0, demangled.utf16.count)
                return regex.firstMatch(in: demangled, options: [], range: range) != nil
                }.map { String( IndexDB.resolutions.backward[$0] ?? -1 ) }

            let inner = ids.joined(separator:",")
            let referenceSQL = "select __ENTITYCOLS__, 0" +
                " from reference t " +
                " inner join group_ g on (g.id = t.group_)" +
                " inner join file f on (f.id = g.file)" +
                " where t.resolution in(\(inner))"
            let symbolSQL = "select __ENTITYCOLS__, 1" +
                " from symbol t " +
                " inner join group_ g on (g.id = t.group_)" +
                " inner join file f on (f.id = g.file)" +
                " where t.resolution in(\(inner))"

            execute(sql: "\(referenceSQL) union \(symbolSQL)", with: [] ) {
                if projectDirIDs[$0[0].dirID] != nil {
                    entitiesByFile.append($0)
                }
            }
        }
        catch (let e) {
            xcode.log("Invalid symbol regex: \(e)" )
        }

        return entitiesByFile
    }

    func orphans() -> [[Entity]] {
        var usrIDs = [Int:Bool](), out = [Int:Bool]()

        _ = select( sql: "select resolution from reference", ids: [] ) {
            (stmt) in
            usrIDs[Int(sqlite3_column_int64(stmt, 0))] = true
        }

        _ = select( sql: "select resolution from symbol", ids: [] ) {
            (stmt) in
            let usrID = Int(sqlite3_column_int64(stmt, 0))
            if usrIDs[usrID] == nil {
                out[usrID] = true
            }
        }

        let symbolSQL = "select __ENTITYCOLS__, 1" +
            " from symbol t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where resolution in(\(out.keys.map { String($0) }.joined(separator:",")))"

        var entitiesByFile = [[Entity]]()
        execute(sql: symbolSQL, with: [] ) {
            if projectDirIDs[$0[0].dirID] != nil && podDirIDs[$0[0].dirID] == nil {
                entitiesByFile.append($0)
            }
        }

        return entitiesByFile
    }

    func dependencies() -> [(String,String, Int)] {
        let dirIDS = projectDirIDs.keys.filter { self.podDirIDs[$0] == nil }.map { String($0) }.joined(separator: ",")

        let SQL = "select f.directory, f.filename, f1.directory, f1.filename, count(s.resolution)" +
            " from symbol s" +
            " inner join group_ g on (g.id = s.group_)" +
            " inner join file f on (f.id = g.file)" +
            " inner join reference r on (s.resolution = r.resolution and s.resolution != 0)" +
            " inner join group_ g1 on (g1.id = r.group_)" +
            " inner join file f1 on (f1.id = g1.file)" +
            " where f.directory in(\(dirIDS)) and f1.directory in(\(dirIDS)) and s.role = 2" +
            " and not (f.directory == f1.directory and f.filename == f1.filename)" +
            " group by f.directory, f.filename, f1.directory, f1.filename"

        var dependencies = [(String,String,Int)]()

        guard select( sql:SQL, ids: [], row: {
            (stmt) in
            let dirID = Int(sqlite3_column_int64(stmt, 0))
            let fileID = Int(sqlite3_column_int64(stmt, 1))
            let dirID1 = Int(sqlite3_column_int64(stmt, 2))
            let fileID1 = Int(sqlite3_column_int64(stmt, 3))
            let count = Int(sqlite3_column_int64(stmt, 4))

            dependencies.append( (directories[dirID]!+"/"+filenames[fileID]!,
                                  directories[dirID1]!+"/"+filenames[fileID1]!,
                                  count))
        } ) else {
            xcode.error( "Dependencies prepare error \(error)" ); return dependencies
        }

        return dependencies
    }

    func dependsOn( path: String ) -> [[Entity]] {
        var entitiesByFile = [[Entity]]()
        guard let (fileid, fileID, dirID) = lookup( filePath: path ) else { return entitiesByFile }

        let symbolSQL = "select __ENTITYCOLS__, 0" +
            " from reference t " +
            " inner join group_ g on (g.id = t.group_)" +
            " inner join file f on (f.id = g.file) " +
            " inner join (select s.resolution, f.directory as directory1, f.filename as filename1 " +
            " from symbol s " +
            " inner join group_ g on (g.id = s.group_)" +
            " inner join file f on (f.id = g.file)" +
            " where f.lowercaseFilename = ? and f.filename = ? and f.directory = ? and \(roleIsDecl)" +
            " ) x on (x.resolution = t.resolution and x.resolution != 0)" +
            " where not (f.directory == x.directory1 and f.filename == x.filename1)"

        execute(sql: symbolSQL, with: [fileid, fileID, dirID] ) {
            entitiesByFile.append( $0 )
        }

        return entitiesByFile
    }
    
    func projectEntities() -> [[Entity]] {
        let projectDirs = projectDirIDs.keys.map { String($0) }.joined(separator: ",")
        let symbolSQL = "select __ENTITYCOLS__, 1" +
            " from file f " +
            " inner join group_ g on (f.id = g.file)" +
            " inner join symbol t on (g.id = t.group_)" +
            " where directory in(\(projectDirs))"
        let referenceSQL = "select __ENTITYCOLS__, 0" +
            " from file f " +
            " inner join group_ g on (f.id = g.file)" +
            " inner join reference t on (g.id = t.group_)" +
            " where directory in(\(projectDirs))"

        var entitiesByFile = [[Entity]]()
        execute(sql: "\(symbolSQL) union \(referenceSQL)", with: [] ) {
            entitiesByFile.append($0)
        }

        return entitiesByFile
    }

    func execute( sql: String, with ids: [Int], callback: (_ entities: [Entity]) -> Void ) {
        var already = [Entity:Bool]()
        var entities = [Entity]()
        var currentPath: String?

        let sql = sql.replacingOccurrences(of: "__ENTITYCOLS__",
                                           with: "directory, filename, lineNumber, column, kind, t.resolution, t.role")
        guard select( sql: "\(sql) order by directory desc, filename, lineNumber, column", ids: ids, row: {
            (stmt) in

            let dirID = Int(sqlite3_column_int64(stmt, 0))
            let fileID = Int(sqlite3_column_int64(stmt, 1))
            let line = Int(sqlite3_column_int64(stmt, 2))
            let col = Int(sqlite3_column_int64(stmt, 3))
            let kindID = Int(sqlite3_column_int64(stmt, 4))
            let usrID = Int(sqlite3_column_int64(stmt, 5))
            let role = Int(sqlite3_column_int64(stmt, 6))
            let isSymbol = sqlite3_column_int64(stmt, 7) != 0

            if line != 0 {
                if let file = self.filenames[fileID], let dir = self.directories[dirID] {
                    let path = dir+"/"+file
                    if path != currentPath {
                        if currentPath != nil {
                            callback( entities )
                            entities.removeAll()
                        }
                        currentPath = path
                    }

                    let entity = Entity( file: path, line: line, col: col, dirID: dirID,
                                         kindID: kindID, decl: isSymbol && (role == 1 || role == 2),
                                         usrID: usrID, role: role )

                    if already[entity] == nil {
                        entities.append( entity )
                        already[entity] = true
                    }
                }
                else {
                    xcode.log( "Could not look up fileID: \(fileID) or dirID: \(dirID)" )
                }
            }

        } ) else {
            xcode.error( "Entities prepare error \(error), SQL: \(sql)" ); return
        }

        if !entities.isEmpty {
            callback( entities )
        }
    }

    func entitiesForUSR( usr: String, oldValue: String ) -> [Entity] {
        var entities = [Entity]()
        entitiesForUSR( usr: usr, oldValue: oldValue, callback: {
            entities += $0
        } )
        return entities
    }

    func entitiesForUSR( usr: String, oldValue: String, callback: (_ entities: [Entity]) -> Void ) {
        if let resID = IndexDB.resolutions[usr] {
            var entities = [Entity]()
            var currentPath: String!

            let referenceSQL = "select f.filename, f.directory, r.lineNumber, r.column, r.kind, 0" +
                " from reference r " +
                " inner join group_ g on (g.id = r.group_)" +
                " inner join file f on (f.id = g.file)" +
                " where r.resolution = ?"
            let symbolSQL = "select f.filename, f.directory, s.lineNumber, s.column, s.kind, 1" +
                " from symbol s " +
                " inner join group_ g on (g.id = s.group_)" +
                " inner join file f on (f.id = g.file)" +
                " where s.resolution = ?"

            guard select( sql: referenceSQL + " union " + symbolSQL, ids: [resID, resID], row: {
                (stmt) in

                let fileID = Int(sqlite3_column_int64(stmt, 0))
                let dirID = Int(sqlite3_column_int64(stmt, 1))
                let line = Int(sqlite3_column_int64(stmt, 2))
                let col = Int(sqlite3_column_int64(stmt, 3))
                let kindID = Int(sqlite3_column_int64(stmt, 4))
                let decl = sqlite3_column_int64(stmt, 5) != 0

                if line != 0 {
                    if let file = self.filenames[fileID], let dir = self.directories[dirID] {
                        let path = dir+"/"+file
                        if path != currentPath {
                            if currentPath != nil {
                                callback( entities )
                                entities.removeAll()
                            }
                            currentPath = path
                        }

                        entities.append( Entity( file: path, line: line, col: col, kindID: kindID, decl: decl ) )
                    }
                    else {
                        xcode.log( "Could not look up fileID: \(fileID) or dirID: \(dirID)" )
                    }
                }

            } ) else {
                xcode.error( "Entities prepare error \(error)" ); return
            }

            if !entities.isEmpty {
                callback( entities )
            }
        }
    }

}

// not public in Swift3

@_silgen_name("swift_demangle")
public
func _stdlib_demangleImpl(
    _ mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<UInt8>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?


func _stdlib_demangleName(_ mangledName: String) -> String {
    return mangledName.utf8CString.withUnsafeBufferPointer {
        (mangledNameUTF8) in

        let demangledNamePtr = _stdlib_demangleImpl(
            mangledNameUTF8.baseAddress,
            mangledNameLength: UInt(mangledNameUTF8.count - 1),
            outputBuffer: nil,
            outputBufferSize: nil,
            flags: 0)

        if let demangledNamePtr = demangledNamePtr {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return mangledName
    }
}

func demangle( _ usr: String? ) -> String? {
    return usr?.hasPrefix("s:") == true ? _stdlib_demangleName("_T"+usr!.substring(from: usr!.index(usr!.startIndex, offsetBy: 2))) : usr
}
