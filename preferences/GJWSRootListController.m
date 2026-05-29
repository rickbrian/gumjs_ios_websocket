#import "GJWSRootListController.h"
#import "GJWSAppConfigController.h"
#import <AltList/ATLApplicationSection.h>

static NSString *const kConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

@implementation GJWSRootListController

- (void)_loadSectionsFromSpecifier {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:
        @"NOT (atl_bundleIdentifier BEGINSWITH 'com.apple') AND atl_isHidden == NO"];
    _applicationSections = @[
        [[ATLApplicationSection alloc]
            initCustomSectionWithPredicate:predicate
                               sectionName:@"Applications"]
    ];
}

- (void)prepareForPopulatingSections {
    [super prepareForPopulatingSections];
    self.subcontrollerClass = [GJWSAppConfigController class];
}

- (BOOL)shouldShowSubtitles {
    return YES;
}

- (NSString *)subtitleForApplicationWithIdentifier:(NSString *)applicationID {
    return applicationID;
}

- (NSString *)previewStringForApplicationWithIdentifier:(NSString *)applicationID {
    NSDictionary *config =
        [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    NSDictionary *appConf = config[@"apps"][applicationID];
    if (appConf && [appConf[@"inject"] boolValue]) {
        return @"ON";
    }
    return nil;
}

@end
