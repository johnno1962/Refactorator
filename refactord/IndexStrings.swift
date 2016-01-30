//
//  IndexStrings.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/IndexStrings.swift#3 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

class IndexStrings {

    var forward = [Int:String]()
    var backward = [String:Int]()

    init( path: String ) {
        if let data = NSData( contentsOfFile: path ) {
            let bytes = UnsafePointer<CChar>( data.bytes )

            var pos = 1
            while pos < data.length {
                if let str = String.fromCString( bytes+pos ) {
                    if backward[str] != nil {
                        print( "Refactorator: Duplicate string \(str) \(backward[str]) \(pos) in \(path)" )
                    }
                    forward[pos] = str
                    backward[str] = pos
                }
                pos += Int(strlen( bytes+pos ))+1
            }
        }
        else {
            xcode.log( "Could not load strings file: \(path)" )
        }
    }

    subscript( pos: Int ) -> String? {
        return forward[pos]
    }

    subscript( usr: String ) -> Int? {
        return backward[usr]
    }

}
