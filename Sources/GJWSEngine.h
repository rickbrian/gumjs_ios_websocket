#ifndef GJWS_ENGINE_H
#define GJWS_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((visibility("default")))
void gjws_start(const char *uri);

__attribute__((visibility("default")))
void gjws_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif
