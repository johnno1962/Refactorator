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

class Entity: Hashable {

    let file: String, line: Int, col: Int, kind: String?, decl: Bool

    init( file: String, line: Int, col: Int, kind: String? = nil, decl: Bool = false ) {
        self.file = file
        self.line = line
        self.col = col
        self.kind = kind
        self.decl = decl
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
        if let matches = regex( value ).match( contents ) {
            var b = "<b title='" + (kind ?? "UNKNOWN") + "'"
            if decl {
                b += " style='color: blue'"
            }
            b += ">"
            return htmlClean( contents, match: matches[1] ) +
               b + htmlClean( contents, match: matches[2] ) + "</b>" +
                   htmlClean( contents, match: matches[3] )
        }
        return "MATCH FAILED line:\(line) column:\(col)"
    }

    func htmlClean( contents: NSData, match: regmatch_t ) -> String {
        var range = match.range
        if range.length > contents.length - range.location {
            range.length = contents.length - range.location
        }
        return String.fromData( contents.subdataWithRange( range ) )?
            .stringByReplacingOccurrencesOfString( "&", withString: "&amp;" )
            .stringByReplacingOccurrencesOfString( "<", withString: "&lt;" ) ?? "CONVERSION FAILED"
    }

}

func ==(lhs: Entity, rhs: Entity) -> Bool {
    return lhs.line == rhs.line && lhs.col == rhs.col && lhs.file == rhs.file
}

func <(e1: Entity, e2: Entity) -> Bool {
    let file1 = NSURL( fileURLWithPath: e1.file ).lastPathComponent!,
    file2 = NSURL( fileURLWithPath: e2.file ).lastPathComponent!
    if file1 < file2 { return true }
    if file1 > file2 { return false }
    if e1.line < e2.line { return true }
    if e1.line > e2.line { return false }
    return e1.col < e2.col
}
