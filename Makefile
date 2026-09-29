ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokPlus
TikTokPlus_FILES = Tweak.xm AudioHooks.xm PrivateAudioHooks.xm TikTokFeedAudioHooks.xm
TikTokPlus_CFLAGS = -fobjc-arc
TikTokPlus_FRAMEWORKS = UIKit AVFoundation
TikTokPlus_LOGOS_DEFAULT_GENERATOR = internal

TWEAK_NAME += YouTubeAudioMix
YouTubeAudioMix_FILES = YouTubeAudioMix.xm
YouTubeAudioMix_CFLAGS = -fobjc-arc
YouTubeAudioMix_FRAMEWORKS = Foundation AVFoundation
YouTubeAudioMix_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk
