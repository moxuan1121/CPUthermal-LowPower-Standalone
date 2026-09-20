#import <Foundation/Foundation.h>
#import <notify.h>
#import <roothide.h>

// RootHide's remapped Settings process can fault on static Objective-C string literals.
#define CTS(s) [NSString stringWithUTF8String:(s)]

static inline NSString *CTSettingsPrefsPath(void) {
    return jbroot(CTS("/var/mobile/Library/Preferences/com.mox1121.cpulowpower.plist"));
}

static inline NSMutableDictionary *CTSettingsReadPrefs(void) {
    NSString *path = CTSettingsPrefsPath();
    if (!path.length) return [NSMutableDictionary dictionary];
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!prefs) {
        NSString *legacyPath = jbroot(CTS("/var/mobile/Library/Preferences/com.huayuarc.cputhermal.lowpower.plist"));
        if (legacyPath.length) prefs = [NSMutableDictionary dictionaryWithContentsOfFile:legacyPath];
    }
    return prefs ?: [NSMutableDictionary dictionary];
}

static inline BOOL CTSettingsWritePrefs(NSDictionary *prefs) {
    NSString *path = CTSettingsPrefsPath();
    if (!path.length) return NO;
    NSString *directory = path.stringByDeletingLastPathComponent;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:&error]) return NO;
    if (![prefs writeToFile:path atomically:YES]) return NO;
    notify_post("com.mox1121.cpulowpower/settingsChanged");
    return YES;
}
