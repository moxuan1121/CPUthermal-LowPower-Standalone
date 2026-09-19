#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "CTSettingsPrefs.h"

@interface CTLowPowerRootListController : PSListController
@end

@implementation CTLowPowerRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:CTS("Root") target:self];
    return _specifiers ?: [NSArray array];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:CTS("key")];
    if (!key) return nil;
    NSDictionary *prefs = CTSettingsReadPrefs();
    id value = prefs[key];
    if (value) return value;
    if ([key isEqualToString:CTS("whitelistEnabled")])
        return [NSNumber numberWithBool:[prefs[CTS("powerMode")] isEqualToString:CTS("fullPower")]];
    if ([key isEqualToString:CTS("lowPowerStrength")]) return CTS("standard");
    return [NSNumber numberWithBool:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:CTS("key")];
    if (!key || !value) return;
    NSMutableDictionary *prefs = CTSettingsReadPrefs();
    prefs[key] = value;
    if (!CTSettingsWritePrefs(prefs)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:CTS("保存失败")
            message:CTS("无法写入隐根配置，请检查 RootHide 环境。")
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:CTS("确定") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
