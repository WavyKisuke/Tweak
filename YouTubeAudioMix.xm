#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL YTIsTarget(void) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [bid isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTIsOtherAudioPlaying(void) {
    @try { return AVAudioSession.sharedInstance.isOtherAudioPlaying; }
    @catch (__unused NSException *e) { return NO; }
}

static AVAudioSessionCategoryOptions YTMix(AVAudioSessionCategoryOptions options) {
    if (!YTIsTarget() || !YTIsOtherAudioPlaying()) return options;
    return options | AVAudioSessionCategoryOptionMixWithOthers;
}

%hook AVAudioSession

- (BOOL)setCategory:(AVAudioSessionCategory)category
       withOptions:(AVAudioSessionCategoryOptions)options
             error:(NSError **)error {
    if (YTIsTarget() && YTIsOtherAudioPlaying() &&
        [category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
        category = AVAudioSessionCategoryAmbient;
    }
    return %orig(category, YTMix(options), error);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)error {
    if (YTIsTarget() && YTIsOtherAudioPlaying() &&
        [category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
        category = AVAudioSessionCategoryAmbient;
    }
    return %orig(category, mode, YTMix(options), error);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)error {
    if (YTIsTarget() && YTIsOtherAudioPlaying() &&
        [category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
        category = AVAudioSessionCategoryAmbient;
    }
    return %orig(category, mode, policy, YTMix(options), error);
}

- (BOOL)setActive:(BOOL)active
            error:(NSError **)error {
    return %orig(active, error);
}

- (BOOL)setActive:(BOOL)active
      withOptions:(AVAudioSessionSetActiveOptions)options
            error:(NSError **)error {
    return %orig(active, options, error);
}

%end

%ctor {
    if (!YTIsTarget()) return;
}
