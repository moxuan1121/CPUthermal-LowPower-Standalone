#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <os/lock.h>
#import "Shared.h"

// Independent preference domain; never reads or writes the original tweak's settings.
static NSString *const CTPrefsPath = @"/var/mobile/Library/Preferences/com.huayuarc.cputhermal.lowpower.plist";
static os_unfair_lock stateLock = OS_UNFAIR_LOCK_INIT;
static BOOL enabled;
static BOOL baseLow;
static BOOL effectiveLow;
static int capMW = 2500;
static int capPercent = 45;
static NSArray<NSString *> *fullPowerApps;
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

static BOOL CTScreenBlanked(void) {
    int token;
    uint64_t value = 0;
    if (notify_register_check("com.apple.springboard.hasBlankedScreen", &token) != NOTIFY_STATUS_OK) return NO;
    int status = notify_get_state(token, &value);
    notify_cancel(token);
    return status == NOTIFY_STATUS_OK && value != 0;
}

static BOOL CTDesiredMode(void) {
    os_unfair_lock_lock(&stateLock);
    BOOL selected = baseLow;
    NSArray *fullExceptions = fullPowerApps;
    NSArray *lowExceptions = lowPowerApps;
    os_unfair_lock_unlock(&stateLock);
    if (CTScreenBlanked()) return YES;
    uint64_t foreground = CTForegroundHash();
    if (selected && CTContainsHash(fullExceptions, foreground)) return NO;
    if (!selected && CTContainsHash(lowExceptions, foreground)) return YES;
    return selected;
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
    if (!CTScreenBlanked() && CTForegroundHash() == 0 && !clearPending) {
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
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:CTPrefsPath];
    NSString *mode = [prefs[@"powerMode"] isKindOfClass:[NSString class]] ? prefs[@"powerMode"] : @"fullPower";
    NSString *strength = [prefs[@"lowPowerStrength"] isKindOfClass:[NSString class]] ? prefs[@"lowPowerStrength"] : @"standard";
    NSArray *full = [prefs[@"fullPowerApps"] isKindOfClass:[NSArray class]] ? prefs[@"fullPowerApps"] : @[];
    NSArray *low = [prefs[@"lowPowerApps"] isKindOfClass:[NSArray class]] ? prefs[@"lowPowerApps"] : @[];
    int power = [strength isEqualToString:@"saver"] ? 2000 : [strength isEqualToString:@"performance"] ? 3000 : 2500;
    int percent = [strength isEqualToString:@"saver"] ? 35 : [strength isEqualToString:@"performance"] ? 55 : 45;
    os_unfair_lock_lock(&stateLock);
    enabled = [prefs[@"enabled"] boolValue]; // Missing or malformed preferences fail closed.
    baseLow = [mode isEqualToString:@"lowPower"];
    capMW = power;
    capPercent = percent;
    fullPowerApps = [full copy];
    lowPowerApps = [low copy];
    os_unfair_lock_unlock(&stateLock);
    CTRefreshMode();
    CTReapply();
}

static void CTTrack(id controller) {
    os_unfair_lock_lock(&stateLock);
    if (!controllers) controllers = [NSHashTable weakObjectsHashTable];
    [controllers addObject:controller];
    os_unfair_lock_unlock(&stateLock);
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
    if ([self respondsToSelector:@selector(setCPMSMitigationsEnabled:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setCPMSMitigationsEnabled:), YES);
}

- (void)setCPULowPowerTarget:(int)target {
    %orig(CTActive() ? MIN(target, CTCapMW()) : target);
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
    dispatch_async(dispatch_get_main_queue(), ^{
        CTLoadSettings();
        int foregroundToken;
        notify_register_dispatch(CTForegroundNotification, &foregroundToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            CTRefreshMode();
        });
        int screenToken;
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &screenToken, dispatch_get_main_queue(), ^(int token) {
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
