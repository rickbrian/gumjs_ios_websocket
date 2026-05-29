#include "GJWSEngine.h"
#include "LogHelper.h"
#include "GJWSWebSocket.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmodule-import-in-extern-c"
#include "frida-gumjs.h"
#pragma clang diagnostic pop

#import <Foundation/Foundation.h>
#include <thread>
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <atomic>

#pragma mark - Globals

static GumScriptBackend *g_backend = NULL;
static GCancellable *g_cancellable = NULL;
static GumScript *g_script = NULL;
static GMainContext *g_context = NULL;
static GMainLoop *g_loop = NULL;

// 自包含 WebSocket 通讯 (纯 BSD socket, 不依赖 NSURLSession/CFNetwork/SSL)
static GJWSWebSocket g_wsClient;
static std::thread *g_readerThread = NULL;
static std::atomic<bool> g_stop{false};

static std::unordered_map<std::string, std::vector<std::string>> g_scriptChunks;

static std::atomic<bool> g_started{false};

#pragma mark - Forward Declarations

static void gjws_ws_send(const char *text);
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
    gjws_ws_send(message);
}

#pragma mark - Safe Script Unload

static void gjws_unload_current_script(void) {
    if (g_script) {
        gum_script_unload_sync(g_script, g_cancellable);
        g_object_unref(g_script);
        g_script = NULL;
    }
}

#pragma mark - Script Operations

static void gjws_start_script_sync(const char *source) {
    GJWS_LOG("Loading script (sync)...");
    GError *error = NULL;

    gjws_unload_current_script();

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

    gjws_unload_current_script();

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

    if (!chunkId || !data || total <= 0 || index < 0 || index >= total)
        return "";

    std::string cid = [chunkId UTF8String];
    if (g_scriptChunks.find(cid) == g_scriptChunks.end()) {
        g_scriptChunks[cid].resize(total);
    }
    g_scriptChunks[cid][index] = [data UTF8String];

    bool allReceived = true;
    for (auto &c : g_scriptChunks[cid]) {
        if (c.empty()) { allReceived = false; break; }
    }

    if (allReceived) {
        std::string full;
        for (auto &c : g_scriptChunks[cid]) full += c;
        g_scriptChunks.erase(cid);
        GJWS_LOG("Big script reassembly complete (%zu bytes)", full.size());
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

        if (msg && msg[@"type"]) {
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
                if (g_loop) g_main_loop_quit(g_loop);
            }
        }
    }

    free(pm->json);
    free(pm);
    return G_SOURCE_REMOVE;
}

#pragma mark - WebSocket (self-contained BSD socket)

static void gjws_ws_send(const char *text) {
    if (!text) return;
    g_wsClient.sendText(text);   // _fd<0 时为安全空操作
}

// 独立读线程: 负责连接/握手/收帧/断线自动重连。
// 收到的文本消息通过 g_idle_add 投递回 GumJS 主循环线程处理。
static void gjws_ws_reader_thread(std::string uri) {
    std::string host, path;
    int port = 0;
    if (!GJWSWebSocket::parseURI(uri, host, port, path)) {
        GJWS_LOG("Invalid WebSocket URI: %{public}s", uri.c_str());
        GJWS_FLOG("reader: bad uri %s", uri.c_str());
        if (g_loop) g_main_loop_quit(g_loop);
        return;
    }

    GJWS_FLOG("reader thread started host=%s port=%d path=%s",
              host.c_str(), port, path.c_str());

    while (!g_stop.load()) {
        GJWS_LOG("WebSocket connecting to %{public}s:%d%{public}s ...",
                 host.c_str(), port, path.c_str());

        if (!g_wsClient.connectTo(host, port, path)) {
            GJWS_LOG("WebSocket connect failed, retry in 2s");
            for (int i = 0; i < 20 && !g_stop.load(); i++) usleep(100 * 1000);
            continue;
        }

        GJWS_LOG("WebSocket connected (fd=%d)", g_wsClient.fd());
        GJWS_FLOG("ws connected fd=%d", g_wsClient.fd());
        gjws_ws_send(
            "{\"type\":\"start\",\"message\":\"websocket client success\"}");

        for (;;) {
            std::string msg;
            int r = g_wsClient.recvMessage(msg);
            if (r < 0) break;                // 断开
            if (r != 1) continue;            // 非文本帧, 忽略

            _GJWSPendingMsg *pm =
                (_GJWSPendingMsg *)calloc(1, sizeof(_GJWSPendingMsg));
            pm->json = strdup(msg.c_str());
            g_idle_add(gjws_dispatch_ws_message, pm);
        }

        g_wsClient.closeSocket();
        GJWS_LOG("WebSocket disconnected");
        GJWS_FLOG("ws disconnected");

        if (g_stop.load()) break;
        for (int i = 0; i < 20 && !g_stop.load(); i++) usleep(100 * 1000);
    }

    GJWS_FLOG("reader thread exiting");
    if (g_loop) g_main_loop_quit(g_loop);
}

