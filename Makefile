ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = thermalmonitord SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CTLowPower CTLowPowerForeground

CTLowPower_FILES = LowPower.xm
CTLowPower_CFLAGS = -fobjc-arc
CTLowPower_FRAMEWORKS = Foundation

CTLowPowerForeground_FILES = Foreground.xm
CTLowPowerForeground_CFLAGS = -fobjc-arc
CTLowPowerForeground_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
