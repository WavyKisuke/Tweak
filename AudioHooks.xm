#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable<AVPlayer *> *gPlayers;
static NSHashTable<AVAudioPlayer *> *gAudioPlayers;
static NSHashTable<AVAudioEngine *> *gEngines;
static NSHashTable<AVAudioPlayerNode *> *gPlayerNodes;
static NSHashTable<AVAudioMixerNode *> *gMixerNodes;
static NSHashTable<AVAudioEnvironmentNode *> *gEnvironmentNodes;
static NSHashTable<AVSampleBufferAudioRenderer *> *gSampleRenderers;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindow *TopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    if (window.isKeyWindow) return window;
                }
            }
        }
    }
    return nil;
}

static void ApplyMuteState(void) {
    if (!gTikTokMuted) return;
    for (AVPlayer *p in gPlayers.allObjects) { p.muted = YES; p.volume = 0.0; }
    for (AVAudioPlayer *p in gAudioPlayers.allObjects) p.volume = 0.0;
    for (AVAudioEngine *e in gEngines.allObjects) e.mainMixerNode.outputVolume = 0.0;
    for (AVAudioPlayerNode *n in gPlayerNodes.allObjects) n.volume = 0.0;
    for (AVAudioMixerNode *n in gMixerNodes.allObjects) n.outputVolume = 0.0;
    for (AVAudioEnvironmentNode *n in gEnvironmentNodes.allObjects) n.outputVolume = 0.0;
    for (AVSampleBufferAudioRenderer *r in gSampleRenderers.allObjects) { r.muted = YES; r.volume = 0.0; }
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
- (void)tapMute:(id)sender { TikTokPlusSetMuted(!gTikTokMuted); }
@end
static TTKPlusAudioTarget *gAudioTarget;

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = TopWindow();
        if (!window) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];
        if (gMuteButton && gMuteButton.superview == window) { [window bringSubviewToFront:gMuteButton]; return; }
        [gMuteButton removeFromSuperview];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(window.bounds.size.width - 102, 60, 88, 38);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        b.layer.cornerRadius = 10;
        [b setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:b];
        gMuteButton = b;
    });
}

%hook AVPlayer
- (instancetype)init { AVPlayer *p = %orig; if (IsTikTok() && p) { [gPlayers addObject:p]; } return p; }
- (instancetype)initWithURL:(NSURL *)URL { AVPlayer *p = %orig; if (IsTikTok() && p) { [gPlayers addObject:p]; } return p; }
- (void)play { if (IsTikTok() && gTikTokMuted) { self.muted = YES; self.volume = 0.0; } %orig; if (IsTikTok() && gTikTokMuted) { self.muted = YES; self.volume = 0.0; } }
- (void)setMuted:(BOOL)muted { if (IsTikTok() && gTikTokMuted) muted = YES; %orig; }
- (void)setVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVQueuePlayer
- (instancetype)init { AVQueuePlayer *p = %orig; if (IsTikTok() && p) { [gPlayers addObject:p]; } return p; }
- (void)play { if (IsTikTok() && gTikTokMuted) { self.muted = YES; self.volume = 0.0; } %orig; if (IsTikTok() && gTikTokMuted) { self.muted = YES; self.volume = 0.0; } }
- (void)setMuted:(BOOL)muted { if (IsTikTok() && gTikTokMuted) muted = YES; %orig; }
- (void)setVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error { AVAudioPlayer *p = %orig; if (IsTikTok() && p) [gAudioPlayers addObject:p]; return p; }
- (void)play { if (IsTikTok() && gTikTokMuted) self.volume = 0.0; %orig; if (IsTikTok() && gTikTokMuted) self.volume = 0.0; }
- (void)setVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVAudioEngine
- (instancetype)init { AVAudioEngine *e = %orig; if (IsTikTok() && e) [gEngines addObject:e]; return e; }
- (void)startAndReturnError:(NSError **)error { %orig; if (IsTikTok() && gTikTokMuted) self.mainMixerNode.outputVolume = 0.0; }
%end

%hook AVAudioPlayerNode
- (instancetype)init { AVAudioPlayerNode *n = %orig; if (IsTikTok() && n) [gPlayerNodes addObject:n]; return n; }
- (void)play { if (IsTikTok() && gTikTokMuted) self.volume = 0.0; %orig; if (IsTikTok() && gTikTokMuted) self.volume = 0.0; }
- (void)setVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVAudioMixerNode
- (instancetype)init { AVAudioMixerNode *n = %orig; if (IsTikTok() && n) [gMixerNodes addObject:n]; return n; }
- (void)setOutputVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVAudioEnvironmentNode
- (instancetype)init { AVAudioEnvironmentNode *n = %orig; if (IsTikTok() && n) [gEnvironmentNodes addObject:n]; return n; }
- (void)setOutputVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%hook AVSampleBufferAudioRenderer
- (instancetype)init { AVSampleBufferAudioRenderer *r = %orig; if (IsTikTok() && r) [gSampleRenderers addObject:r]; return r; }
- (void)setMuted:(BOOL)muted { if (IsTikTok() && gTikTokMuted) muted = YES; %orig; }
- (void)setVolume:(float)volume { if (IsTikTok() && gTikTokMuted) volume = 0.0; %orig; }
%end

%ctor {
    if (!IsTikTok()) return;
    gPlayers = [NSHashTable weakObjectsHashTable];
    gAudioPlayers = [NSHashTable weakObjectsHashTable];
    gEngines = [NSHashTable weakObjectsHashTable];
    gPlayerNodes = [NSHashTable weakObjectsHashTable];
    gMixerNodes = [NSHashTable weakObjectsHashTable];
    gEnvironmentNodes = [NSHashTable weakObjectsHashTable];
    gSampleRenderers = [NSHashTable weakObjectsHashTable];
    dispatch_async(dispatch_get_main_queue(), ^{
        InstallMuteButton();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) { InstallMuteButton(); }];
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ InstallMuteButton(); if (gTikTokMuted) ApplyMuteState(); });
    dispatch_resume(timer);
}
