ARCHS = arm64
TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless

export THEOS_PACKAGE_SCHEME

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GumJSWebSocket

GumJSWebSocket_FILES = Tweak.xm
GumJSWebSocket_CFLAGS = -fobjc-arc
GumJSWebSocket_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

LIBRARY_NAME = libGJWSEngine

libGJWSEngine_FILES = Sources/GJWSEngine.mm
libGJWSEngine_CFLAGS = -fobjc-arc -fno-modules -fno-cxx-modules -Wno-module-import-in-extern-c -Ilib -fvisibility=hidden
libGJWSEngine_CCFLAGS = -std=c++17 -fno-modules -fno-cxx-modules -Wno-module-import-in-extern-c -fvisibility=hidden -fvisibility-inlines-hidden
libGJWSEngine_LDFLAGS = lib/libfrida-gumjs.a -lresolv -Wl,-exported_symbols_list,Sources/engine_exports.txt
libGJWSEngine_FRAMEWORKS = Foundation Security
libGJWSEngine_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
