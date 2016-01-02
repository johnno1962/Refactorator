//
//  RefactoratorPlugin.m
//  Refactorator
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Refactorator/Classes/RefactoratorPlugin.m#26 $
//
//  Repo: https://github.com/johnno1962/Refactorator
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"

#import "RefactoratorPlugin.h"

@import Cocoa;
@import WebKit;
@import ObjectiveC.runtime;

static RefactoratorPlugin *refactoratorPlugin;

@implementation RefactoratorPlugin {
    Class IDEWorkspaceWindowControllerClass;
    NSWindowController *lastWindowController;
    NSTimeInterval lastRefactor;
    NSTask *refactorTask;
    NSString *lastUSR;
    BOOL daemonBusy;

    NSConnection *doConnection;
    id<RefactoratorRequest> refactord;

    IBOutlet NSPanel *panel;
    IBOutlet NSTextField *oldValueField, *usrField, *newValueField;
    IBOutlet NSButton *refineButton, *performButton, *confirmButton, *revertButton;
    IBOutlet WebView *webView;
@public
    NSMenuItem *refactorItem;
}

// MARK: Initialisation

+ (void)pluginDidLoad:(NSBundle *)plugin {
    if ([[NSBundle mainBundle].infoDictionary[@"CFBundleName"] isEqual:@"Xcode"]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            refactoratorPlugin = [[self alloc] init];
            dispatch_async( dispatch_get_main_queue(), ^{
                [refactoratorPlugin applicationDidFinishLaunching:nil];
                system( "kill `ps auxww | grep Refactorator.xcplugin/Contents/Resources/refactord | "
                       " grep -v grep | awk '{ print $2 }'` 2>/dev/null &" );
            } );
        } );
    }
}

- (oneway void)error:(NSString *)message {
    dispatch_async( dispatch_get_main_queue(), ^{
        [[NSAlert alertWithMessageText:@"Refactorator Error" defaultButton:@"OK" alternateButton:nil otherButton:nil
             informativeTextWithFormat:@"%@", message] runModal];
    } );
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {

    NSMenu *editMenu = [[NSApp mainMenu] itemWithTitle:@"Edit"].submenu;
    NSMenu *refactorMenu = [editMenu itemWithTitle:@"Refactor"].submenu;
    refactorItem = [[NSMenuItem alloc] initWithTitle:@"Swift !"
                                              action:@selector(startRefactor:) keyEquivalent:@""];
    refactorItem.target = refactoratorPlugin;
    [refactorMenu insertItem:refactorItem atIndex:0];

    [self swizzleClass:NSClassFromString(@"DVTSourceTextView")
              exchange:@selector(menuForEvent:)
                  with:@selector(rf_menuForEvent:)];

    IDEWorkspaceWindowControllerClass = NSClassFromString(@"IDEWorkspaceWindowController");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(workspaceDidChange:)
                                                 name:NSWindowDidBecomeKeyNotification object:nil];
}

- (void)swizzleClass:(Class)aClass exchange:(SEL)origMethod with:(SEL)altMethod
{
    method_exchangeImplementations(class_getInstanceMethod(aClass, origMethod),
                                   class_getInstanceMethod(aClass, altMethod));
}

- (void)workspaceDidChange:(NSNotification *)notification {
    NSWindow *object = [notification object];
    NSWindowController *newWindowController = [object windowController];
    if ([newWindowController isKindOfClass:IDEWorkspaceWindowControllerClass])
        lastWindowController = newWindowController;
}

- (NSString *)currentFile {
    return [[[[self currentEditor] document] fileURL] path];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return [self.currentFile hasSuffix:@".swift"];
}

// MARK: Refactoring

