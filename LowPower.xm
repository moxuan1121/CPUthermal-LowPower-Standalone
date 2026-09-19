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
static NSHashTable *ppmInstances;
static NSHashTable *products;
static BOOL clearPending;
static BOOL prefsRead;
static BOOL sawController;
static BOOL sawPPM;
static BOOL sawProduct;
static BOOL requestedLevel2;
static BOOL requestedBudget;

static void CTWriteStatus(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        os_unfair_lock_lock(&stateLock);
        NSString *report = [NSString stringWithFormat:
            @"version=0.5.3\nprocess=%@\nprefsPath=%@\nprefsRead=%d\nenabled=%d\nwhitelistEnabled=%d\neffectiveLow=%d\nmitigationHook=%d\nppmHook=%d\nproductHook=%d\nlevel2Requested=%d\nbudgetRequested=%d\n",
            [NSProcessInfo processInfo].processName, CTPrefsPath(), prefsRead, enabled,
            whitelistEnabled, effectiveLow, sawController, sawPPM, sawProduct, requestedLevel2, requestedBudget];
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

static void CTApplyKnownLevel(id object) {
    if (!CTActive() || ![object respondsToSelector:@selector(setCPULevel:)]) return;
    // CommonProduct may have no getter; the original tweak still sends level 2 to its setter.
    if ([object respondsToSelector:@selector(CPULevel)]) {
        int level = ((int (*)(id, SEL))objc_msgSend)(object, @selector(CPULevel));
        if (level < 0 || level >= 2) return;
    }
    ((void (*)(id, SEL, int))objc_msgSend)(object, @selector(setCPULevel:), 2);
    os_unfair_lock_lock(&stateLock);
    BOOL firstRequest = !requestedLevel2;
    requestedLevel2 = YES;
    os_unfair_lock_unlock(&stateLock);
    if (firstRequest) CTWriteStatus();
}

static void CTApplyController(id controller) {
    if (!CTActive()) return;
    if ([controller respondsToSelector:@selector(setCPMSMitigationsEnabled:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, @selector(setCPMSMitigationsEnabled:), YES);
    if ([controller respondsToSelector:@selector(setCPULowPowerTarget:)]) {
        ((void (*)(id, SEL, int))objc_msgSend)(controller, @selector(setCPULowPowerTarget:), CTCapMW());
        os_unfair_lock_lock(&stateLock);
        BOOL firstRequest = !requestedBudget;
        requestedBudget = YES;
        os_unfair_lock_unlock(&stateLock);
        if (firstRequest) CTWriteStatus();
    }
    if ([controller respondsToSelector:@selector(setCPUPowerZoneTarget:)])
        ((void (*)(id, SEL, int))objc_msgSend)(controller, @selector(setCPUPowerZoneTarget:), CTCapPercent());
    CTApplyKnownLevel(controller);
}

static void CTReapply(void) {
    NSArray *snapshot, *ppmSnapshot, *productSnapshot;
    os_unfair_lock_lock(&stateLock);
    snapshot = controllers.allObjects;
    ppmSnapshot = ppmInstances.allObjects;
    productSnapshot = products.allObjects;
    os_unfair_lock_unlock(&stateLock);
    for (id controller in snapshot) { CTApplyController(controller); CTCallUpdateCPU(controller); }
    for (id ppm in ppmSnapshot) { CTCallUpdateCPU(ppm); CTApplyKnownLevel(ppm); }
    for (id product in productSnapshot) CTApplyKnownLevel(product);
}

static void CTApplyDesiredMode(void) {
    BOOL desired = CTDesiredMode();
    BOOL changed;
    os_unfair_lock_lock(&stateLock);
    changed = effectiveLow != desired;
    effectiveLow = desired;
    os_unfair_lock_unlock(&stateLock);
    if (changed) { CTReapply(); CTWriteStatus(); }
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
    prefsRead = prefs != nil;
    os_unfair_lock_unlock(&stateLock);
    CTRefreshMode();
    CTReapply();
    CTWriteStatus();
    NSLog(@"[CTLowPower] settings loaded: enabled=%d whitelist=%d apps=%lu", enabled, whitelist, (unsigned long)low.count);
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

static void CTTrackPPM(id ppm) {
    os_unfair_lock_lock(&stateLock);
    if (!ppmInstances) ppmInstances = [NSHashTable weakObjectsHashTable];
    [ppmInstances addObject:ppm];
    BOOL shouldLog = !sawPPM;
    sawPPM = YES;
    os_unfair_lock_unlock(&stateLock);
    if (shouldLog) { NSLog(@"[CTLowPower] ApplePPMCPU hook active; level getter=%d", [ppm respondsToSelector:@selector(CPULevel)]); CTWriteStatus(); }
}

static void CTTrackProduct(id product) {
    os_unfair_lock_lock(&stateLock);
    if (!products) products = [NSHashTable weakObjectsHashTable];
    [products addObject:product];
    BOOL shouldLog = !sawProduct;
    sawProduct = YES;
    os_unfair_lock_unlock(&stateLock);
    if (shouldLog) { NSLog(@"[CTLowPower] CommonProduct hook active; level getter=%d", [product respondsToSelector:@selector(CPULevel)]); CTWriteStatus(); }
}

%hook CommonProduct
- (id)initProduct:(id)params {
    id result = %orig;
    if (result) { CTTrackProduct(result); CTApplyKnownLevel(result); }
    return result;
}

- (void)setCPMSMitigationsEnabled:(BOOL)value {
    %orig(CTActive() ? YES : value);
}

- (void)setCPULevel:(int)level {
    CTTrackProduct(self);
    %orig(CTActive() ? MAX(level, 2) : level);
}
%end

%hook ApplePPMCPU
- (id)init {
    id result = %orig;
    if (result) { CTTrackPPM(result); CTApplyKnownLevel(result); }
    return result;
}

- (void)updateCPU {
    CTTrackPPM(self);
    %orig;
    CTApplyKnownLevel(self);
}

- (void)setCPULevel:(int)level {
    CTTrackPPM(self);
    %orig(CTActive() ? MAX(level, 2) : level);
}
%end

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

- (void)setCPULowPowerTarget:(int)target {
    %orig(CTActive() ? MIN(target, CTCapMW()) : target);
}

- (void)setCPULevel:(int)level {
    CTTrack(self);
    %orig(CTActive() ? MAX(level, 2) : level);
}

- (void)setCPMSMitigationsEnabled:(BOOL)value {
    %orig(CTActive() ? YES : value);
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
