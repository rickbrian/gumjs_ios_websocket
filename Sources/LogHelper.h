#ifndef GJWS_LOG_HELPER_H
#define GJWS_LOG_HELPER_H

#include <os/log.h>

#define GJWS_LOG_TAG "GumJSWS"

#define GJWS_LOG(fmt, ...) \
    os_log(OS_LOG_DEFAULT, "[%{public}s] " fmt, GJWS_LOG_TAG, ##__VA_ARGS__)

#endif
