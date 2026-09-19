#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <initializer_list>
#import "Shared.h"

static uint64_t lastPublished;
static CFAbsoluteTime lastForegroundSeen;

static id CTCall(id object, const char *name) {
    SEL selector = sel_registerName(name);
    return object && [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static NSString *CTIdentifier(id application) {
    for (const char *selector : {"bundleIdentifier", "displayIdentifier", "applicationIdentifier"}) {
        id value = CTCall(application, selector);
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    }
    return nil;
}

static void CTPublishIfChanged(NSString *identifier) {
    uint64_t hash = CTBundleHash(identifier);
    if (hash == lastPublished) return;
    // A backgrounded app must not erase the next foreground app's state.
    if (!identifier && CTForegroundHash() != lastPublished) return;
    lastPublished = hash;
    CTPublishForeground(identifier);
}

static BOOL CTIsSpringBoard(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
}

static void CTPollSpringBoard(void) {
    id app = nil;
    for (const char *selector : {"_accessibilityFrontMostApplication", "accessibilityFrontMostApplication", "frontmostApplication"}) {
        app = CTCall([UIApplication sharedApplication], selector);
        if (app) break;
    }
    if (!app) {
        id owner = CTCall((id)objc_getClass("SBApplicationController"), "sharedInstance");
        app = CTCall(owner, "frontmostApplication");
    }
    NSString *identifier = CTIdentifier(app);
    if (identifier.length) {
        lastForegroundSeen = CFAbsoluteTimeGetCurrent();
        CTPublishIfChanged(identifier);
    } else if (CFAbsoluteTimeGetCurrent() - lastForegroundSeen >= 1.5) {
        CTPublishIfChanged(nil);
    }
}

%hook UIApplication
- (void)didBecomeActive {
    %orig;
    if (CTIsSpringBoard()) CTPollSpringBoard();
    else CTPublishIfChanged([[NSBundle mainBundle] bundleIdentifier]);
}

- (void)didEnterBackground {
    %orig;
    if (!CTIsSpringBoard()) CTPublishIfChanged(nil);
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (CTIsSpringBoard()) {
            CTPollSpringBoard();
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                (void)timer;
                CTPollSpringBoard();
            }];
        } else if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            CTPublishIfChanged([[NSBundle mainBundle] bundleIdentifier]);
        }
    });
}
