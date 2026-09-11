#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable<AVPlayer *> *gTrackedPlayers = nil;
static NSHashTable<AVAudioPlayer *> *gTrackedAudioPlayers = nil;
static NSHashTable<AVAudioEngine *> *gTrackedEngines = nil;
static dispatch_source_t gMuteTimer = nil;

static BOOL IsTikTokAudio(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

// Decide the audio session config that TikTok must end up with so it mixes
// with the user's music / podcasts instead of interrupting them.
static void ResolveAudioMixConfig(AVAudioSessionCategory inCat,
                                  AVAudioSessionCategoryOptions inOpts,
                                  AVAudioSessionCategory *outCat,
                                  AVAudioSessionCategoryOptions *outOpts) {
    AVAudioSessionCategory targetCat = inCat;
    AVAudioSessionCategoryOptions targetOpts = inOpts | AVAudioSessionCategoryOptionMixWithOthers;

    // Preserve PlayAndRecord / MultiRoute (TikTok needs them for recording and
    // route-mixing features). For everything else — Ambient, SoloAmbient,
    // Record, Playback, nil — force Playback so iOS treats TikTok as
    // background-friendly and mixes it with the other app.
    if (![targetCat isEqualToString:AVAudioSessionCategoryPlayAndRecord] &&
        ![targetCat isEqualToString:AVAudioSessionCategoryMultiRoute]) {
        targetCat = AVAudioSessionCategoryPlayback;
    }

    if (outCat)  *outCat  = targetCat;
    if (outOpts) *outOpts = targetOpts;
}

static void ConfigureAudioMixing(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    AVAudioSessionCategory currentCat = s.category;
    AVAudioSessionCategoryOptions currentOpts = s.categoryOptions;

    AVAudioSessionCategory targetCat;
    AVAudioSessionCategoryOptions targetOpts;
    ResolveAudioMixConfig(currentCat, currentOpts, &targetCat, &targetOpts);

    if (![currentCat isEqualToString:targetCat] || currentOpts != targetOpts) {
        NSError *err = nil;
        [s setCategory:targetCat mode:s.mode options:targetOpts error:&err];

        // Re-activate so it re-evaluates interruptibility — otherwise the first
        // activation under the old config keeps the music app paused.
        if (s.otherAudioPlaying) {
            NSError *deactErr = nil;
            [s setActive:NO
             withOptions:AVAudioSessionSetActivationOptionNotifyOthersOnDeactivation
                   error:&deactErr];
            NSError *actErr = nil;
            [s setActive:YES withOptions:0 error:&actErr];
        }
    }
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

static void TrackPlayer(AVPlayer *player) {
    if (!player || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) { [gTrackedPlayers addObject:player]; }
}

static void TrackAudioPlayer(AVAudioPlayer *player) {
    if (!player || !gTrackedAudioPlayers) return;
    @synchronized (gTrackedAudioPlayers) { [gTrackedAudioPlayers addObject:player]; }
}

static void TrackEngine(AVAudioEngine *engine) {
    if (!engine || !gTrackedEngines) return;
    @synchronized (gTrackedEngines) { [gTrackedEngines addObject:engine]; }
}

static void ApplyMuteState(void) {
    if (gTrackedPlayers) {
        @synchronized (gTrackedPlayers) {
            for (AVPlayer *player in gTrackedPlayers.allObjects) {
                if (![player isKindOfClass:[AVPlayer class]]) continue;
                player.muted = gTikTokMuted;
                [player setVolume:gTikTokMuted ? 0.0f : 1.0f];
            }
        }
    }

    if (gTrackedAudioPlayers) {
        @synchronized (gTrackedAudioPlayers) {
            for (AVAudioPlayer *player in gTrackedAudioPlayers.allObjects) {
                if (![player isKindOfClass:[AVAudioPlayer class]]) continue;
                player.volume = gTikTokMuted ? 0.0f : 1.0f;
            }
        }
    }

    if (gTrackedEngines) {
        @synchronized (gTrackedEngines) {
            for (AVAudioEngine *engine in gTrackedEngines.allObjects) {
                if (![engine isKindOfClass:[AVAudioEngine class]]) continue;
                engine.mainMixerNode.outputVolume = gTikTokMuted ? 0.0f : 1.0f;
            }
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

%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError {
    AVAudioPlayer *player = %orig(url, outError);
    if (IsTikTokAudio()) TrackAudioPlayer(player);
    return player;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)outError {
    AVAudioPlayer *player = %orig(data, outError);
    if (IsTikTokAudio()) TrackAudioPlayer(player);
    return player;
}

- (void)setVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackAudioPlayer(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}

- (BOOL)play {
    if (IsTikTokAudio() && gTikTokMuted) self.volume = 0.0f;
    BOOL result = %orig;
    if (IsTikTokAudio() && gTikTokMuted) self.volume = 0.0f;
    return result;
}
%end

%hook AVAudioEngine
- (instancetype)init {
    AVAudioEngine *engine = %orig;
    if (IsTikTokAudio()) TrackEngine(engine);
    return engine;
}

- (BOOL)startAndReturnError:(NSError **)outError {
    if (IsTikTokAudio()) TrackEngine(self);
    BOOL result = %orig(outError);
    if (IsTikTokAudio() && gTikTokMuted) self.mainMixerNode.outputVolume = 0.0f;
    return result;
}
%end

%hook AVAudioSession
- (BOOL)setCategory:(AVAudioSessionCategory)category
               mode:(AVAudioSessionMode)mode
            options:(AVAudioSessionCategoryOptions)options
              error:(NSError **)outError {
    if (IsTikTokAudio()) {
        ResolveAudioMixConfig(category, options, &category, &options);
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
       withOptions:(AVAudioSessionCategoryOptions)options
             error:(NSError **)outError {
    if (IsTikTokAudio()) {
        ResolveAudioMixConfig(category, options, &category, &options);
    }
    return %orig(category, options, outError);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category
              error:(NSError **)outError {
    if (IsTikTokAudio()) {
        // This overload can't carry options — upgrade by calling the
        // option-taking overload. ResolveAudioMixConfig is idempotent so the
        // recursive call doesn't loop.
        NSError *innerErr = nil;
        BOOL ok = [self setCategory:AVAudioSessionCategoryPlayback
                               mode:AVAudioSessionModeDefault
                            options:AVAudioSessionCategoryOptionMixWithOthers
                              error:&innerErr];
        if (outError) *outError = innerErr;
        return ok;
    }
    return %orig(category, outError);
}

- (BOOL)setActive:(BOOL)active
      withOptions:(AVAudioSessionSetActivationOptions)options
            error:(NSError **)outError {
    if (IsTikTokAudio() && !active) {
        // Be polite when TikTok stops using the audio device — let the music
        // app resume cleanly instead of leaving it paused.
        options |= AVAudioSessionSetActivationOptionNotifyOthersOnDeactivation;
    }
    return %orig(active, options, outError);
}
%end

%ctor {
    if (!IsTikTokAudio()) return;

    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedAudioPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedEngines = [NSHashTable weakObjectsHashTable];

    // Apply MixWithOthers immediately so we beat TikTok's first audio-session
    // activation; otherwise iOS sees the wrong config and pauses the music app.
    ConfigureAudioMixing();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMuteButton();
    });

    gMuteTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gMuteTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              750 * NSEC_PER_MSEC,
                              100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gMuteTimer, ^{
        ConfigureAudioMixing();
        InstallMuteButton();
        if (gTikTokMuted) ApplyMuteState();
    });
    dispatch_resume(gMuteTimer);
}
