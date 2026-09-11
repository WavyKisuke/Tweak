ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokAudioMix
TikTokAudioMix_FILES = Tweak.xm
TikTokAudioMix_CFLAGS = -fobjc-arc
TikTokAudioMix_FRAMEWORKS = UIKit AVFoundation
TikTokAudioMix_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk
