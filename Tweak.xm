#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "Sources/LogHelper.h"

static NSString *const kGJWSConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

typedef void (*gjws_start_func)(const char *uri);

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

        GJWS_LOG("Target app matched: %{public}@, loading engine...", bundleId);

        void *handle = dlopen("/var/jb/usr/lib/libGJWSEngine.dylib", RTLD_NOW);
        if (!handle) {
            GJWS_LOG("Failed to load engine: %{public}s", dlerror());
            return;
        }

        gjws_start_func start = (gjws_start_func)dlsym(handle, "gjws_start");
        if (!start) {
            GJWS_LOG("Failed to find gjws_start: %{public}s", dlerror());
            return;
        }

        int delay = [appConfig[@"delay"] intValue];
        NSString *uriCopy = [uri copy];

        GJWS_LOG("Injecting into %{public}@ (uri=%{public}@, delay=%d)",
                 bundleId, uri, delay);

        if (delay > 0) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(delay * NSEC_PER_MSEC)),
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    start([uriCopy UTF8String]);
                });
        } else {
            dispatch_async(
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    start([uriCopy UTF8String]);
                });
        }
    }
}
