#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable<AVPlayer *> *gTrackedPlayers = nil;
static NSHashTable<AVAudioPlayer *> *gTrackedAudioPlayers = nil;
static NSHashTable<AVAudioEngine *> *gTrackedEngines = nil;
static NSHashTable<AVAudioPlayerNode *> *gTrackedPlayerNodes = nil;
static NSHashTable<AVAudioMixerNode *> *gTrackedMixerNodes = nil;
static NSHashTable<AVAudioEnvironmentNode *> *gTrackedEnvironmentNodes = nil;
static NSHashTable<AVSampleBufferAudioRenderer *> *gTrackedSampleRenderers = nil;
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

static void TrackPlayerNode(AVAudioPlayerNode *node) {
    if (!node || !gTrackedPlayerNodes) return;
    @synchronized (gTrackedPlayerNodes) { [gTrackedPlayerNodes addObject:node]; }
}

static void TrackMixerNode(AVAudioMixerNode *node) {
    if (!node || !gTrackedMixerNodes) return;
    @synchronized (gTrackedMixerNodes) { [gTrackedMixerNodes addObject:node]; }
}

static void TrackEnvironmentNode(AVAudioEnvironmentNode *node) {
    if (!node || !gTrackedEnvironmentNodes) return;
    @synchronized (gTrackedEnvironmentNodes) { [gTrackedEnvironmentNodes addObject:node]; }
}

static void TrackSampleRenderer(AVSampleBufferAudioRenderer *renderer) {
    if (!renderer || !gTrackedSampleRenderers) return;
    @synchronized (gTrackedSampleRenderers) { [gTrackedSampleRenderers addObject:renderer]; }
}

static void ApplyMuteState(void) {
    if (gTrackedPlayers) {
        @synchronized (gTrackedPlayers) {
            for (AVPlayer *player in gTrackedPlayers.allObjects) {
                if (![player isKindOfClass:[AVPlayer class]]) continue;
                player.muted = gTikTokMuted;
                if (gTikTokMuted) player.volume = 0.0f;
            }
        }
    }

    if (gTrackedAudioPlayers) {
        @synchronized (gTrackedAudioPlayers) {
            for (AVAudioPlayer *player in gTrackedAudioPlayers.allObjects) {
                if (![player isKindOfClass:[AVAudioPlayer class]]) continue;
                if (gTikTokMuted) player.volume = 0.0f;
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

    if (gTrackedPlayerNodes) {
        @synchronized (gTrackedPlayerNodes) {
            for (AVAudioPlayerNode *node in gTrackedPlayerNodes.allObjects) {
                if (![node isKindOfClass:[AVAudioPlayerNode class]]) continue;
                node.volume = gTikTokMuted ? 0.0f : 1.0f;
            }
        }
    }

    if (gTrackedMixerNodes) {
        @synchronized (gTrackedMixerNodes) {
            for (AVAudioMixerNode *node in gTrackedMixerNodes.allObjects) {
                if (![node isKindOfClass:[AVAudioMixerNode class]]) continue;
                node.outputVolume = gTikTokMuted ? 0.0f : 1.0f;
            }
        }
    }

    if (gTrackedEnvironmentNodes) {
        @synchronized (gTrackedEnvironmentNodes) {
            for (AVAudioEnvironmentNode *node in gTrackedEnvironmentNodes.allObjects) {
                if (![node isKindOfClass:[AVAudioEnvironmentNode class]]) continue;
                node.outputVolume = gTikTokMuted ? 0.0f : 1.0f;
            }
        }
    }

    if (gTrackedSampleRenderers) {
        @synchronized (gTrackedSampleRenderers) {
            for (AVSampleBufferAudioRenderer *renderer in gTrackedSampleRenderers.allObjects) {
                if (![renderer isKindOfClass:[AVSampleBufferAudioRenderer class]]) continue;
                renderer.muted = gTikTokMuted;
                if (gTikTokMuted) renderer.volume = 0.0f;
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
+ (instancetype)playerWithURL:(NSURL *)URL {
    AVPlayer *player = %orig(URL);
    if (IsTikTokAudio()) {
        TrackPlayer(player);
        if (gTikTokMuted) {
            player.muted = YES;
            player.volume = 0.0f;
        }
    }
    return player;
}

+ (instancetype)playerWithPlayerItem:(AVPlayerItem *)item {
    AVPlayer *player = %orig(item);
    if (IsTikTokAudio()) {
        TrackPlayer(player);
        if (gTikTokMuted) {
            player.muted = YES;
            player.volume = 0.0f;
        }
    }
    return player;
}

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

%hook AVAudioPlayerNode
- (instancetype)init {
    AVAudioPlayerNode *node = %orig;
    if (IsTikTokAudio()) TrackPlayerNode(node);
    return node;
}

- (void)setVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackPlayerNode(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}

- (void)play {
    if (IsTikTokAudio() && gTikTokMuted) self.volume = 0.0f;
    %orig;
    if (IsTikTokAudio() && gTikTokMuted) self.volume = 0.0f;
}
%end

%hook AVAudioMixerNode
- (instancetype)init {
    AVAudioMixerNode *node = %orig;
    if (IsTikTokAudio()) TrackMixerNode(node);
    return node;
}

- (void)setOutputVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackMixerNode(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}
%end

%hook AVAudioEnvironmentNode
- (instancetype)init {
    AVAudioEnvironmentNode *node = %orig;
    if (IsTikTokAudio()) TrackEnvironmentNode(node);
    return node;
}

- (void)setOutputVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackEnvironmentNode(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}
%end

%hook AVSampleBufferAudioRenderer
- (instancetype)init {
    AVSampleBufferAudioRenderer *renderer = %orig;
    if (IsTikTokAudio()) TrackSampleRenderer(renderer);
    return renderer;
}

- (void)setMuted:(BOOL)muted {
    if (IsTikTokAudio()) {
        TrackSampleRenderer(self);
        if (gTikTokMuted) muted = YES;
    }
    %orig(muted);
}

- (void)setVolume:(float)volume {
    if (IsTikTokAudio()) {
        TrackSampleRenderer(self);
        if (gTikTokMuted) volume = 0.0f;
    }
    %orig(volume);
}
%end

%ctor {
    if (!IsTikTokAudio()) return;

    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedAudioPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedEngines = [NSHashTable weakObjectsHashTable];
    gTrackedPlayerNodes = [NSHashTable weakObjectsHashTable];
    gTrackedMixerNodes = [NSHashTable weakObjectsHashTable];
    gTrackedEnvironmentNodes = [NSHashTable weakObjectsHashTable];
    gTrackedSampleRenderers = [NSHashTable weakObjectsHashTable];

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