- (IBAction)startRefactor:(id)sender {

    if ( !webView &&
        ![[NSBundle bundleForClass:[self class]] loadNibNamed:[self className] owner:self topLevelObjects:NULL] ) {
        if ( [[NSAlert alertWithMessageText:@"Refactorator Plugin:"
                              defaultButton:@"OK" alternateButton:@"Goto GitHub" otherButton:nil
                  informativeTextWithFormat:@"Could not load interface nib. This was a problem using Alcatraz with Xcode6. Please download and build from the sources on GitHub."]
              runModal] == NSAlertAlternateReturn )
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/johnno1962/Refactorator"]];
        return;
    }

    NSURL *logURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"log" withExtension:@"html"];
    [webView.mainFrame loadRequest:[NSURLRequest requestWithURL:logURL]];

    NSTextView *textView = self.textView;
    NSRange range = textView.selectedRange;

    if ( [sender isKindOfClass:[NSMenuItem class]] )
        oldValueField.stringValue = [textView.string substringWithRange:range];

    newValueField.stringValue = oldValueField.stringValue;
    [newValueField selectText:self];
    refineButton.enabled = performButton.enabled = confirmButton.enabled = FALSE;
    usrField.stringValue = @"";

    lastRefactor = [NSDate timeIntervalSinceReferenceDate];

    if ( !refactorTask || daemonBusy )
        [self startDaemon];

    int offset = [[textView.string substringWithRange:NSMakeRange( 0, range.location )]
                  lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self try:^{
            NSLog( @"Refactorating: %@ %d %@", refactord, offset, [self logDirectory] );
            daemonBusy = TRUE;
            int refs = [refactord refactorFile:self.currentFile byteOffset:offset
                                         oldValue:oldValueField.stringValue
                                           logDir:[self logDirectory] plugin:self];
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *html = @"<br><b>Indexing Complete. Symbol referenced in %d places. "
                    "<a href='http://injectionforxcode.johnholdsworth.com/refactorator.html'>usage</a><p>";
                [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[[NSString stringWithFormat:html, refs]]];
                performButton.enabled = TRUE;
                daemonBusy = FALSE;
            } );
        }];
    } );
}

- (void)startDaemon {
    [refactorTask terminate];

    refactorTask = [NSTask new];
    refactorTask.launchPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"refactord" ofType:nil];
    refactorTask.currentDirectoryPath = @"/tmp";
    [refactorTask launch];

    while ( !(doConnection = [NSConnection connectionWithRegisteredName:REFACTORATOR_SERVICE
                                                                   host:nil]) )
        [NSThread sleepForTimeInterval:.1];

    refactord = (id<RefactoratorRequest>)[doConnection rootProxy];
    [(id)refactord setProtocolForProxy:@protocol(RefactoratorRequest)];

    [self housekeepDaemon];
}

- (void)housekeepDaemon {
    if ( [NSDate timeIntervalSinceReferenceDate] - lastRefactor > 12. * 60. * 60. ) {
        [refactorTask terminate];
        refactorTask = nil;
    }
    else
        [self performSelector:@selector(housekeepDaemon) withObject:nil afterDelay:60. * 60.];
}

- (oneway void)foundUSR:(NSString *)usr {
    dispatch_async( dispatch_get_main_queue(), ^{
        usrField.stringValue = lastUSR = usr;
        [panel makeKeyAndOrderFront:self];
    } );
}

- (oneway void)indexing:(NSString *)file {
    dispatch_async( dispatch_get_main_queue(), ^{
        usrField.stringValue = file ?
        [NSString stringWithFormat:@"Indexing: %@...", file.lastPathComponent] : lastUSR;
    } );
}

- (oneway void)willPatchFile:(NSString *)file line:(int)line col:(int)col text:(NSString *)text {
    dispatch_async( dispatch_get_main_queue(), ^{
        [webView.windowScriptObject callWebScriptMethod:@"showPatch" withArguments:@[file, file.lastPathComponent, @(line), @(col), text]];
    } );
}

- (oneway void)log:(NSString *)msg {
    dispatch_async( dispatch_get_main_queue(), ^{
        [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[msg]];
    } );
}

- (IBAction)enableRefine:(id)sender {
    refineButton.enabled = TRUE;
}

- (IBAction)performRefactor:(id)sender {
    [self try:^{
        [refactord refactorFrom:oldValueField.stringValue to:newValueField.stringValue];
        confirmButton.enabled = TRUE;
        revertButton.enabled = FALSE;
    }];
}

