//
//  SwifactorPlugin.m
//  Swifactor
//
//  Created by John Holdsworth on 01/05/2014.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Swifactor/Classes/SwifactorPlugin.m#2 $
//
//  Repo: https://github.com/johnno1962/Swifactor
//

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"

#import "SwifactorPlugin.h"

@import Cocoa;
@import WebKit;
@import ObjectiveC.runtime;

static SwifactorPlugin *swifactorPlugin;

@implementation SwifactorPlugin {
    Class IDEWorkspaceWindowControllerClass;
    NSWindowController *lastWindowController;
    NSTask *refactorTask;

    NSConnection *doConnection;
    id<SwifactorRequest> refactord;

    IBOutlet NSPanel *panel;
    IBOutlet NSTextField *oldValueField, *usrField, *newValueField;
    IBOutlet NSButton *performButton, *confirmButton;
    IBOutlet WebView *webView;
@public
    IBOutlet NSMenuItem *refactorItem;
}

// MARK: Initialisation

+ (void)pluginDidLoad:(NSBundle *)plugin {
    if ([[NSBundle mainBundle].infoDictionary[@"CFBundleName"] isEqual:@"Xcode"]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            swifactorPlugin = [[self alloc] init];
            [[NSNotificationCenter defaultCenter] addObserver:swifactorPlugin
                                                     selector:@selector(applicationDidFinishLaunching:)
                                                         name:NSApplicationDidFinishLaunchingNotification object:nil];
        });
    }
}

- (oneway void)error:(NSString *)message {
    dispatch_async( dispatch_get_main_queue(), ^{
        [[NSAlert alertWithMessageText:@"Swifactor Error" defaultButton:@"OK" alternateButton:nil otherButton:nil
             informativeTextWithFormat:@"%@", message] runModal];
    } );
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {

    if ( ![[NSBundle bundleForClass:[self class]] loadNibNamed:[self className] owner:self topLevelObjects:NULL] ) {
        if ( [[NSAlert alertWithMessageText:@"Swifactor Plugin:"
                              defaultButton:@"OK" alternateButton:@"Goto GitHub" otherButton:nil
                  informativeTextWithFormat:@"Could not load interface nib. This was a problem using Alcatraz with Xcode6. Please download and build from the sources on GitHub."]
              runModal] == NSAlertAlternateReturn )
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/johnno1962/Swifactor"]];
        return;
    }

    NSMenu *editMenu = [[NSApp mainMenu] itemWithTitle:@"Edit"].submenu;
    NSMenu *refactorMenu = [editMenu itemWithTitle:@"Refactor"].submenu;
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

    NSURL *logURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"log" withExtension:@"html"];
    [webView.mainFrame loadRequest:[NSURLRequest requestWithURL:logURL]];

    NSTextView *textView = self.textView;
    NSRange range = textView.selectedRange;

    if ( [sender isKindOfClass:[NSMenuItem class]] )
        oldValueField.stringValue = [textView.string substringWithRange:range];

    newValueField.stringValue = oldValueField.stringValue;
    performButton.enabled = confirmButton.enabled = FALSE;
    usrField.stringValue = @"";

    [refactorTask terminate];

    refactorTask = [NSTask new];
    refactorTask.launchPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"refactord" ofType:nil];
    refactorTask.currentDirectoryPath = @"/tmp";
    [refactorTask launch];

    while ( !(doConnection = [NSConnection connectionWithRegisteredName:@SWIFACTOR_SERVICE
                                                                   host:nil]) )
           [NSThread sleepForTimeInterval:.1];

    refactord = (id<SwifactorRequest>)[doConnection rootProxy];
    [(id)refactord setProtocolForProxy:@protocol(SwifactorRequest)];

    int offset = [[textView.string substringWithRange:NSMakeRange( 0, range.location )]
                  lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self try:^{
            NSLog( @"Swifactoring: %@ %d %@", refactord, offset, [self logDirectory] );
            int refs = [refactord refactorFile:self.currentFile byteOffset:offset
                                         oldValue:oldValueField.stringValue
                                           logDir:[self logDirectory] plugin:self];
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *html = @"<br><b>Indexing Complete. Symbol referenced in %d places. "
                    "<a href='http://injectionforxcode.johnholdsworth.com/swifactor.html'>usage</a><p>";
                [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[[NSString stringWithFormat:html, refs]]];
                performButton.enabled = TRUE;
            } );
        }];
    } );
}

- (oneway void)foundUSR:(NSString *)usr {
    dispatch_async( dispatch_get_main_queue(), ^{
        usrField.stringValue = usr;
        [panel makeKeyAndOrderFront:self];
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

- (IBAction)performRefactor:(id)sender {
    [self try:^{
        [refactord refactorFrom:oldValueField.stringValue to:newValueField.stringValue];
        confirmButton.enabled = TRUE;
    }];
}

- (IBAction)confirmRefactor:(id)sender {
    [self try:^{
        confirmButton.enabled = FALSE;
        int patched = [refactord confirmRefactor];
        NSString *s =  patched == 1 ? @"" : @"s";
        NSString *msg = [NSString stringWithFormat:@"<p><b>%d file%@ modified.</b><br>", patched, s];
        [webView.windowScriptObject callWebScriptMethod:@"append" withArguments:@[msg]];
    }];
}

- (void)try:(void(^)())block {
    @try {
        block();
    }
    @catch ( NSException *e ) {
        [self error:[NSString stringWithFormat:@"Exception communicating with daemon: %@", e]];
    }
}

- (void)windowWillClose:(NSWindow *)window {
    [refactorTask terminate];
    refactorTask = nil;
}

// MARK: WebView

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
        request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id < WebPolicyDecisionListener >)listener {

    if ( [request.URL.path hasSuffix:@".html"] ) {
        [listener use];
        return;
    }

    [listener ignore];
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

@implementation NSTextView(Swifactor)

- (NSMenu *)rf_menuForEvent:(NSEvent *)event {
    NSMenu *contextMenu = [self rf_menuForEvent:event];
    NSMenu *refactorMenu = [contextMenu itemWithTitle:@"Refactor"].submenu;
    if ( swifactorPlugin && [refactorMenu indexOfItemWithTitle:swifactorPlugin->refactorItem.title] == -1 ) {
        NSMenuItem *refactorItem = [[NSMenuItem alloc] initWithTitle:swifactorPlugin->refactorItem.title
                                                              action:@selector(startRefactor:) keyEquivalent:@""];
        refactorItem.target = swifactorPlugin;
        [refactorMenu insertItem:refactorItem atIndex:0];
    }
    return contextMenu;
}

@end

#pragma clang diagnostic pop
