ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CTLowPower CTLowPowerForeground

CTLowPower_FILES = LowPower.xm
CTLowPower_CFLAGS = -fobjc-arc
CTLowPower_FRAMEWORKS = Foundation
CTLowPower_LDFLAGS = -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide

CTLowPowerForeground_FILES = Foreground.xm
CTLowPowerForeground_CFLAGS = -fobjc-arc
CTLowPowerForeground_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = CTLowPowerSettings
CTLowPowerSettings_FILES = Settings/CTLowPowerRootListController.m Settings/CTLowPowerAppListController.m
CTLowPowerSettings_INSTALL_PATH = /Library/PreferenceBundles
CTLowPowerSettings_CFLAGS = -fobjc-arc -ISettings
CTLowPowerSettings_CODESIGN_FLAGS = -SSettings/Settings.entitlements
CTLowPowerSettings_FRAMEWORKS = Foundation UIKit
CTLowPowerSettings_PRIVATE_FRAMEWORKS = Preferences
CTLowPowerSettings_LDFLAGS = -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide
include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	$(ECHO_NOTHING)cp Settings/Info.plist Settings/Root.plist Settings/icon.png Settings/icon@2x.png Settings/icon@3x.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CTLowPowerSettings.bundle/"$(ECHO_END)
