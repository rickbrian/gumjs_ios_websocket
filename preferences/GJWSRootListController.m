#import "GJWSRootListController.h"
#import "GJWSAppConfigController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

@implementation GJWSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        [self reloadSpecifiers];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    NSMutableArray *specs = [NSMutableArray new];
    NSDictionary *config = [self loadConfig];

    // --- Master Switch ---
    PSSpecifier *group1 =
        [PSSpecifier groupSpecifierWithName:@"General"];
    [specs addObject:group1];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"Enabled"
                                                         target:self
                                                            set:@selector(setEnabled:specifier:)
                                                            get:@selector(readEnabled:)
                                                         detail:nil
                                                           cell:PSSwitchCell
                                                           edit:nil];
    [enabled setProperty:@"enabled" forKey:@"key"];
    [specs addObject:enabled];

    // --- Configured Apps ---
    NSDictionary *apps = config[@"apps"];
    if (apps.count > 0) {
        PSSpecifier *group2 =
            [PSSpecifier groupSpecifierWithName:@"Configured Apps"];
        [group2 setProperty:@"Swipe left to delete"
                     forKey:@"footerText"];
        [specs addObject:group2];

        NSArray *sortedKeys =
            [[apps allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *bundleId in sortedKeys) {
            NSDictionary *appConf = apps[bundleId];
            NSString *subtitle = appConf[@"uri"] ?: @"";

            PSSpecifier *app =
                [PSSpecifier preferenceSpecifierNamed:bundleId
                                              target:self
                                                 set:nil
                                                 get:nil
                                              detail:[GJWSAppConfigController class]
                                                cell:PSLinkCell
                                                edit:nil];
            [app setProperty:bundleId forKey:@"bundleId"];
            [app setProperty:subtitle forKey:@"sublabel"];
            [app setProperty:@YES forKey:@"enabled"];
            [specs addObject:app];
        }
    }

    // --- Add / Remove ---
    PSSpecifier *group3 = [PSSpecifier groupSpecifierWithName:@""];
    [specs addObject:group3];

    PSSpecifier *addBtn =
        [PSSpecifier preferenceSpecifierNamed:@"Add App"
                                      target:self
                                         set:nil
                                         get:nil
                                      detail:nil
                                        cell:PSButtonCell
                                        edit:nil];
    addBtn->action = @selector(addApp);
    [specs addObject:addBtn];

    _specifiers = specs;
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

#pragma mark - Master Switch

- (id)readEnabled:(PSSpecifier *)specifier {
    return [self loadConfig][@"enabled"] ?: @NO;
}

- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *config = [self loadConfig];
    config[@"enabled"] = value;
    [self saveConfig:config];
}

#pragma mark - Add App

- (void)addApp {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Add App"
                         message:@"Enter the target app's Bundle ID"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"com.example.app";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.keyboardType = UIKeyboardTypeURL;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Add"
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *action) {
                                     NSString *bid =
                                         alert.textFields.firstObject.text;
                                     if (bid.length > 0) {
                                         [weakSelf addAppWithBundleId:bid];
                                     }
                                 }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addAppWithBundleId:(NSString *)bundleId {
    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps =
        [config[@"apps"] mutableCopy] ?: [NSMutableDictionary new];

    if (apps[bundleId]) {
        UIAlertController *dup = [UIAlertController
            alertControllerWithTitle:@"Duplicate"
                             message:[NSString
                                         stringWithFormat:
                                             @"%@ is already configured",
                                             bundleId]
                      preferredStyle:UIAlertControllerStyleAlert];
        [dup addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
        [self presentViewController:dup animated:YES completion:nil];
        return;
    }

    apps[bundleId] = @{
        @"inject" : @YES,
        @"uri" : @"ws://192.168.1.100:14725/ws",
        @"delay" : @0,
    };
    config[@"apps"] = apps;
    [self saveConfig:config];
    [self reloadSpecifiers];
    [self.table reloadData];
}

#pragma mark - Delete support

- (BOOL)canBeShownFromSuspendedState {
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if ([spec propertyForKey:@"bundleId"]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;

    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    NSString *bundleId = [spec propertyForKey:@"bundleId"];
    if (!bundleId) return;

    NSMutableDictionary *config = [self loadConfig];
    NSMutableDictionary *apps = [config[@"apps"] mutableCopy];
    [apps removeObjectForKey:bundleId];
    config[@"apps"] = apps;
    [self saveConfig:config];
    [self reloadSpecifiers];
    [self.table reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
    [self.table reloadData];
}

@end
