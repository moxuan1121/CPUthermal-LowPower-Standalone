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
