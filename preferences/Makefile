TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

THEOS_PACKAGE_SCHEME = rootless

BUNDLE_NAME = GJWSPreferences

GJWSPreferences_FILES = GJWSRootListController.m GJWSAppConfigController.m
GJWSPreferences_INSTALL_PATH = /Library/PreferenceBundles
GJWSPreferences_FRAMEWORKS = UIKit
GJWSPreferences_CFLAGS = -fobjc-arc
GJWSPreferences_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/GJWSPreferences.plist$(ECHO_END)
