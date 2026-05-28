ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GumJSWebSocket

GumJSWebSocket_FILES = Tweak.xm Sources/GJWSEngine.mm
GumJSWebSocket_CFLAGS = -fobjc-arc -fno-modules -Ilib
GumJSWebSocket_CCFLAGS = -std=c++17
GumJSWebSocket_LDFLAGS = lib/libfrida-gumjs.a -lresolv
GumJSWebSocket_FRAMEWORKS = Foundation Security

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
