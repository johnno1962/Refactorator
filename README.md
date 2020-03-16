# Refactorator Xcode Plugin

Due to changes in the index database with Xcode 10 this plugin no longer works.

Refactorator is an Xcode plugin for refactoring Swift & now Objective-C code. It will
rename public or internal vars, functions, enums etc. For private and local entities
use Xcode's existing "Edit All in Scope" functionality.

Stop Press: Refactorator no longer uses [SourceKit](http://www.jpsim.com/uncovering-sourcekit/) directly,
rather it accesses the SQLite database Xcode compiles using SourceKit. This makes it both faster as it
no longer needs to re-index the sources of your project but also means all targets of a project are
included in refactoring including code written in Objectve-C.

An improved version of Refactorator is now available as a standalone App avilable [here](https://github.com/johnno1962/RefactoratorApp)

![Icon](http://injectionforxcode.johnholdsworth.com/refactorator.png)

To use, download the source for this project and build to install the plugin
then restart Xcode. Not used a Plugin before? Use [Alcatraz Package Manager](http://alcatraz.io/)
to install it. Select a symbol in a Swift source and use "Right-click/Refactor/Swift !"
to list places in the target that declare or refer to that symbol.
Enter a new value for the identifier in the bottom textfield and press
the "Preview" button to view the changes that would be made.
Press the "Save" button to save these changes to disk. Use the
"Undo" button to revert the changes if need be.

As a by-product of the analysis performed for refactoring, if you have 
[Graphviz](http://www.graphviz.org/) installed, you can view an approximate
visualisation of the classes in your project and their interrelationships
using the "Edit/Refactor/Visualise !" menu item. Initialiser calls are
coloured green, ivar references blue, and method calls red:

![Icon](http://injectionforxcode.johnholdsworth.com/visualiser.png)

Refactorator was originally suggested as being feasible by @Daniel1of1 shortly after
Swift came out building on the work by @jpsim on [SourceKitten](https://github.com/jpsim/SourceKitten).
The last piece of the puzzle was the Open Sourcing of the SourceKit API by Apple as a part of Swift.
Source files are parsed using data from the same XPC calls that Xcode uses when it indexes
a project and implemented in a daemon process so as not to affect the stability of Xcode.
Invaluable in underdstanding the index database was [DB Browser for SQLite](http://sqlitebrowser.org/) 
and the SQLite Swift code was helped along by reference to the excellent [SQLite.swift](https://github.com/stephencelis/SQLite.swift).

### MIT License

Copyright (C) 2015 John Holdsworth

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
documentation files (the "Software"), to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, 
and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial 
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT 
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This source includes a header file "sourcekit.h" from Apple's Swift distribution under Apache License v2.0
