#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

extern void TikTokPlusInstallMuteButton(void);

static BOOL gFeedMuted = YES;
static float gFeedVolume = 0.0f;

%hook IESVideoPlayer
- (void)setVolume:(float)volume {
    %orig(gFeedMuted ? 0.0f : (volume * gFeedVolume));
}
%end

%ctor {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    if (!bundleID.length) return;
    if (![bundleID containsString:@"tiktok"] && ![bundleID containsString:@"musically"]) return;

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusToggleMute" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        gFeedMuted = [n.object boolValue];
        if (!gFeedVolume && !gFeedMuted) gFeedVolume = 1.0f;
        TikTokPlusInstallMuteButton();
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        NSNumber *muted = n.userInfo[@"muted"];
        NSNumber *volume = n.userInfo[@"volume"];
        if (volume) gFeedVolume = MAX(0.0f, MIN(1.0f, volume.floatValue));
        if (muted) gFeedMuted = muted.boolValue;
    }];

    dispatch_async(dispatch_get_main_queue(), ^{ TikTokPlusInstallMuteButton(); });
}
