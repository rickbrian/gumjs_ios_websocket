#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "Sources/LogHelper.h"

static NSString *const kGJWSConfigPath =
    @"/var/mobile/Library/Preferences/com.gjws.config.plist";

typedef void (*gjws_start_func)(const char *uri);

static NSString *const kEnginePath =
    @"/var/jb/usr/lib/libGJWSEngine.dylib";

%ctor {
    @autoreleasepool {
        GJWS_FLOG("ctor enter");

        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleId) { GJWS_FLOG("no bundleId, abort"); return; }
        GJWS_FLOG("bundleId=%s", [bundleId UTF8String]);

        NSDictionary *config =
            [NSDictionary dictionaryWithContentsOfFile:kGJWSConfigPath];
        if (!config) { GJWS_FLOG("no config, abort"); return; }

        NSDictionary *apps = config[@"apps"];
        if (!apps) { GJWS_FLOG("no apps, abort"); return; }

        NSDictionary *appConfig = apps[bundleId];
        if (!appConfig) { GJWS_FLOG("app not in config, abort"); return; }

        if (![appConfig[@"inject"] boolValue]) {
            GJWS_FLOG("inject=NO, abort");
            return;
        }

        NSString *uri = appConfig[@"uri"];
        if (!uri || uri.length == 0) { GJWS_FLOG("empty uri, abort"); return; }
        GJWS_FLOG("matched, uri=%s", [uri UTF8String]);

        GJWS_LOG("Target app matched: %{public}@, loading engine...", bundleId);

        const char *enginePath = [kEnginePath fileSystemRepresentation];
        GJWS_FLOG("engine path=%s exists=%d", enginePath,
                  [[NSFileManager defaultManager] fileExistsAtPath:kEnginePath]);

        GJWS_FLOG("before dlopen (RTLD_LAZY)");
        void *handle = dlopen(enginePath, RTLD_LAZY | RTLD_LOCAL);
        GJWS_FLOG("after dlopen handle=%p", handle);
        if (!handle) {
            const char *err = dlerror();
            GJWS_FLOG("dlopen failed: %s", err ? err : "(null)");
            GJWS_LOG("Failed to load engine: %{public}s", err);
            return;
        }

        GJWS_FLOG("before dlsym gjws_start");
        gjws_start_func start = (gjws_start_func)dlsym(handle, "gjws_start");
        GJWS_FLOG("after dlsym start=%p", start);
        if (!start) {
            const char *err = dlerror();
            GJWS_FLOG("dlsym failed: %s", err ? err : "(null)");
            GJWS_LOG("Failed to find gjws_start: %{public}s", err);
            return;
        }

        int delay = [appConfig[@"delay"] intValue];
        NSString *uriCopy = [uri copy];

        GJWS_FLOG("scheduling start, delay=%d", delay);
        GJWS_LOG("Injecting into %{public}@ (uri=%{public}@, delay=%d)",
                 bundleId, uri, delay);

        if (delay > 0) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(delay * NSEC_PER_MSEC)),
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    GJWS_FLOG("calling start() [delayed]");
                    start([uriCopy UTF8String]);
                });
        } else {
            dispatch_async(
                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{
                    GJWS_FLOG("calling start() [async]");
                    start([uriCopy UTF8String]);
                });
        }
        GJWS_FLOG("ctor done");
    }
}
