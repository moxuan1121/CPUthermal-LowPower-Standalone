#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <os/lock.h>
#import <roothide.h>
#import "Shared.h"

// Independent preference domain; never reads or writes the original tweak's settings.
static NSString *CTPrefsPath(void) {
    return jbroot(@"/var/mobile/Library/Preferences/com.huayuarc.cputhermal.lowpower.plist");
}
static os_unfair_lock stateLock = OS_UNFAIR_LOCK_INIT;
static BOOL enabled;
static BOOL whitelistEnabled;
static BOOL effectiveLow;
static int capMW = 2500;
static int capPercent = 45;
static NSArray<NSString *> *lowPowerApps;
static NSHashTable *controllers;
static BOOL clearPending;

static BOOL CTActive(void) {
    os_unfair_lock_lock(&stateLock);
    BOOL active = enabled && effectiveLow;
    os_unfair_lock_unlock(&stateLock);
    return active;
}

static int CTCapMW(void) {
    os_unfair_lock_lock(&stateLock);
    int result = capMW;
    os_unfair_lock_unlock(&stateLock);
    return result;
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
    NSArray *whitelist = lowPowerApps;
    os_unfair_lock_unlock(&stateLock);
    return !selected || CTContainsHash(whitelist, CTForegroundHash());
}

static void CTCallUpdateCPU(id controller) {
    if ([controller respondsToSelector:@selector(updateCPU)])
        ((void (*)(id, SEL))objc_msgSend)(controller, @selector(updateCPU));
}

static void CTReapply(void) {
    NSArray *snapshot;
    os_unfair_lock_lock(&stateLock);
    snapshot = controllers.allObjects;
    os_unfair_lock_unlock(&stateLock);
    for (id controller in snapshot) CTCallUpdateCPU(controller);
}

static void CTApplyDesiredMode(void) {
    BOOL desired = CTDesiredMode();
    BOOL changed;
    os_unfair_lock_lock(&stateLock);
    changed = effectiveLow != desired;
    effectiveLow = desired;
    os_unfair_lock_unlock(&stateLock);
    if (changed) CTReapply();
}

static void CTRefreshMode(void) {
    // Foreground state briefly becomes zero during app transitions.
    if (CTForegroundHash() == 0 && !clearPending) {
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
    NSString *strength = [prefs[@"lowPowerStrength"] isKindOfClass:[NSString class]] ? prefs[@"lowPowerStrength"] : @"standard";
    NSArray *low = [prefs[@"lowPowerApps"] isKindOfClass:[NSArray class]] ? prefs[@"lowPowerApps"] : @[];
    BOOL whitelist = prefs[@"whitelistEnabled"] ? [prefs[@"whitelistEnabled"] boolValue]
        : [prefs[@"powerMode"] isEqualToString:@"fullPower"]; // Preserve the old native-plus-app-list mode on upgrade.
    int power = [strength isEqualToString:@"saver"] ? 2000 : [strength isEqualToString:@"performance"] ? 3000 : 2500;
    int percent = [strength isEqualToString:@"saver"] ? 35 : [strength isEqualToString:@"performance"] ? 55 : 45;
    os_unfair_lock_lock(&stateLock);
    enabled = [prefs[@"enabled"] boolValue]; // Missing or malformed preferences fail closed.
    whitelistEnabled = whitelist;
    capMW = power;
    capPercent = percent;
    lowPowerApps = [low copy];
    os_unfair_lock_unlock(&stateLock);
    CTRefreshMode();
    CTReapply();
    NSLog(@"[CTLowPower] settings loaded: enabled=%d whitelist=%d apps=%lu", enabled, whitelist, (unsigned long)low.count);
}

static void CTTrack(id controller) {
    static BOOL loggedController;
    os_unfair_lock_lock(&stateLock);
    if (!controllers) controllers = [NSHashTable weakObjectsHashTable];
    [controllers addObject:controller];
    BOOL shouldLog = !loggedController;
    loggedController = YES;
    os_unfair_lock_unlock(&stateLock);
    if (shouldLog) NSLog(@"[CTLowPower] MitigationController hook active");
}

// These hooks only tighten CPU budgets. Native thermal limits remain in force.
%hook MitigationController
- (id)initForFastLoop:(BOOL)fastLoop noDisplay:(BOOL)noDisplay powerSaveParams:(id)saveParams powerZoneParams:(id)zoneParams {
    id result = %orig;
    if (result) CTTrack(result);
    return result;
}

- (void)updateCPU {
    CTTrack(self);
    %orig;
    if (!CTActive()) return;
    if ([(id)self respondsToSelector:@selector(setCPMSMitigationsEnabled:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setCPMSMitigationsEnabled:), YES);
}

- (void)setCPULowPowerTarget:(int)target {
    %orig(CTActive() ? MIN(target, CTCapMW()) : target);
}

- (void)setCPULevel:(int)level {
    %orig(CTActive() ? MAX(level, 2) : level);
}

- (void)setMaxCPUPowerTarget:(int)target useLegacyPath:(BOOL)legacy setProperty:(uintptr_t)property {
    %orig(CTActive() ? MIN(target, CTCapMW()) : target, legacy, property);
}

- (void)setCPUPowerZoneTarget:(int)target {
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
    });
}
