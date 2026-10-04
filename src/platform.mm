#import <AppKit/AppKit.h>

bool fieldnotesSystemReduceMotion() {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}

#include <QWindow>

// The expanded Qt client area paints behind the title bar but does not provide
// AppKit's usual draggable title-bar view. Keep dragging native and independent
// of QML hit testing; native traffic lights remain outside this view's bounds.
@interface FieldnotesTitleDragView : NSView
@end
@implementation FieldnotesTitleDragView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (NSView *)hitTest:(NSPoint)point {
    if (self.window.styleMask & NSWindowStyleMaskFullScreen) return nil;
    return [super hitTest:point];
}
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        [self.window performZoom:nil];
    } else {
        [self.window performWindowDragWithEvent:event];
    }
}
@end

void fieldnotesStyleWindow(QWindow *window) {
    NSView *view = (__bridge NSView *)(void *)window->winId();
    NSWindow *nativeWindow = view.window;
    nativeWindow.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    nativeWindow.titleVisibility = NSWindowTitleHidden;
    nativeWindow.titlebarAppearsTransparent = YES;
    const CGFloat controlsWidth = 80;
    const CGFloat titleHeight = MAX(28, nativeWindow.frame.size.height - nativeWindow.contentLayoutRect.size.height);
    FieldnotesTitleDragView *dragView = [[FieldnotesTitleDragView alloc]
        initWithFrame:NSMakeRect(controlsWidth, view.isFlipped ? 0 : view.bounds.size.height - titleHeight,
                                MAX(0, view.bounds.size.width - controlsWidth), titleHeight)];
    dragView.autoresizingMask = NSViewWidthSizable | (view.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    [view addSubview:dragView];
    [dragView release];
    nativeWindow.backgroundColor = [NSColor colorWithRed:0.951 green:0.969 blue:0.941 alpha:1];
}
