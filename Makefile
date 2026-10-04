export TARGET := iphone:clang:16.5:17.0
export ARCHS := arm64 arm64e
export THEOS_PACKAGE_SCHEME := roothide
export DEB_ARCH := iphoneos-arm64e
include $(THEOS)/makefiles/common.mk
TWEAK_NAME := VPNTime
VPNTime_FILES := Tweak.xm
VPNTime_CFLAGS := -fobjc-arc
VPNTime_FRAMEWORKS := UIKit Foundation
VPNTime_LIBRARIES := substrate
include $(THEOS_MAKE_PATH)/tweak.mk
