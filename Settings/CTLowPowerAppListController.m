#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "CTSettingsPrefs.h"

@interface PSSpecifier (CTAppList)
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get
                                   detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface CTLowPowerAppListController : PSListController
@end

@implementation CTLowPowerAppListController

- (NSString *)listKey { return CTS("lowPowerApps"); }

- (NSString *)stringFrom:(id)object selector:(const char *)name {
    SEL selector = sel_registerName(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

- (NSArray<NSDictionary *> *)installedApps {
    @try {
    Class cls = objc_getClass("LSApplicationWorkspace");
    id workspace = nil;
    SEL shared = sel_registerName("defaultWorkspace");
    if (cls && [cls respondsToSelector:shared])
        workspace = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    SEL all = sel_registerName("allApplications");
    id result = workspace && [workspace respondsToSelector:all]
        ? ((id (*)(id, SEL))objc_msgSend)(workspace, all) : nil;
    NSArray *proxies = [result isKindOfClass:[NSArray class]] ? result : nil;
    NSMutableDictionary *apps = [NSMutableDictionary dictionary];
    for (id proxy in proxies) {
        NSString *identifier = [self stringFrom:proxy selector:"applicationIdentifier"]
            ?: [self stringFrom:proxy selector:"bundleIdentifier"];
        NSString *name = [self stringFrom:proxy selector:"localizedName"]
            ?: [self stringFrom:proxy selector:"itemName"];
        if (identifier.length) apps[identifier] = @{CTS("id"): identifier, CTS("name"): name ?: identifier};
    }
    return [apps.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[CTS("name")] localizedCaseInsensitiveCompare:b[CTS("name")]];
    }];
    } @catch (NSException *exception) {
        (void)exception;
        return [NSArray array];
    }
}

- (NSMutableSet<NSString *> *)selectedApps {
    id value = CTSettingsReadPrefs()[self.listKey];
    return [NSMutableSet setWithArray:[value isKindOfClass:[NSArray class]] ? value : [NSArray array]];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    NSArray *apps = [self installedApps];
    PSSpecifier *group = [PSSpecifier preferenceSpecifierNamed:nil target:nil set:NULL get:NULL detail:nil cell:0 edit:nil];
    [group setProperty:apps.count ? CTS("勾选要加入此名单的应用。") : CTS("无法列出应用，请确认 RootHide 已允许设置读取应用列表。")
                  forKey:CTS("footerText")];
    [items addObject:group];
    for (NSDictionary *app in apps) {
        NSString *identifier = app[CTS("id")];
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:app[CTS("name")] target:self
            set:@selector(setAppEnabled:specifier:) get:@selector(appEnabled:) detail:nil cell:6 edit:nil];
        [item setProperty:identifier forKey:CTS("bundleIdentifier")];
        [items addObject:item];
    }
    _specifiers = items;
    return _specifiers;
}

- (id)appEnabled:(PSSpecifier *)specifier {
    return [NSNumber numberWithBool:[[self selectedApps] containsObject:[specifier propertyForKey:CTS("bundleIdentifier")]]];
}

- (void)setAppEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:CTS("bundleIdentifier")];
    if (!identifier.length) return;
    NSMutableSet *selected = [self selectedApps];
    if ([value boolValue]) [selected addObject:identifier]; else [selected removeObject:identifier];
    NSMutableDictionary *prefs = CTSettingsReadPrefs();
    prefs[self.listKey] = [selected.allObjects sortedArrayUsingSelector:@selector(compare:)];
    CTSettingsWritePrefs(prefs);
}

@end

@interface CTFullPowerAppListController : CTLowPowerAppListController
@end

@implementation CTFullPowerAppListController
- (NSString *)listKey { return CTS("fullPowerApps"); }
@end
