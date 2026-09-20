ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CPULowPower CPULowPowerForeground

CPULowPower_FILES = LowPower.xm
CPULowPower_CFLAGS = -fobjc-arc
CPULowPower_FRAMEWORKS = Foundation
CPULowPower_LDFLAGS = -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide

CPULowPowerForeground_FILES = Foreground.xm
CPULowPowerForeground_CFLAGS = -fobjc-arc
CPULowPowerForeground_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = CPULowPowerSettings
CPULowPowerSettings_FILES = Settings/CTLowPowerRootListController.m Settings/CTLowPowerAppListController.m
CPULowPowerSettings_INSTALL_PATH = /Library/PreferenceBundles
CPULowPowerSettings_CFLAGS = -fobjc-arc -ISettings
CPULowPowerSettings_CODESIGN_FLAGS = -SSettings/Settings.entitlements
CPULowPowerSettings_FRAMEWORKS = Foundation UIKit
CPULowPowerSettings_PRIVATE_FRAMEWORKS = Preferences
CPULowPowerSettings_LDFLAGS = -L$(THEOS_VENDOR_LIBRARY_PATH)/iphone/roothide -lroothide
include $(THEOS_MAKE_PATH)/bundle.mk

after-stage::
	$(ECHO_NOTHING)cp Settings/Info.plist Settings/Root.plist Settings/icon.png Settings/icon@2x.png Settings/icon@3x.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CPULowPowerSettings.bundle/"$(ECHO_END)
