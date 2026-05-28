#import <Foundation/Foundation.h>
#import "Sources/GJWSEngine.h"
#import "Sources/LogHelper.h"

static NSString *const kGJWSConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

%ctor {
    @autoreleasepool {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleId) return;

        NSDictionary *config =
            [NSDictionary dictionaryWithContentsOfFile:kGJWSConfigPath];
        if (!config) return;

        if (![config[@"enabled"] boolValue]) return;

        NSDictionary *apps = config[@"apps"];
        if (!apps) return;

        NSDictionary *appConfig = apps[bundleId];
        if (!appConfig) return;

        if (appConfig[@"inject"] && ![appConfig[@"inject"] boolValue]) return;

        NSString *uri = appConfig[@"uri"];
        if (!uri || uri.length == 0) return;

        int delay = [appConfig[@"delay"] intValue];

        GJWS_LOG("Injecting into %{public}@ (uri=%{public}@, delay=%d)",
                 bundleId, uri, delay);

        if (delay > 0) {
            NSString *uriCopy = [uri copy];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(delay * NSEC_PER_MSEC)),
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    gjws_start([uriCopy UTF8String]);
                });
        } else {
            dispatch_async(
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    gjws_start([uri UTF8String]);
                });
        }
    }
}
