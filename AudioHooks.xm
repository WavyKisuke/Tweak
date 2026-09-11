#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton;
static id gAudioTarget;
static NSHashTable *gPlayers;
static NSHashTable *gAudioObjects;

static BOOL IsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *TopWindow(void) {
    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0.01 || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
                if (!fallback) fallback = window;
                if (window.isKeyWindow) return window;
            }
        }
        return fallback;
    }
    return nil;
}

static void ForceMuteObject(id object) {
    if (!object || !gTikTokMuted) return;
    if ([object respondsToSelector:@selector(setMuted:)]) [object setMuted:YES];
    if ([object respondsToSelector:@selector(setVolume:)]) [object setVolume:0.0f];
    if ([object respondsToSelector:@selector(setOutputVolume:)]) [object setOutputVolume:0.0f];
}

static void ApplyMuteState(void) {
    if (!gTikTokMuted) return;
    for (id object in gPlayers.allObjects) ForceMuteObject(object);
    for (id object in gAudioObjects.allObjects) ForceMuteObject(object);
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

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = TopWindow();
        if (!window) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];
        if (gMuteButton.superview == window) {
            gMuteButton.hidden = NO;
            gMuteButton.alpha = 1.0;
            [window bringSubviewToFront:gMuteButton];
            return;
        }
        [gMuteButton removeFromSuperview];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(MAX(8.0, window.bounds.size.width - 110.0), 60.0, 96.0, 42.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
        button.layer.cornerRadius = 10.0;
        button.layer.zPosition = 10000.0;
        [button setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        [button addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:button];
        [window bringSubviewToFront:button];
        gMuteButton = button;
    });
}

void TikTokPlusInstallMuteButton(void) { if (IsTikTok()) InstallMuteButton(); }

static IMP gAVPlayerPlay;
static IMP gAVPlayerSetMuted;
static IMP gAVPlayerSetVolume;
static IMP gAVAudioPlayerPlay;
static IMP gAVAudioPlayerSetVolume;
static IMP gAVAudioPlayerNodePlay;
static IMP gAVAudioMixerSetOutputVolume;
static IMP gAVAudioEnvironmentSetOutputVolume;
static IMP gAVSamplePlay;
static IMP gAVSampleSetMuted;
static IMP gAVSampleSetVolume;
static IMP gAVAudioEngineStart;

static void HookMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || !replacement || !original || *original) return;
    *original = method_getImplementation(m);
    method_setImplementation(m, replacement);
}

static void TTK_AVPlayerPlay(id self, SEL _cmd) { [gPlayers addObject:self]; if (gTikTokMuted) ForceMuteObject(self); if (gAVPlayerPlay) ((void(*)(id,SEL))gAVPlayerPlay)(self,_cmd); if (gTikTokMuted) ForceMuteObject(self); }
static void TTK_AVPlayerSetMuted(id self, SEL _cmd, BOOL muted) { if (gTikTokMuted) muted = YES; if (gAVPlayerSetMuted) ((void(*)(id,SEL,BOOL))gAVPlayerSetMuted)(self,_cmd,muted); }
static void TTK_AVPlayerSetVolume(id self, SEL _cmd, float volume) { if (gTikTokMuted) volume = 0.0f; if (gAVPlayerSetVolume) ((void(*)(id,SEL,float))gAVPlayerSetVolume)(self,_cmd,volume); }
static void TTK_AVAudioPlayerPlay(id self, SEL _cmd) { [gAudioObjects addObject:self]; if (gTikTokMuted) ForceMuteObject(self); if (gAVAudioPlayerPlay) ((void(*)(id,SEL))gAVAudioPlayerPlay)(self,_cmd); if (gTikTokMuted) ForceMuteObject(self); }
static void TTK_AVAudioPlayerSetVolume(id self, SEL _cmd, float volume) { if (gTikTokMuted) volume = 0.0f; if (gAVAudioPlayerSetVolume) ((void(*)(id,SEL,float))gAVAudioPlayerSetVolume)(self,_cmd,volume); }
static void TTK_AVAudioPlayerNodePlay(id self, SEL _cmd) { [gAudioObjects addObject:self]; if (gTikTokMuted) ForceMuteObject(self); if (gAVAudioPlayerNodePlay) ((void(*)(id,SEL))gAVAudioPlayerNodePlay)(self,_cmd); if (gTikTokMuted) ForceMuteObject(self); }
static void TTK_AVAudioMixerSetOutputVolume(id self, SEL _cmd, float volume) { if (gTikTokMuted) volume = 0.0f; if (gAVAudioMixerSetOutputVolume) ((void(*)(id,SEL,float))gAVAudioMixerSetOutputVolume)(self,_cmd,volume); }
static void TTK_AVAudioEnvironmentSetOutputVolume(id self, SEL _cmd, float volume) { if (gTikTokMuted) volume = 0.0f; if (gAVAudioEnvironmentSetOutputVolume) ((void(*)(id,SEL,float))gAVAudioEnvironmentSetOutputVolume)(self,_cmd,volume); }
static void TTK_AVSamplePlay(id self, SEL _cmd) { [gAudioObjects addObject:self]; if (gTikTokMuted) ForceMuteObject(self); if (gAVSamplePlay) ((void(*)(id,SEL))gAVSamplePlay)(self,_cmd); if (gTikTokMuted) ForceMuteObject(self); }
static void TTK_AVSampleSetMuted(id self, SEL _cmd, BOOL muted) { if (gTikTokMuted) muted = YES; if (gAVSampleSetMuted) ((void(*)(id,SEL,BOOL))gAVSampleSetMuted)(self,_cmd,muted); }
static void TTK_AVSampleSetVolume(id self, SEL _cmd, float volume) { if (gTikTokMuted) volume = 0.0f; if (gAVSampleSetVolume) ((void(*)(id,SEL,float))gAVSampleSetVolume)(self,_cmd,volume); }
static BOOL TTK_AVAudioEngineStart(id self, SEL _cmd, NSError **error) { BOOL result = gAVAudioEngineStart ? ((BOOL(*)(id,SEL,NSError**))gAVAudioEngineStart)(self,_cmd,error) : NO; if (gTikTokMuted && [self respondsToSelector:@selector(mainMixerNode)]) { id mixer = [self mainMixerNode]; if ([mixer respondsToSelector:@selector(setOutputVolume:)]) [mixer setOutputVolume:0.0f]; } return result; }