#pragma mark - Engine Lifecycle

static void gjws_run_loop(const char *uri) {
    GJWS_LOG("Engine starting (uri=%{public}s)", uri);
    GJWS_FLOG("run_loop begin uri=%s", uri ? uri : "(null)");

    GJWS_FLOG("before gum_init_embedded");
    gum_init_embedded();
    GJWS_FLOG("after gum_init_embedded");

    g_backend = gum_script_backend_obtain_qjs();
    GJWS_FLOG("after obtain_qjs backend=%p", (void *)g_backend);

    g_cancellable = g_cancellable_new();
    GJWS_FLOG("after cancellable_new");

    g_context = g_main_context_default();
    GJWS_FLOG("after main_context_default ctx=%p", (void *)g_context);

    g_loop = g_main_loop_new(g_context, FALSE);
    GJWS_FLOG("after main_loop_new loop=%p", (void *)g_loop);

    g_stop.store(false);
    g_readerThread = new std::thread(gjws_ws_reader_thread, std::string(uri));
    GJWS_FLOG("reader thread spawned");

    GJWS_LOG("WebSocket connecting...");
    GJWS_FLOG("before main_loop_run");

    g_main_context_push_thread_default(g_context);
    g_main_loop_run(g_loop);
    g_main_context_pop_thread_default(g_context);

    GJWS_FLOG("after main_loop_run (loop exited)");

    GJWS_LOG("Engine loop exited, cleaning up...");

    // 停止读线程并关闭 socket (closeSocket 会唤醒阻塞中的 recv)
    g_stop.store(true);
    g_wsClient.closeSocket();
    if (g_readerThread) {
        g_readerThread->join();
        delete g_readerThread;
        g_readerThread = NULL;
    }

    gjws_unload_current_script();

    g_scriptChunks.clear();

    if (g_cancellable) {
        g_cancellable_cancel(g_cancellable);
        g_object_unref(g_cancellable);
        g_cancellable = NULL;
    }

    if (g_loop) {
        g_main_loop_unref(g_loop);
        g_loop = NULL;
    }

    gum_deinit_embedded();
    g_started.store(false);

    GJWS_LOG("Cleanup complete");
}

void gjws_start(const char *uri) {
    GJWS_FLOG("gjws_start entered uri=%s", uri ? uri : "(null)");

    bool expected = false;
    if (!g_started.compare_exchange_strong(expected, true)) {
        GJWS_LOG("Engine already running, ignoring duplicate start");
        GJWS_FLOG("gjws_start: already running, ignore");
        return;
    }

    GJWS_LOG("gjws_start called");
    char *uri_copy = strdup(uri);
    GJWS_FLOG("gjws_start: spawning engine thread");
    std::thread t([uri_copy]() {
        GJWS_FLOG("engine thread started");
        gjws_run_loop(uri_copy);
        free(uri_copy);
    });
    t.detach();
    GJWS_FLOG("gjws_start: thread detached");
}

void gjws_cleanup(void) {
    GJWS_LOG("gjws_cleanup: requesting shutdown...");
    if (g_loop) {
        g_main_loop_quit(g_loop);
    }
}
