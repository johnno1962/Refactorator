//
//  Entity.swift
//  refactord
//
//  Created by John Holdsworth on 19/02/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//
//  $Id: //depot/siteify/siteify/Entity.swift#3 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

extension String {

    var url: URL {
        return hasPrefix( "http://" ) ? URL(string: self)! : URL(fileURLWithPath: self)
    }

}

class Entity: Hashable {

    let file: String, line: Int, col: Int, dirID: Int, kindID: Int, decl: Bool
    var offset: Int?, usrID: Int?, role: Int?
    var notMatch = false

    init( file: String, line: Int = -1, col: Int = -1, offset: Int? = nil, dirID: Int = -1, kindID: Int = -1, decl: Bool = false, usrID: Int? = nil, role: Int? = nil ) {
        self.file = file
        self.line = line
        self.col = col
        self.offset = offset
        self.dirID = dirID
        self.kindID = kindID
        self.decl = decl
        self.usrID = usrID
        self.role = role
    }

    var usr: String? {
        return usrID != nil ? IndexDB.resolutions[usrID!] : nil
    }
    var kind: String {
        return IndexDB.kinds[kindID] ?? "unknown"
    }
    var kindSuffix: String {
        return IndexDB.kindSuffixies[kindID] ?? "unknown"
    }
    var sourceName: String {
        return file.url.lastPathComponent
    }

    var hashValue: Int {
        return line + col
    }

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

    func patchText( contents: NSData, value: String ) -> String? {
        if let matches = regex( text: value ).match( input: contents ) {
            var b = "<b title='\(kind)'"
            if decl {
                b += " style='color: blue'"
            }
            b += ">"
            return htmlClean( contents: contents, match: matches[1] ) +
               b + htmlClean( contents: contents, match: matches[2] ) + "</b>" +
                   htmlClean( contents: contents, match: matches[3] )
        }
        return "MATCH FAILED line:\(line) column:\(col)"
    }

    func htmlClean( contents: NSData, match: regmatch_t ) -> String {
        var range = match.range
        if range.length > contents.length - range.location {
            range.length = contents.length - range.location
        }
        return String( data: contents.subdata( with: range ), encoding: String.Encoding.utf8 )?
            .replacingOccurrences( of: "&", with: "&amp;" )
            .replacingOccurrences( of: "<", with: "&lt;" ) ?? "CONVERSION FAILED"
    }

}

func ==(lhs: Entity, rhs: Entity) -> Bool {
    return lhs.line == rhs.line && lhs.col == rhs.col && lhs.file == rhs.file
}

func <(e1: Entity, e2: Entity) -> Bool {
//    let file1 = e1.file.url.lastPathComponent,
//    file2 = e2.file.url.lastPathComponent
//    if file1 < file2 { return true }
//    if file1 > file2 { return false }
    if e1.file < e2.file { return true }
    if e1.file > e2.file { return false }
    if e1.line < e2.line { return true }
    if e1.line > e2.line { return false }
    return e1.col < e2.col
}
