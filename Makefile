ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokPlus
TikTokPlus_FILES = Tweak.xm AudioHooks.xm PrivateAudioHooks.xm TikTokFeedAudioHooks.xm
TikTokPlus_CFLAGS = -fobjc-arc
TikTokPlus_FRAMEWORKS = UIKit AVFoundation
TikTokPlus_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

# Rebuild trigger: use the current fixed AudioHooks source on main.
