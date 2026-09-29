#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static BOOL YTIsTarget(void) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [bid isEqualToString:@"com.google.ios.youtube"] ||
           [bid hasPrefix:@"com.google.ios.youtube"];
}

/*
 * Do not depend on isOtherAudioPlaying here.
 * YouTube can configure its session before iOS reports that another
 * application is currently playing. The MixWithOthers option is safe
 * to request on the playback categories we care about and is the key
 * part of allowing existing audio to continue.
 */
static AVAudioSessionCategoryOptions YTForceMix(AVAudioSessionCategoryOptions options) {
    if (!YTIsTarget()) return options;

    options |= AVAudioSessionCategoryOptionMixWithOthers;
    options &= ~AVAudioSessionCategoryOptionDuckOthers;
    return options;
}

%hook AVAudioSession

- (BOOL)setCategory:(AVAudioSessionCategory)category
       withOptions:(AVAudioSessionCategoryOptions)options
             error:(NSError **)error {
    if (YTIsTarget()) {
        options = YTForceMix(options);

        // SoloAmbient cannot mix with other application audio.
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
    }

    return %orig(category, options, error);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)error {
    if (YTIsTarget()) {
        options = YTForceMix(options);

        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
    }

    return %orig(category, mode, options, error);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
 routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)error {
    if (YTIsTarget()) {
        options = YTForceMix(options);

        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
            category = AVAudioSessionCategoryAmbient;
        }
    }

    return %orig(category, mode, policy, options, error);
}

%end

%ctor {
    if (!YTIsTarget()) return;
}
