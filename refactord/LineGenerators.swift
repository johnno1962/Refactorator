//
//  LineGenerators.swift
//  refactord
//
//  Created by John Holdsworth on 19/12/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/refactord/LineGenerators.swift#6 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

import Foundation

class TaskGenerator: FileGenerator {

    let task: NSTask

    convenience init( command: String, directory: String? = nil, lineSeparator: String? = nil ) {
        self.init( launchPath: "/bin/bash", arguments: ["-c", "exec \(command)"], directory: directory, lineSeparator: lineSeparator )
    }

    convenience init( launchPath: String, arguments: [String] = [], directory: String? = nil, lineSeparator: String? = nil ) {

        let task = NSTask()
        task.launchPath = launchPath
        task.arguments = arguments
        task.currentDirectoryPath = directory ?? "."

        self.init( task: task, lineSeparator: lineSeparator )
    }

    init( task: NSTask, lineSeparator: String? = nil ) {

        self.task = task

        let pipe = NSPipe()
        task.standardOutput = pipe.fileHandleForWriting
        task.launch()

        pipe.fileHandleForWriting.closeFile()
        super.init( handle: pipe.fileHandleForReading, lineSeparator: lineSeparator )
    }

    deinit {
        task.terminate()
    }

}

class FileGenerator: GeneratorType {

    let eol: Int32
    let handle: NSFileHandle
    let readBuffer = NSMutableData()

    convenience init?( path: String, lineSeparator: String? = nil ) {
        guard let handle = NSFileHandle( forReadingAtPath: path ) else { return nil }
        self.init( handle: handle, lineSeparator: lineSeparator )
    }

    init( handle: NSFileHandle, lineSeparator: String? = nil ) {
        self.eol = Int32((lineSeparator ?? "\n").utf16.first!)
        self.handle = handle
    }

    func next() -> String? {
        while true {
            let endOfLine = UnsafeMutablePointer<Int8>( memchr( readBuffer.bytes, eol, readBuffer.length ) )
            if endOfLine != nil {
                endOfLine[0] = 0

                let start = UnsafeMutablePointer<Int8>(readBuffer.bytes)
                let line = String.fromCString( start )

                let consumed = NSMakeRange( 0, endOfLine + 1 - start )
                readBuffer.replaceBytesInRange( consumed, withBytes:nil, length:0 )

                return line
            }

            let bytesRead = handle.availableData
            if bytesRead.length <= 0 {
                if readBuffer.length != 0 {
                    let last = String.fromData( readBuffer )
                    readBuffer.length = 0
                    return last
                }
                else {
                    break
                }
            }

            readBuffer.appendData( bytesRead )
        }
        return nil
    }

    var sequence: AnySequence<String> {
        return AnySequence({self})
    }

    deinit {
        handle.closeFile()
    }
}

extension String {

    static func fromData( data: NSData, encoding: UInt = NSUTF8StringEncoding ) -> String? {
        return NSString( data: data, encoding: encoding ) as? String
    }

}
