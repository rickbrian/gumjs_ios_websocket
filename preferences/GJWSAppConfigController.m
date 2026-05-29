#import "GJWSAppConfigController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

@implementation GJWSAppConfigController

- (NSArray *)specifiers {
    if (!_specifiers) {
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
        [uri setProperty:@"ws://192.168.1.100:14725/ws" forKey:@"placeholder"];
        [uri setProperty:@NO forKey:@"noAutoCorrect"];
        [specs addObject:uri];

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