static void InstallAVHooks(void) {
    HookMethod(NSClassFromString(@"AVPlayer"), @selector(play), (IMP)TTK_AVPlayerPlay, &gAVPlayerPlay);
    HookMethod(NSClassFromString(@"AVPlayer"), @selector(setMuted:), (IMP)TTK_AVPlayerSetMuted, &gAVPlayerSetMuted);
    HookMethod(NSClassFromString(@"AVPlayer"), @selector(setVolume:), (IMP)TTK_AVPlayerSetVolume, &gAVPlayerSetVolume);
    HookMethod(NSClassFromString(@"AVAudioPlayer"), @selector(play), (IMP)TTK_AVAudioPlayerPlay, &gAVAudioPlayerPlay);
    HookMethod(NSClassFromString(@"AVAudioPlayer"), @selector(setVolume:), (IMP)TTK_AVAudioPlayerSetVolume, &gAVAudioPlayerSetVolume);
    HookMethod(NSClassFromString(@"AVAudioPlayerNode"), @selector(play), (IMP)TTK_AVAudioPlayerNodePlay, &gAVAudioPlayerNodePlay);
    HookMethod(NSClassFromString(@"AVAudioMixerNode"), @selector(setOutputVolume:), (IMP)TTK_AVAudioMixerSetOutputVolume, &gAVAudioMixerSetOutputVolume);
    HookMethod(NSClassFromString(@"AVAudioEnvironmentNode"), @selector(setOutputVolume:), (IMP)TTK_AVAudioEnvironmentSetOutputVolume, &gAVAudioEnvironmentSetOutputVolume);
    HookMethod(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(play), (IMP)TTK_AVSamplePlay, &gAVSamplePlay);
    HookMethod(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(setMuted:), (IMP)TTK_AVSampleSetMuted, &gAVSampleSetMuted);
    HookMethod(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(setVolume:), (IMP)TTK_AVSampleSetVolume, &gAVSampleSetVolume);
    HookMethod(NSClassFromString(@"AVAudioEngine"), @selector(startAndReturnError:), (IMP)TTK_AVAudioEngineStart, &gAVAudioEngineStart);
}

%ctor {
    if (!IsTikTok()) return;
    gPlayers = [NSHashTable weakObjectsHashTable];
    gAudioObjects = [NSHashTable weakObjectsHashTable];
    dispatch_async(dispatch_get_main_queue(), ^{ InstallMuteButton(); });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ InstallAVHooks(); InstallMuteButton(); if (gTikTokMuted) ApplyMuteState(); });
    dispatch_resume(timer);
}
