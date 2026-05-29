#ifndef GJWS_LOG_HELPER_H
#define GJWS_LOG_HELPER_H

#include <os/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>
#include <unistd.h>

#define GJWS_LOG_TAG "GumJSWS"
#define GJWS_LOG_FILE "/var/tmp/gjws.log"

// 同时写 os_log（实时）和文件（保证每条落盘，崩溃也不丢）
#define GJWS_LOG(fmt, ...) \
    os_log(OS_LOG_DEFAULT, "[%{public}s] " fmt, GJWS_LOG_TAG, ##__VA_ARGS__)

// 纯 C 风格文件日志：每条立即 flush + fsync，定位崩溃点用
__attribute__((unused))
static void gjws_flog(const char *fmt, ...) {
    FILE *f = fopen(GJWS_LOG_FILE, "a");
    const char *used = GJWS_LOG_FILE;
    char altpath[1024] = {0};
    if (!f) {
        const char *tmp = getenv("TMPDIR");
        if (tmp) {
            snprintf(altpath, sizeof(altpath), "%sgjws.log", tmp);
            f = fopen(altpath, "a");
            used = altpath;
        }
    }
    if (!f) {
        os_log(OS_LOG_DEFAULT, "[%{public}s] FLOG fopen failed", GJWS_LOG_TAG);
        return;
    }

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    time_t t = ts.tv_sec;
    struct tm tmv;
    localtime_r(&t, &tmv);
    char tbuf[32];
    strftime(tbuf, sizeof(tbuf), "%H:%M:%S", &tmv);

    fprintf(f, "[%s.%03ld][pid=%d] ", tbuf, ts.tv_nsec / 1000000, getpid());

    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);

    fprintf(f, "\n");
    fflush(f);
    fsync(fileno(f));
    fclose(f);

    static int announced = 0;
    if (!announced) {
        announced = 1;
        os_log(OS_LOG_DEFAULT, "[%{public}s] file log -> %{public}s",
               GJWS_LOG_TAG, used);
    }
}

#define GJWS_FLOG(fmt, ...) gjws_flog(fmt, ##__VA_ARGS__)

#endif
