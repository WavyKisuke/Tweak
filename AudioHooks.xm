#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable<AVPlayer *> *gTrackedPlayers = nil;
static dispatch_source_t gMuteTimer = nil;

static BOOL IsTikTokAudio(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *AudioTopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal && w.rootViewController) {
                    if (w.isKeyWindow) return w;
                    if (!gMuteButton || !gMuteButton.superview) return w;
                }
            }
        }
    }
    return nil;
}

// Tracking must never change the player's volume itself.  Doing that from
// setVolume:/setMuted: would re-enter our hooks recursively.
static void TrackPlayer(AVPlayer *player) {
    if (!player || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) {
        [gTrackedPlayers addObject:player];
    }
}

static void ApplyMuteState(void) {
    if (!gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) {
        for (AVPlayer *player in gTrackedPlayers.allObjects) {
            if (![player isKindOfClass:[AVPlayer class]]) continue;
            player.muted = gTikTokMuted;
            [player setVolume:(gTikTokMuted ? 0.0f : 1.0f)];
        }
    }
}

@interface TTKPlusAudioTarget : NSObject
@end

@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    [gMuteButton setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
    ApplyMuteState();
}
@end

static TTKPlusAudioTarget *gAudioTarget = nil;

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AudioTopWindow();
        if (!w) return;
        if (gMuteButton && gMuteButton.superview) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];

        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(w.bounds.size.width - 102, 60, 88, 38);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        b.layer.cornerRadius = 10;
        b.layer.masksToBounds = YES;
        [b setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        b.accessibilityIdentifier = @"TikTokPlusMuteButton";
        [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
        [w addSubview:b];
        gMuteButton = b;
    });
}

%hook AVPlayer
- (instancetype)init {
    AVPlayer *player = %orig;
    if (IsTikTokAudio()) TrackPlayer(player);
    return player;
}

- (instancetype)initWithURL:(NSURL *)URL {
    AVPlayer *player = %orig;
    if (IsTikTokAudio()) TrackPlayer(player);
    return player;
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    AVPlayer *player = %orig;
    if (IsTikTokAudio()) TrackPlayer(player);
    return player;
}

- (void)setVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackPlayer(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}

- (void)setMuted:(BOOL)muted {
    if (IsTikTokAudio()) {
        TrackPlayer(self);
        if (gTikTokMuted) muted = YES;
    }
    %orig(muted);
}

- (void)play {
    if (IsTikTokAudio() && gTikTokMuted) {
        self.muted = YES;
        self.volume = 0.0f;
    }
    %orig;
    if (IsTikTokAudio() && gTikTokMuted) {
        self.muted = YES;
        self.volume = 0.0f;
    }
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    if (IsTikTokAudio()) TrackPlayer(self);
    %orig(item);
    if (IsTikTokAudio() && gTikTokMuted) {
        self.muted = YES;
        self.volume = 0.0f;
    }
}
%end

%ctor {
    if (!IsTikTokAudio()) return;

    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMuteButton();
    });

    gMuteTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gMuteTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              750 * NSEC_PER_MSEC,
                              100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gMuteTimer, ^{
        InstallMuteButton();
        if (gTikTokMuted) ApplyMuteState();
    });
    dispatch_resume(gMuteTimer);
}
