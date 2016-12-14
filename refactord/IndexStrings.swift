//
//  IndexStrings.swift
//  refactord
//
//  Created by John Holdsworth on 29/01/2016.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/IndexStrings.swift#8 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//
//

import Foundation

func mtime( _ path: String ) -> TimeInterval {
    if path.contains(".DS_Store") {
        return -2
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.modificationDate] as! NSDate).timeIntervalSinceReferenceDate
    }
    catch {
        return -1
    }
}

class IndexStrings {

    static var cache = [String:IndexStrings]()

    static func load( path: String ) -> IndexStrings {
        if cache[path] == nil || mtime( path ) > cache[path]!.loaded {
            cache[path] = IndexStrings(path: path)
        }
        return cache[path]!
    }

    let loaded: TimeInterval
    var forward = [Int:String]()
    var backward = [String:Int]()

    init( path: String ) {
        loaded = mtime( path )
        if let data = NSData( contentsOfFile: path ) {
            let bytes = data.bytes.assumingMemoryBound(to: CChar.self)

            var pos = 1
            while pos < data.length {
                let str = String( cString: bytes+pos )
                    if backward[str] != nil {
                        print( "Refactorator: Duplicate string \(str) \(backward[str]) \(pos) in \(path)" )
                    }
                    forward[pos] = str
                    backward[str] = pos
//                }
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