- (IBAction)confirmRefactor:(id)sender {
    [self try:^{
        confirmButton.enabled = FALSE;
        revertButton.enabled = TRUE;
        int patched = [refactord confirmRefactor];
        NSString *s =  patched == 1 ? @"" : @"s";
        NSString *msg = [NSString stringWithFormat:@"<p><b>%d file%@ modified.</b><br>", patched, s];
        [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[msg]];
    }];
}

- (IBAction)revertRefactor:(id)sender {
    [self try:^{
        revertButton.enabled = FALSE;
        int patched = [refactord revertRefactor];
        NSString *s =  patched == 1 ? @"" : @"s";
        NSString *msg = [NSString stringWithFormat:@"<p><b>%d file%@ reverted.</b><br>", patched, s];
        [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[msg]];
    }];
}

- (void)try:(void(^)())block {
    @try {
        block();
    }
    @catch ( NSException *e ) {
        if ( refactorTask )
            [self error:[NSString stringWithFormat:@"Exception communicating with daemon: %@", e]];
        [refactorTask terminate];
        refactorTask = nil;
    }
}

- (void)windowWillClose:(NSWindow *)window {
    if ( daemonBusy ) {
        [refactorTask terminate];
        refactorTask = nil;
    }
}

// MARK: WebView

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id < WebPolicyDecisionListener >)listener {

    if ( [request.URL.path hasSuffix:@".html"] ) {
        [listener use];
        return;
    }

    [listener ignore];
    //[panel miniaturize:self];
    NSArray *split = [request.URL.path componentsSeparatedByString:@"___"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:split[0]]];

    [self performSelector:@selector(selectLine:) withObject:split[1] afterDelay:.5];
}

- (void)webView:(WebView *)aWebView didReceiveTitle:(NSString *)aTitle forFrame:(WebFrame *)frame {
    panel.title = aTitle;
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    [self error:[NSString stringWithFormat:@"JavaScript alert: %@", message]];
}

- (void)webView:(WebView *)webView addMessageToConsole:(NSDictionary *)message {
    [self error:[NSString stringWithFormat:@"JavaScript problem: %@", message]];
}

// MARK: Utilities

// Thanks https://github.com/krzysztofzablocki/KZLinkedConsole
// I've no idea how this works but it does!

- (void)selectLine:(NSString *)lineString {
    NSTextView *textView = [self textView];
    NSString *text = textView.string;

    NSUInteger line = lineString.intValue, currentLine = 1, index = 0;
    for (; index < text.length; currentLine++) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(index, 0)];
        index = NSMaxRange(lineRange);

        if ( currentLine == line ) {
            [textView scrollRangeToVisible:lineRange];
            [textView setSelectedRange:lineRange];
            break;
        }
    }
}

- (NSTextView *)textView {
    id editor = [self currentEditor];
    return [editor respondsToSelector:@selector(textView)] ? [editor textView] : nil;
}

- (id)currentEditor {
    return [lastWindowController valueForKeyPath:@"editorArea.lastActiveEditorContext.editor"];
}

- (NSString *)logDirectory {
    return [lastWindowController valueForKeyPath:@"workspace.executionEnvironment.logStore.rootDirectoryPath"];
}

@end

@implementation NSTextView(Refactorator)

- (NSMenu *)rf_menuForEvent:(NSEvent *)event {
    NSMenu *contextMenu = [self rf_menuForEvent:event];
    NSMenu *refactorMenu = [contextMenu itemWithTitle:@"Refactor"].submenu;
    if ( refactoratorPlugin && [refactorMenu indexOfItemWithTitle:refactoratorPlugin->refactorItem.title] == -1 ) {
        NSMenuItem *refactorItem = [[NSMenuItem alloc] initWithTitle:refactoratorPlugin->refactorItem.title
                                                              action:@selector(startRefactor:) keyEquivalent:@""];
        refactorItem.target = refactoratorPlugin;
        [refactorMenu insertItem:refactorItem atIndex:0];
    }
    return contextMenu;
}

@end

#pragma clang diagnostic pop
