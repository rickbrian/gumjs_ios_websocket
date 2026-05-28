#include "GJWSEngine.h"
#include "LogHelper.h"
#include "frida-gumjs.h"

#import <Foundation/Foundation.h>
#include <thread>
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>

#pragma mark - Globals

static GumScriptBackend *g_backend = NULL;
static GCancellable *g_cancellable = NULL;
static GumScript *g_script = NULL;
static GMainContext *g_context = NULL;
static GMainLoop *g_loop = NULL;

static NSURLSession *g_wsSession = nil;
static NSURLSessionWebSocketTask *g_wsTask = nil;

static std::unordered_map<std::string, std::vector<std::string>> g_scriptChunks;

#pragma mark - Forward Declarations

@interface _GJWSWebSocketDelegate : NSObject <NSURLSessionWebSocketDelegate>
@end

static void gjws_ws_send(NSString *text);
static void gjws_ws_receive_next(void);
static void gjws_on_script_message(const gchar *message, GBytes *data, gpointer user_data);
static void gjws_start_script_sync(const char *source);
static void gjws_create_script_async(const char *source);
static std::string gjws_process_big_script(NSDictionary *msg);

#pragma mark - Stalker Exclusion

static void gjws_exclude_own_range(void) {
    if (!g_script) return;

    GumAddress addr = (GumAddress)((guintptr)gum_strip_code_pointer(
        (void *)gjws_exclude_own_range));

    struct Ctx { GumAddress addr; };
    auto ctx = std::make_unique<Ctx>();
    ctx->addr = addr;

    gum_process_enumerate_modules(
        [](GumModule *module, gpointer user_data) -> gboolean {
            auto *c = static_cast<Ctx *>(user_data);
            const GumMemoryRange *range = gum_module_get_range(module);
            if (c->addr >= range->base_address &&
                c->addr < range->base_address + range->size) {
                gum_stalker_exclude(gum_script_get_stalker(g_script), range);
                return FALSE;
            }
            return TRUE;
        },
        ctx.get());
}

#pragma mark - Script Message Handler

static void gjws_on_script_message(const gchar *message, GBytes *data,
                                   gpointer user_data) {
    if (!message) return;
    gjws_ws_send([NSString stringWithUTF8String:message]);
}

#pragma mark - Script Operations

static void gjws_start_script_sync(const char *source) {
    GJWS_LOG("Loading script (sync)...");
    GError *error = NULL;

    if (g_script) {
        gum_script_unload_sync(g_script, g_cancellable);
        g_object_unref(g_script);
        g_script = NULL;
    }

    g_script = gum_script_backend_create_sync(
        g_backend, "base_script", source, NULL, g_cancellable, &error);

    if (error) {
        GJWS_LOG("Script creation failed: %{public}s", error->message);
        g_error_free(error);
        return;
    }

    gjws_exclude_own_range();
    gum_script_set_message_handler(g_script, gjws_on_script_message, NULL, NULL);
    gum_script_load_sync(g_script, g_cancellable);
    GJWS_LOG("Script loaded successfully");
}

static void gjws_on_script_created_cb(GObject *source, GAsyncResult *res,
                                      gpointer user_data) {
    GError *error = NULL;

    if (g_script) {
        g_object_unref(g_script);
        g_script = NULL;
    }

    g_script = gum_script_backend_create_finish(
        GUM_SCRIPT_BACKEND(source), res, &error);
    if (error) {
        GJWS_LOG("Async script creation failed: %{public}s", error->message);
        g_error_free(error);
        return;
    }

    gjws_exclude_own_range();
    gum_script_set_message_handler(g_script, gjws_on_script_message, NULL, NULL);
    gum_script_load_sync(g_script, g_cancellable);
    GJWS_LOG("Script reloaded (async path)");
}

static void gjws_create_script_async(const char *source) {
    GJWS_LOG("Creating script (async)...");
    gum_script_backend_create(g_backend, "base_script", source, NULL,
                              g_cancellable, gjws_on_script_created_cb, NULL);
}

#pragma mark - Big Script Chunking

static std::string gjws_process_big_script(NSDictionary *msg) {
    NSString *chunkId = msg[@"chunk_id"];
    int total = [msg[@"chunk_total"] intValue];
    int index = [msg[@"chunk_index"] intValue];
    NSString *data = msg[@"chunk_data"];

    if (!chunkId || !data || index < 0 || index >= total) return "";

    std::string cid = [chunkId UTF8String];
    if (g_scriptChunks.find(cid) == g_scriptChunks.end()) {
        g_scriptChunks[cid].resize(total);
    }
    g_scriptChunks[cid][index] = [data UTF8String];

    if (index + 1 == total) {
        std::string full;
        for (auto &c : g_scriptChunks[cid]) full += c;
        g_scriptChunks.erase(cid);
        GJWS_LOG("Big script reassembly complete");
        return full;
    }
    return "";
}

#pragma mark - GLib Idle Dispatch (WebSocket → GumJS thread)

typedef struct {
    char *json;
} _GJWSPendingMsg;

