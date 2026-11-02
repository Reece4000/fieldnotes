#import <AppKit/AppKit.h>

bool fieldnotesSystemReduceMotion() {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}

#include <QWindow>

// The header band lives in the title bar. An empty compact toolbar makes the title bar
// 38 tall and centres the traffic lights in it (x 12 to 66); its own view is hidden, because it
// would take every click in the strip from the Qt view below. The band moves the
// window itself (QML calls startSystemMove), so the strip stays one surface.
static void fieldnotesHideToolbarView(NSWindow *window) {
    NSView *titlebar = [window standardWindowButton:NSWindowCloseButton].superview;
    for (NSView *view in titlebar.subviews)
        if ([NSStringFromClass([view class]) isEqualToString:@"NSToolbarView"]) view.hidden = YES;
}

void fieldnotesStyleWindow(QWindow *window) {
    NSView *view = (__bridge NSView *)(void *)window->winId();
    NSWindow *nativeWindow = view.window;
    nativeWindow.titleVisibility = NSWindowTitleHidden;
    nativeWindow.titlebarAppearsTransparent = YES;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"fieldnotes"];
    nativeWindow.toolbar = toolbar;
    [toolbar release];
    nativeWindow.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    nativeWindow.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    fieldnotesHideToolbarView(nativeWindow);
    // Full screen moves the title bar into its own window and back; hide the view again after.
    for (NSNotificationName name : {NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification})
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nativeWindow queue:nil
            usingBlock:^(NSNotification *note) { fieldnotesHideToolbarView(note.object); }];
    // The appearance follows the theme (QML sets the colour scheme); the window
    // background follows the appearance, so a resize never flashes the wrong tone.
    nativeWindow.backgroundColor = NSColor.windowBackgroundColor;
}
