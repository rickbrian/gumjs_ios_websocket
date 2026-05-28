#ifndef GJWS_ENGINE_H
#define GJWS_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

void gjws_start(const char *uri);
void gjws_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif
