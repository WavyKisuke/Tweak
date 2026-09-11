#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton;
static NSHashTable *gPlayers;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindow *TopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController && window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

static void ApplyMuteState(void) {
    if (!gTikTokMuted) return;
    for (AVPlayer *player in gPlayers.allObjects) {
        player.muted = YES;
        player.volume = 0.0;
    }
}

void TikTokPlusSetMuted(BOOL muted) {
    if (!IsTikTok()) return;
    gTikTokMuted = muted;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gMuteButton setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
    });
    ApplyMuteState();
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(muted)}];
}

@interface TTKPlusAudioTarget : NSObject
@end
@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender {
    TikTokPlusSetMuted(!gTikTokMuted);
}
@end

static TTKPlusAudioTarget *gAudioTarget;

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = TopWindow();
        if (!window) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];
        if (gMuteButton && gMuteButton.superview == window) {
            [window bringSubviewToFront:gMuteButton];
            return;
        }
        [gMuteButton removeFromSuperview];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(window.bounds.size.width - 102, 60, 88, 38);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        button.layer.cornerRadius = 10.0;
        [button setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        [button addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:button];
        gMuteButton = button;
    });
}

void TikTokPlusInstallMuteButton(void) {
    if (!IsTikTok()) return;
    InstallMuteButton();
}

%hook AVPlayer
- (void)play {
    if (IsTikTok() && gTikTokMuted) {
        self.muted = YES;
        self.volume = 0.0;
    }
    %orig;
    if (IsTikTok() && gTikTokMuted) {
        self.muted = YES;
        self.volume = 0.0;
    }
}
- (void)setMuted:(BOOL)muted {
    if (IsTikTok() && gTikTokMuted) muted = YES;
    %orig;
}
- (void)setVolume:(float)volume {
    if (IsTikTok() && gTikTokMuted) volume = 0.0;
    %orig;
}
%end

%ctor {
    if (!IsTikTok()) return;
    gPlayers = [NSHashTable weakObjectsHashTable];
    dispatch_async(dispatch_get_main_queue(), ^{
        InstallMuteButton();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            InstallMuteButton();
        }];
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        InstallMuteButton();
        if (gTikTokMuted) ApplyMuteState();
    });
    dispatch_resume(timer);
}
