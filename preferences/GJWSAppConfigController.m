#import "GJWSAppConfigController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

static NSString *const kDefaultURI = @"ws://192.168.1.100:14725/ws";

@implementation GJWSAppConfigController

- (NSArray *)specifiers {
    if (!_specifiers) {
        [self ensureDefaultURI];

        NSMutableArray *specs = [NSMutableArray new];

        PSSpecifier *group1 =
            [PSSpecifier groupSpecifierWithName:@"App Configuration"];
        [specs addObject:group1];

        PSSpecifier *inject =
            [PSSpecifier preferenceSpecifierNamed:@"Enable Injection"
                                          target:self
                                             set:@selector(setPref:specifier:)
                                             get:@selector(readPref:)
                                          detail:nil
                                            cell:PSSwitchCell
                                            edit:nil];
        [inject setProperty:@"inject" forKey:@"prefKey"];
        [specs addObject:inject];

        PSSpecifier *uri =
            [PSSpecifier preferenceSpecifierNamed:@"WebSocket URI"
                                          target:self
                                             set:@selector(setPref:specifier:)
                                             get:@selector(readPref:)
                                          detail:nil
                                            cell:PSEditTextCell
                                            edit:nil];
        [uri setProperty:@"uri" forKey:@"prefKey"];
        [uri setProperty:kDefaultURI forKey:@"placeholder"];
        [uri setProperty:@NO forKey:@"noAutoCorrect"];
        [specs addObject:uri];

        PSSpecifier *uriHint = [PSSpecifier groupSpecifierWithName:@""];
        [uriHint setProperty:@"需填完整地址：ws://电脑IP:14725/ws\n端口 14725 和 /ws 固定，只改 IP 为电脑局域网地址"
                      forKey:@"footerText"];
        [specs addObject:uriHint];

        PSSpecifier *delay =
            [PSSpecifier preferenceSpecifierNamed:@"Delay (ms)"
                                          target:self
                                             set:@selector(setPref:specifier:)
                                             get:@selector(readPref:)
                                          detail:nil
                                            cell:PSEditTextCell
                                            edit:nil];
        [delay setProperty:@"delay" forKey:@"prefKey"];
        [delay setProperty:@"0" forKey:@"placeholder"];
        [delay setProperty:@1 forKey:@"isNumeric"];
        [specs addObject:delay];

        _specifiers = specs;
    }
    return _specifiers;
}

#pragma mark - Config I/O

- (NSMutableDictionary *)loadConfig {
    NSDictionary *d =
        [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    return d ? [d mutableCopy] : [@{ @"apps" : @{} } mutableCopy];
}

- (void)saveConfig:(NSDictionary *)config {
    [config writeToFile:kConfigPath atomically:YES];
}

- (NSDictionary *)appConfig {
    return [self loadConfig][@"apps"][self.applicationID] ?: @{};
}

- (void)ensureDefaultURI {
    if (!self.applicationID) return;

    NSDictionary *appConf = [self appConfig];
    NSString *existing = appConf[@"uri"];
    if (existing && existing.length > 0) return;

    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps =
        [config[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *appConfM =
        [apps[self.applicationID] mutableCopy] ?: [NSMutableDictionary new];

    appConfM[@"uri"] = kDefaultURI;
    apps[self.applicationID] = appConfM;
    config[@"apps"] = apps;
    [self saveConfig:config];
}

#pragma mark - Read / Write

- (id)readPref:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"prefKey"];
    id value = [self appConfig][key];

    if ([key isEqualToString:@"delay"] &&
        [value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return value;
}

- (void)setPref:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"prefKey"];
    if (!key || !self.applicationID) return;

    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps =
        [config[@"apps"] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *appConf =
        [apps[self.applicationID] mutableCopy] ?: [NSMutableDictionary new];

    if ([key isEqualToString:@"delay"]) {
        appConf[key] = @([value intValue]);
    } else {
        appConf[key] = value;
    }

    apps[self.applicationID] = appConf;
    config[@"apps"] = apps;
    [self saveConfig:config];
}

@end
