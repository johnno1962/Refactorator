//
//  Visualiser.swift
//  refactord
//
//  Created by John Holdsworth on 04/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/Visualiser.swift#9 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

struct Edge {
    let title: String
    let from: String
    let to: String
    let kind: sourcekitd_uid_t
}

class Visualiser {

    private var definingStack = [("global",SK.classID)]
    private var defining: (name: String, kind: sourcekitd_uid_t) {
        get {
            return definingStack[definingStack.count-1]
        }
        set(newValue) {
            definingStack[definingStack.count-1] = newValue
        }
    }

    func enter() {
        definingStack.append( defining )
    }

    func exit() {
        definingStack.removeAtIndex( definingStack.count-1 )
    }

    func present( dict: sourcekitd_variant_t, indent: String ) {
        let kind = sourcekitd_variant_dictionary_get_uid( dict, SK.kindID )
        let usr = sourcekitd_variant_dictionary_get_string( dict, SK.usrID )
        let name = sourcekitd_variant_dictionary_get_string( dict, SK.nameID )

        if isTTY {
            let entityUSR = String.fromCString( usr )
            print( "\n\(indent)\(String.fromCString( sourcekitd_uid_get_string_ptr( kind ) )!) " )
            print( "\(indent)\(entityUSR!)" )
            if name != nil {
                print( indent+String.fromCString( name )! )
            }
            if entityUSR!.hasPrefix("s:") {
                print( "\(indent)\(disectUSR(entityUSR!))" )
            }
        }

        if usr != nil && name != nil, let name = String.fromCString( name ),
                usr = String.fromCString( usr ), details = disectUSR( usr ) {
            switch kind {
            case SK.structID, SK.classID://, SK.enumID:
                makeNode( name, kind:kind )
                defining = (name,kind)

            case SK.classVarID, SK.classMethodID, SK.initID, SK.varID, SK.methodID://, SK.elementID:
                if (kind != SK.initID || details[0] == "s:FC") && details[2] != defining.name {
                    makeNode( details[2], kind: nil )
                    makeEdge( name, from: defining.name, to: details[2], kind: kind )
                }
            default:
                break
            }
        }
    }

    private var objectHash = [String:sourcekitd_uid_t]()
    private var objectList = [String]()
    private var edgeHash = [String:Bool]()
    private var edgeList = [Edge]()

    private func makeNode( name: String, kind: sourcekitd_uid_t ) {
        if kind != nil {
            objectHash[name] = kind
            objectList.append( name )
        }
    }

    private func makeEdge( title: String, from: String, to: String, kind: sourcekitd_uid_t ) {
        let key = title+"/"+from+"/"+to
        if edgeHash[key] == nil {
            edgeHash[key] = true
            edgeList.append( Edge( title: title, from: from, to: to, kind: kind ) )
        }
    }

    func render( outPath: String ) -> Bool {
        let graph = fopen( outPath, "w" )
        guard graph != nil else { return false }

        fputs( "digraph xref {\n    node [href=\"javascript:void(click_node('\\N'))\" id=\"\\N\" fontname=\"Arial\"];\n", graph )
//        print( definingStack )
//        print( objectHash )
//        print( objectList )

        let filled = " style=\"filled\" fillcolor=\"#e0e0e0\""
        var idHash = [String:Int]()
        let color = "black"
        var oid = 0
        for name in objectList {
            let shape = objectHash[name] == SK.enumID ? " shape=parallelogram" : objectHash[name] == SK.structID ? " shape=box" : ""
            fputs( "    \(oid) [label=\"\(name)\" tooltip=\"<\(name)> #\(oid)\"\(shape)\(filled) color=\"\(color)\"];\n", graph )
            idHash[name] = oid
            oid += 1
        }

        for edge in edgeList {
            if let fromID = idHash[edge.from], toID = idHash[edge.to] {
                var color = "#000000"
                switch edge.kind {
                case SK.classVarID:
                    color = "#ffff00"
                case SK.classMethodID:
                    color = "#ff00ff"
                case SK.initID:
                    color = "#00ff00"
                case SK.varID:
                    color = "#0000ff"
                case SK.methodID:
                    color = "#ff0000"
                case SK.elementID:
                    color = "#00ffff"
                default:
                    break
                }
                fputs( "    \(fromID) -> \(toID) [label=\"\(edge.title)\" color=\"\(color)\" eid=\"\(0)\"];\n", graph )
            }
        }

        fputs( "}\n", graph )
        return fclose( graph ) == 0
    }

}

extension NSFileHandle {

    func append( str: String ) {
        str.withCString { bytes in
            writeData( NSData( bytesNoCopy: UnsafeMutablePointer<Void>(bytes),
                length: Int(strlen(bytes)), freeWhenDone: false ) )
        }
    }

}
