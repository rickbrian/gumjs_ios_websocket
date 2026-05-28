#import "GJWSAppConfigController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

@implementation GJWSAppConfigController

- (NSArray *)specifiers {
    if (!_specifiers) {
        self.bundleId = [self.specifier propertyForKey:@"bundleId"];
        self.title = self.bundleId;

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
        [uri setProperty:@"ws://192.168.1.100:14725/ws"
                  forKey:@"placeholder"];
        [uri setProperty:@NO forKey:@"noAutoCorrect"];
        [specs addObject:uri];

        PSSpecifier *uriHint =
            [PSSpecifier groupSpecifierWithName:@""];
        [uriHint setProperty:@"格式: ws://{电脑IP}:14725/ws\n例如: ws://192.168.1.100:14725/ws"
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

        // --- Danger Zone ---
        PSSpecifier *group2 = [PSSpecifier groupSpecifierWithName:@""];
        [specs addObject:group2];

        PSSpecifier *del =
            [PSSpecifier preferenceSpecifierNamed:@"Delete This App"
                                          target:self
                                             set:nil
                                             get:nil
                                          detail:nil
                                            cell:PSButtonCell
                                            edit:nil];
        del->action = @selector(confirmDelete);
        [del setProperty:@YES forKey:@"isDestructive"];
        [specs addObject:del];

        _specifiers = specs;
    }
    return _specifiers;
}

#pragma mark - Config I/O

- (NSMutableDictionary *)loadConfig {
    NSDictionary *d =
        [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    return d ? [d mutableCopy]
             : [@{ @"enabled" : @NO, @"apps" : @{} } mutableCopy];
}

- (void)saveConfig:(NSDictionary *)config {
    [config writeToFile:kConfigPath atomically:YES];
}

- (NSDictionary *)appConfig {
    return [self loadConfig][@"apps"][self.bundleId] ?: @{};
}

#pragma mark - Read / Write

- (id)readPref:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"prefKey"];
    id value = [self appConfig][key];

    if ([key isEqualToString:@"delay"] && [value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return value;
}

- (void)setPref:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"prefKey"];

    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps = [config[@"apps"] mutableCopy];
    NSMutableDictionary *appConf = [apps[self.bundleId] mutableCopy];

    if ([key isEqualToString:@"delay"]) {
        appConf[key] = @([value intValue]);
    } else {
        appConf[key] = value;
    }

    apps[self.bundleId] = appConf;
    config[@"apps"] = apps;
    [self saveConfig:config];
}

#pragma mark - Delete

- (void)confirmDelete {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Confirm"
                         message:[NSString stringWithFormat:
                                               @"Remove configuration for %@?",
                                               self.bundleId]
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Delete"
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *action) {
                                     [weakSelf deleteApp];
                                 }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteApp {
    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps = [config[@"apps"] mutableCopy];
    [apps removeObjectForKey:self.bundleId];
    config[@"apps"] = apps;
    [self saveConfig:config];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
