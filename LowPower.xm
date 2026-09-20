#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <os/lock.h>
#import <roothide.h>
#import "Shared.h"

// Independent preference domain; never reads or writes the original tweak's settings.
static NSString *CTPrefsPath(void) {
    return jbroot(@"/var/mobile/Library/Preferences/com.mox1121.cpulowpower.plist");
}
static NSString *CTOldPrefsPath(void) {
    return jbroot(@"/var/mobile/Library/Preferences/com.huayuarc.cputhermal.lowpower.plist");
}
static os_unfair_lock stateLock = OS_UNFAIR_LOCK_INIT;
static BOOL enabled;
static BOOL whitelistEnabled;
static BOOL effectiveLow;
static int capPercent = 45;
static int nativeZoneTarget = 100;
static __thread BOOL applyingBudget;
static BOOL screenBlanked;
static NSString *awakeStrength;
static NSString *lockStrength;
static NSArray<NSString *> *lowPowerApps;
static NSHashTable *controllers;
static BOOL clearPending;
static BOOL prefsRead;
static BOOL sawController;
static BOOL requestedBudget;

static void CTWriteStatus(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        os_unfair_lock_lock(&stateLock);
        NSString *report = [NSString stringWithFormat:
            @"version=0.6.0\nprocess=%@\nprefsPath=%@\nprefsRead=%d\nenabled=%d\nwhitelistEnabled=%d\neffectiveLow=%d\nscreenBlanked=%d\nprofile=%@\nceilingPercent=%d\nnativeZoneTarget=%d\nmitigationHook=%d\nbudgetRequested=%d\n",
            [NSProcessInfo processInfo].processName, CTPrefsPath(), prefsRead, enabled,
            whitelistEnabled, effectiveLow, screenBlanked,
            screenBlanked ? lockStrength : awakeStrength, capPercent, nativeZoneTarget,
            sawController, requestedBudget];
        os_unfair_lock_unlock(&stateLock);
        NSString *path = [[CTPrefsPath() stringByDeletingPathExtension] stringByAppendingString:@".status.txt"];
        NSError *error = nil;
        if (![report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error])
            NSLog(@"[CTLowPower] status write failed: %@", error);
    }
}

static BOOL CTActive(void) {
    os_unfair_lock_lock(&stateLock);
    BOOL active = enabled && effectiveLow;
    os_unfair_lock_unlock(&stateLock);
    return active;
}

static int CTCapPercent(void) {
    os_unfair_lock_lock(&stateLock);
    int result = capPercent;
    os_unfair_lock_unlock(&stateLock);
    return result;
}

static BOOL CTContainsHash(NSArray<NSString *> *identifiers, uint64_t hash) {
    if (!hash) return NO;
    for (id identifier in identifiers)
        if ([identifier isKindOfClass:[NSString class]] && CTBundleHash(identifier) == hash) return YES;
    return NO;
}

static BOOL CTDesiredMode(void) {
    os_unfair_lock_lock(&stateLock);
    BOOL selected = whitelistEnabled;
    BOOL blanked = screenBlanked;
    NSArray *whitelist = lowPowerApps;
    os_unfair_lock_unlock(&stateLock);
    return blanked || !selected || CTContainsHash(whitelist, CTForegroundHash());
}

static void CTCallUpdateCPU(id controller) {
    if ([controller respondsToSelector:@selector(updateCPU)])
        ((void (*)(id, SEL))objc_msgSend)(controller, @selector(updateCPU));
}

static void CTApplyController(id controller) {
    if (!CTActive()) return;
    if ([controller respondsToSelector:@selector(setCPMSMitigationsEnabled:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(setCPMSMitigationsEnabled:), YES);
    if ([controller respondsToSelector:@selector(setCPUPowerZoneTarget:)]) {
        os_unfair_lock_lock(&stateLock);
        int target = MIN(capPercent, nativeZoneTarget);
        os_unfair_lock_unlock(&stateLock);
        BOOL previous = applyingBudget;
        applyingBudget = YES;
        ((void (*)(id, SEL, int))objc_msgSend)(controller, @selector(setCPUPowerZoneTarget:), target);
        applyingBudget = previous;
        os_unfair_lock_lock(&stateLock);
        BOOL firstRequest = !requestedBudget;
        requestedBudget = YES;
        os_unfair_lock_unlock(&stateLock);
        if (firstRequest) CTWriteStatus();
    }
}

static void CTReapply(void) {
    NSArray *snapshot;
    os_unfair_lock_lock(&stateLock);
    snapshot = controllers.allObjects;
    os_unfair_lock_unlock(&stateLock);
    for (id controller in snapshot) { CTApplyController(controller); CTCallUpdateCPU(controller); }
}

static void CTApplyDesiredMode(void) {
    BOOL desired = CTDesiredMode();
    BOOL changed;
    os_unfair_lock_lock(&stateLock);
    NSString *strength = screenBlanked ? lockStrength : awakeStrength;
    int nextPercent = [strength isEqualToString:@"saver"] ? 35 : [strength isEqualToString:@"performance"] ? 75 : 55;
    changed = effectiveLow != desired || capPercent != nextPercent;
    effectiveLow = desired;
    capPercent = nextPercent;
    os_unfair_lock_unlock(&stateLock);
    if (changed) { CTReapply(); CTWriteStatus(); }
}

static void CTRefreshMode(void) {
    // Foreground state briefly becomes zero during app transitions.
    if (!screenBlanked && whitelistEnabled && CTForegroundHash() == 0 && !clearPending) {
        clearPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            clearPending = NO;
            CTApplyDesiredMode();
        });
        return;
    }
    CTApplyDesiredMode();
}

