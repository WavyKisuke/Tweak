#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton;
static id gAudioTarget;
static NSHashTable *gPlayers;
static NSHashTable *gAudioObjects;
static NSMutableDictionary *gAVOriginals;

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

static IMP OriginalFor(Class cls, SEL sel) {
    if (!gAVOriginals) return NULL;
    return [gAVOriginals[NSStringFromClass(cls) stringByAppendingFormat:@":%@", NSStringFromSelector(sel)] pointerValue];
}

static void SaveAndHook(Class cls, SEL sel, IMP replacement) {
    if (!cls || !replacement) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSString *key = [NSStringFromClass(cls) stringByAppendingFormat:@":%@", NSStringFromSelector(sel)];
    if (gAVOriginals[key]) return;
    IMP original = method_getImplementation(m);
    gAVOriginals[key] = [NSValue valueWithPointer:original];
    method_setImplementation(m, replacement);
}

static BOOL IsSubclassOf(Class cls, Class base) {
    if (!cls || !base) return NO;
    for (Class c = cls; c; c = class_getSuperclass(c)) if (c == base) return YES;
    return NO;
}

static void TTK_AVPlayerPlay(id self, SEL _cmd) {
    [gPlayers addObject:self];
    if (gTikTokMuted) ForceMuteObject(self);
    IMP orig = OriginalFor(NSClassFromString(@"AVPlayer"), @selector(play));
    if (orig) ((void(*)(id,SEL))orig)(self,_cmd);
    if (gTikTokMuted) ForceMuteObject(self);
}
static void TTK_AVPlayerSetMuted(id self, SEL _cmd, BOOL muted) {
    if (gTikTokMuted) muted = YES;
    IMP orig = OriginalFor(NSClassFromString(@"AVPlayer"), @selector(setMuted:));
    if (!orig) orig = class_getMethodImplementation(NSClassFromString(@"AVPlayer"), _cmd);
    if (orig) ((void(*)(id,SEL,BOOL))orig)(self,_cmd,muted);
}
static void TTK_AVPlayerSetVolume(id self, SEL _cmd, float volume) {
    if (gTikTokMuted) volume = 0.0f;
    IMP orig = OriginalFor(NSClassFromString(@"AVPlayer"), @selector(setVolume:));
    if (orig) ((void(*)(id,SEL,float))orig)(self,_cmd,volume);
}
static void TTK_AVAudioPlayerPlay(id self, SEL _cmd) {
    [gAudioObjects addObject:self];
    if (gTikTokMuted) ForceMuteObject(self);
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioPlayer"), @selector(play));
    if (orig) ((void(*)(id,SEL))orig)(self,_cmd);
    if (gTikTokMuted) ForceMuteObject(self);
}
static void TTK_AVAudioPlayerSetVolume(id self, SEL _cmd, float volume) {
    if (gTikTokMuted) volume = 0.0f;
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioPlayer"), @selector(setVolume:));
    if (orig) ((void(*)(id,SEL,float))orig)(self,_cmd,volume);
}
static void TTK_AVAudioPlayerNodePlay(id self, SEL _cmd) {
    [gAudioObjects addObject:self];
    if (gTikTokMuted) ForceMuteObject(self);
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioPlayerNode"), @selector(play));
    if (orig) ((void(*)(id,SEL))orig)(self,_cmd);
    if (gTikTokMuted) ForceMuteObject(self);
}
static void TTK_AVAudioMixerSetOutputVolume(id self, SEL _cmd, float volume) {
    if (gTikTokMuted) volume = 0.0f;
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioMixerNode"), @selector(setOutputVolume:));
    if (orig) ((void(*)(id,SEL,float))orig)(self,_cmd,volume);
}
static void TTK_AVAudioEnvironmentSetOutputVolume(id self, SEL _cmd, float volume) {
    if (gTikTokMuted) volume = 0.0f;
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioEnvironmentNode"), @selector(setOutputVolume:));
    if (orig) ((void(*)(id,SEL,float))orig)(self,_cmd,volume);
}
static void TTK_AVSamplePlay(id self, SEL _cmd) {
    [gAudioObjects addObject:self];
    if (gTikTokMuted) ForceMuteObject(self);
    IMP orig = OriginalFor(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(play));
    if (orig) ((void(*)(id,SEL))orig)(self,_cmd);
    if (gTikTokMuted) ForceMuteObject(self);
}
static void TTK_AVSampleSetMuted(id self, SEL _cmd, BOOL muted) {
    if (gTikTokMuted) muted = YES;
    IMP orig = OriginalFor(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(setMuted:));
    if (orig) ((void(*)(id,SEL,BOOL))orig)(self,_cmd,muted);
}
static void TTK_AVSampleSetVolume(id self, SEL _cmd, float volume) {
    if (gTikTokMuted) volume = 0.0f;
    IMP orig = OriginalFor(NSClassFromString(@"AVSampleBufferAudioRenderer"), @selector(setVolume:));
    if (orig) ((void(*)(id,SEL,float))orig)(self,_cmd,volume);
}
static BOOL TTK_AVAudioEngineStart(id self, SEL _cmd, NSError **error) {
    IMP orig = OriginalFor(NSClassFromString(@"AVAudioEngine"), @selector(startAndReturnError:));
    BOOL result = orig ? ((BOOL(*)(id,SEL,NSError**))orig)(self,_cmd,error) : NO;
    if (gTikTokMuted && [self respondsToSelector:@selector(mainMixerNode)]) {
        id mixer = [self mainMixerNode];
        if ([mixer respondsToSelector:@selector(setOutputVolume:)]) [mixer setOutputVolume:0.0f];
    }
    return result;
}