static gboolean gjws_dispatch_ws_message(gpointer data) {
    _GJWSPendingMsg *pm = (_GJWSPendingMsg *)data;

    @autoreleasepool {
        NSData *d = [NSData dataWithBytesNoCopy:pm->json
                                         length:strlen(pm->json)
                                   freeWhenDone:NO];
        NSDictionary *msg =
            [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if (!msg || !msg[@"type"]) goto done;

        NSString *type = msg[@"type"];

        if ([type isEqualToString:@"start"] ||
            [type isEqualToString:@"script"]) {
            BOOL isStart = [type isEqualToString:@"start"];
            if ([msg[@"big_script"] boolValue]) {
                std::string src = gjws_process_big_script(msg);
                if (!src.empty()) {
                    if (isStart)
                        gjws_start_script_sync(src.c_str());
                    else
                        gjws_create_script_async(src.c_str());
                }
            } else {
                NSString *src = msg[@"script"];
                if (src) {
                    if (isStart)
                        gjws_start_script_sync([src UTF8String]);
                    else
                        gjws_create_script_async([src UTF8String]);
                }
            }
        } else if ([type isEqualToString:@"post"]) {
            NSString *s = msg[@"script"];
            if (s && g_script)
                gum_script_post(g_script, [s UTF8String], NULL);
        } else if ([type isEqualToString:@"end"]) {
            gjws_cleanup();
        }
    }

done:
    free(pm->json);
    free(pm);
    return G_SOURCE_REMOVE;
}

#pragma mark - WebSocket

static void gjws_ws_send(NSString *text) {
    if (!g_wsTask) return;
    NSURLSessionWebSocketMessage *m =
        [[NSURLSessionWebSocketMessage alloc] initWithString:text];
    [g_wsTask sendMessage:m
        completionHandler:^(NSError *err) {
            if (err)
                GJWS_LOG("WS send error: %{public}@", err.localizedDescription);
        }];
}

static void gjws_ws_receive_next(void) {
    if (!g_wsTask) return;
    [g_wsTask
        receiveMessageWithCompletionHandler:^(
            NSURLSessionWebSocketMessage *message, NSError *error) {
            if (error) {
                GJWS_LOG("WS receive error: %{public}@",
                         error.localizedDescription);
                if (g_loop) g_main_loop_quit(g_loop);
                return;
            }

            if (message.type == NSURLSessionWebSocketMessageTypeString &&
                message.string) {
                const char *cstr = [message.string UTF8String];
                _GJWSPendingMsg *pm =
                    (_GJWSPendingMsg *)calloc(1, sizeof(_GJWSPendingMsg));
                pm->json = strdup(cstr);
                g_idle_add(gjws_dispatch_ws_message, pm);
            }

            gjws_ws_receive_next();
        }];
}

#pragma mark - WebSocket Delegate

static _GJWSWebSocketDelegate *g_wsDelegate = nil;

@implementation _GJWSWebSocketDelegate

- (void)URLSession:(NSURLSession *)session
          webSocketTask:(NSURLSessionWebSocketTask *)task
    didOpenWithProtocol:(NSString *)protocol {
    GJWS_LOG("WebSocket connected");
    gjws_ws_send(
        @"{\"type\":\"start\",\"message\":\"websocket client success\"}");
    gjws_ws_receive_next();
}

- (void)URLSession:(NSURLSession *)session
          webSocketTask:(NSURLSessionWebSocketTask *)task
     didCloseWithCode:(NSURLSessionWebSocketCloseCode)code
                reason:(NSData *)reason {
    GJWS_LOG("WebSocket closed (code=%ld)", (long)code);
    if (g_loop) g_main_loop_quit(g_loop);
}

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    if (error) {
        GJWS_LOG("WS connection failed: %{public}@",
                 error.localizedDescription);
        if (g_loop) g_main_loop_quit(g_loop);
    }
}

@end

#pragma mark - Engine Lifecycle

static void gjws_run_loop(const char *uri) {
    GJWS_LOG("Engine starting (uri=%{public}s)", uri);

    gum_init_embedded();
    g_backend = gum_script_backend_obtain_qjs();
    g_cancellable = g_cancellable_new();

    g_context = g_main_context_default();
    g_loop = g_main_loop_new(g_context, FALSE);

    @autoreleasepool {
        g_wsDelegate = [_GJWSWebSocketDelegate new];
        NSURLSessionConfiguration *cfg =
            [NSURLSessionConfiguration defaultSessionConfiguration];
        g_wsSession = [NSURLSession sessionWithConfiguration:cfg
                                                    delegate:g_wsDelegate
                                               delegateQueue:nil];

        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:uri]];
        g_wsTask = [g_wsSession webSocketTaskWithURL:url];
        [g_wsTask resume];
    }

    GJWS_LOG("WebSocket connecting...");

    g_main_context_push_thread_default(g_context);
    g_main_loop_run(g_loop);
    g_main_context_pop_thread_default(g_context);

    GJWS_LOG("Engine loop exited");
}

void gjws_start(const char *uri) {
    GJWS_LOG("gjws_start called");
    char *uri_copy = strdup(uri);
    std::thread t([uri_copy]() {
        gjws_run_loop(uri_copy);
        free(uri_copy);
    });
    t.detach();
}

void gjws_cleanup(void) {
    GJWS_LOG("Cleaning up...");

    if (g_loop) {
        g_main_loop_quit(g_loop);
        g_main_loop_unref(g_loop);
        g_loop = NULL;
    }

    if (g_script) {
        gum_script_unload_sync(g_script, g_cancellable);
        g_object_unref(g_script);
        g_script = NULL;
    }

    if (g_cancellable) {
        g_cancellable_cancel(g_cancellable);
        g_object_unref(g_cancellable);
        g_cancellable = NULL;
    }

    gum_deinit_embedded();

    @autoreleasepool {
        [g_wsTask cancel];
        g_wsTask = nil;
        [g_wsSession invalidateAndCancel];
        g_wsSession = nil;
        g_wsDelegate = nil;
    }

    GJWS_LOG("Cleanup complete");
}