static void CTLoadSettings(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:CTPrefsPath()];
    if (!prefs) prefs = [NSDictionary dictionaryWithContentsOfFile:CTOldPrefsPath()];
    NSString *strength = [prefs[@"lowPowerStrength"] isKindOfClass:[NSString class]] ? prefs[@"lowPowerStrength"] : @"standard";
    NSString *sleepStrength = [prefs[@"lockStrength"] isKindOfClass:[NSString class]] ? prefs[@"lockStrength"] : @"saver";
    NSArray *low = [prefs[@"lowPowerApps"] isKindOfClass:[NSArray class]] ? prefs[@"lowPowerApps"] : @[];
    BOOL whitelist = prefs[@"whitelistEnabled"] ? [prefs[@"whitelistEnabled"] boolValue]
        : [prefs[@"powerMode"] isEqualToString:@"fullPower"]; // Preserve the old native-plus-app-list mode on upgrade.
    os_unfair_lock_lock(&stateLock);
    enabled = [prefs[@"enabled"] boolValue]; // Missing or malformed preferences fail closed.
    whitelistEnabled = whitelist;
    awakeStrength = [strength copy];
    lockStrength = [sleepStrength copy];
    lowPowerApps = [low copy];
    prefsRead = prefs != nil;
    os_unfair_lock_unlock(&stateLock);
    CTRefreshMode();
    CTReapply();
    CTWriteStatus();
    NSLog(@"[CTLowPower] settings loaded: enabled=%d whitelist=%d apps=%lu", enabled, whitelist, (unsigned long)low.count);
}

static void CTUpdateScreen(int token) {
    uint64_t state = 0;
    if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;
    os_unfair_lock_lock(&stateLock);
    BOOL changed = screenBlanked != (state != 0);
    screenBlanked = state != 0;
    os_unfair_lock_unlock(&stateLock);
    if (changed) { CTRefreshMode(); CTReapply(); CTWriteStatus(); }
}

static void CTTrack(id controller) {
    os_unfair_lock_lock(&stateLock);
    if (!controllers) controllers = [NSHashTable weakObjectsHashTable];
    [controllers addObject:controller];
    BOOL shouldLog = !sawController;
    sawController = YES;
    os_unfair_lock_unlock(&stateLock);
    if (shouldLog) { NSLog(@"[CTLowPower] MitigationController hook active"); CTWriteStatus(); }
}

// These hooks only tighten CPU budgets. Native thermal limits remain in force.
%hook MitigationController
- (id)initForFastLoop:(BOOL)fastLoop noDisplay:(BOOL)noDisplay powerSaveParams:(id)saveParams powerZoneParams:(id)zoneParams {
    id result = %orig;
    if (result) { CTTrack(result); CTApplyController(result); }
    return result;
}

- (void)updateCPU {
    CTTrack(self);
    CTApplyController(self);
    %orig;
    CTApplyController(self);
}

- (void)setCPMSMitigationsEnabled:(BOOL)value {
    %orig(CTActive() ? YES : value);
}

- (void)setCPUPowerZoneTarget:(int)target {
    if (!applyingBudget) {
        os_unfair_lock_lock(&stateLock);
        nativeZoneTarget = target;
        os_unfair_lock_unlock(&stateLock);
    }
    %orig(CTActive() ? MIN(target, CTCapPercent()) : target);
}

- (void)setCPUPowerCeiling:(int)ceiling fromDecisionSource:(uintptr_t)source {
    %orig(CTActive() ? MIN(ceiling, CTCapPercent()) : ceiling, source);
}

- (void)setCPUPowerCeiling:(int)ceiling forDVD1Contributor:(int)contributor {
    %orig(CTActive() ? MIN(ceiling, CTCapPercent()) : ceiling, contributor);
}
%end

%ctor {
    NSLog(@"[CTLowPower] loaded into %@", [NSProcessInfo processInfo].processName);
    dispatch_async(dispatch_get_main_queue(), ^{
        CTLoadSettings();
        int screenToken;
        if (notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &screenToken,
                dispatch_get_main_queue(), ^(int token) { CTUpdateScreen(token); }) == NOTIFY_STATUS_OK)
            CTUpdateScreen(screenToken);
        int foregroundToken;
        notify_register_dispatch(CTForegroundNotification, &foregroundToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            CTRefreshMode();
        });
        int settingsToken;
        notify_register_dispatch(CTSettingsNotification, &settingsToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            CTLoadSettings();
        });
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            if (CTActive()) CTReapply();
        }];
    });
}