static void InstallAVHooks(void) {
    if (!gAVOriginals) gAVOriginals = [NSMutableDictionary dictionary];
    Class player = NSClassFromString(@"AVPlayer");
    SaveAndHook(player,@selector(play),(IMP)TTK_AVPlayerPlay);
    SaveAndHook(player,@selector(setMuted:),(IMP)TTK_AVPlayerSetMuted);
    SaveAndHook(player,@selector(setVolume:),(IMP)TTK_AVPlayerSetVolume);

    Class audioPlayer = NSClassFromString(@"AVAudioPlayer");
    SaveAndHook(audioPlayer,@selector(play),(IMP)TTK_AVAudioPlayerPlay);
    SaveAndHook(audioPlayer,@selector(setVolume:),(IMP)TTK_AVAudioPlayerSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioPlayerNode"),@selector(play),(IMP)TTK_AVAudioPlayerNodePlay);
    SaveAndHook(NSClassFromString(@"AVAudioMixerNode"),@selector(setOutputVolume:),(IMP)TTK_AVAudioMixerSetOutputVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEnvironmentNode"),@selector(setOutputVolume:),(IMP)TTK_AVAudioEnvironmentSetOutputVolume);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(play),(IMP)TTK_AVSamplePlay);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setMuted:),(IMP)TTK_AVSampleSetMuted);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setVolume:),(IMP)TTK_AVSampleSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEngine"),@selector(startAndReturnError:),(IMP)TTK_AVAudioEngineStart);

    // TikTok may use AVPlayer subclasses that override these methods.
    if (player) {
        int count = objc_getClassList(NULL,0);
        if (count > 0) {
            Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class)*count);
            count = objc_getClassList(classes,count);
            for (int i=0;i<count;i++) {
                Class cls = classes[i];
                if (cls == player || !IsSubclassOf(cls,player)) continue;
                Method play = class_getInstanceMethod(cls,@selector(play));
                Method muted = class_getInstanceMethod(cls,@selector(setMuted:));
                Method volume = class_getInstanceMethod(cls,@selector(setVolume:));
                if (play && class_getMethodImplementation(cls,@selector(play)) != method_getImplementation(play)) method_setImplementation(play,(IMP)TTK_AVPlayerPlay);
                if (muted && class_getMethodImplementation(cls,@selector(setMuted:)) != method_getImplementation(muted)) method_setImplementation(muted,(IMP)TTK_AVPlayerSetMuted);
                if (volume && class_getMethodImplementation(cls,@selector(setVolume:)) != method_getImplementation(volume)) method_setImplementation(volume,(IMP)TTK_AVPlayerSetVolume);
            }
            free(classes);
        }
    }
}

%ctor {
    if (!IsTikTok()) return;
    gPlayers = [NSHashTable weakObjectsHashTable];
    gAudioObjects = [NSHashTable weakObjectsHashTable];
    gAVOriginals = [NSMutableDictionary dictionary];
    InstallAVHooks();
    dispatch_async(dispatch_get_main_queue(), ^{ InstallMuteButton(); });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{ InstallAVHooks(); InstallMuteButton(); if (gTikTokMuted) ApplyMuteState(); });
    dispatch_resume(timer);
}
