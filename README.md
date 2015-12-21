## Refactorator

Refactorator is an Xcode plugin for refactoring Swift code. It will rename 
public or internal vars, functions, enums etc. For private and local entities
use Xcode's existing "Edit All in Scope" functionality. 

![Icon](http://injectionforxcode.johnholdsworth.com/refactor.png)

To use, download the source for the project and build to install the plugin
then restart Xcode. Select a symbol and use "Right-click/Refactor/Swift !"
to list the places in your code that declare and refer to that symbol.
Enter a new value for the identifier in the bottom textfield and press
the "Preview" button to view the changes that would be made.
Press the "Save" button to save these changes to disk.

Refactorator was originally suggested as being feasible by @Daniel1of1 shortly after
Swift came out and uses [SourceKit](http://www.jpsim.com/uncovering-sourcekit/) 
distributed with Xcode, building on the work by @jpsim. The final piece of the
puzzle was the Open Sourcing of the SourceKit API by Apple as a part of Swift.
Source files are parsed using the same XPC calls that Xcode uses when it indexes
a project. The plugin's main limitation is that it does not currently refactor
across targets in the interests of speed.

Happy Christmas!

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