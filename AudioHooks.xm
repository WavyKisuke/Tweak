#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSMutableSet *gHookedClasses = nil;

static BOOL IsTikTokAudio(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *AudioTopWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) return w;
        }
    }
    return nil;
}

static void TrackAudioPlayer(id obj) {
    if (!obj || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) { [gTrackedPlayers addObject:obj]; }
}

static void ApplyAudioMute(id player) {
    if (!player || !gTikTokMuted) return;
    Class cls = object_getClass(player);
    SEL sels[] = { sel_registerName("mute:"), sel_registerName("unfocusedMute:"), sel_registerName("mutePlayer:") };
    for (NSUInteger i = 0; i < 3; i++) {
        if ([cls instancesRespondToSelector:sels[i]]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], YES); return; }
    }
    if ([cls instancesRespondToSelector:@selector(setVolume:)]) ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), 0.0f);
}

static void ApplyAudioMuteToTracked(void) {
    if (!gTikTokMuted || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) { for (id player in gTrackedPlayers.allObjects) ApplyAudioMute(player); }
}

@interface TTKPlusAudioTarget : NSObject
@end
@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    [gMuteButton setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
    if (gTrackedPlayers) {
        @synchronized (gTrackedPlayers) {
            for (id player in gTrackedPlayers.allObjects) {
                Class cls = object_getClass(player);
                SEL a = sel_registerName("mute:"), b = sel_registerName("unfocusedMute:"), c = sel_registerName("mutePlayer:");
                if ([cls instancesRespondToSelector:a]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, a, gTikTokMuted);
                else if ([cls instancesRespondToSelector:b]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, b, gTikTokMuted);
                else if ([cls instancesRespondToSelector:c]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, c, gTikTokMuted);
                else if ([cls instancesRespondToSelector:@selector(setVolume:)]) ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), gTikTokMuted ? 0.0f : 1.0f);
            }
        }
    }
}
@end

static TTKPlusAudioTarget *gAudioTarget = nil;

static BOOL ClassDeclaresSelector(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    free(methods);
    return found;
}

static void HookVolume(Class cls) {
    SEL sel = @selector(setVolume:);
    if (!ClassDeclaresSelector(cls, sel)) return;
    Method m = class_getInstanceMethod(cls, sel); if (!m) return;
    IMP old = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(^(id self, float volume) {
        TrackAudioPlayer(self); if (gTikTokMuted) volume = 0.0f;
        ((void (*)(id, SEL, float))old)(self, sel, volume);
    });
    method_setImplementation(m, repl);
}

static void HookMute(Class cls, SEL sel) {
    if (!ClassDeclaresSelector(cls, sel)) return;
    Method m = class_getInstanceMethod(cls, sel); if (!m) return;
    IMP old = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(^(id self, BOOL mute) {
        TrackAudioPlayer(self); ((void (*)(id, SEL, BOOL))old)(self, sel, gTikTokMuted ? YES : mute);
    });
    method_setImplementation(m, repl);
}

static void InstallAudioPlayerHooks(void) {
    NSArray *names = @[@"TTKECMMKVideoPlayer", @"BDXLynxVideoPlayerPro", @"IESMMBGAVPlayer", @"IESMMBGVideoPlayer", @"VEEffectVideoPlayer"];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name); if (!cls || [gHookedClasses containsObject:name]) continue;
        BOOL found = ClassDeclaresSelector(cls, @selector(setVolume:)) || ClassDeclaresSelector(cls, sel_registerName("mute:")) || ClassDeclaresSelector(cls, sel_registerName("unfocusedMute:")) || ClassDeclaresSelector(cls, sel_registerName("mutePlayer:"));
        if (!found) continue;
        HookVolume(cls); HookMute(cls, sel_registerName("mute:")); HookMute(cls, sel_registerName("unfocusedMute:")); HookMute(cls, sel_registerName("mutePlayer:"));
        [gHookedClasses addObject:name];
    }
}

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AudioTopWindow(); if (!w) return;
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
        [w addSubview:b]; gMuteButton = b;
    });
}

%hook AVAudioSession
- (BOOL)setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTokAudio()) options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, mode, options, outError);
}
- (BOOL)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTokAudio()) options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, options, outError);
}
%end

%ctor {
    if (!IsTikTokAudio()) return;
    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gHookedClasses = [NSMutableSet set];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ InstallMuteButton(); });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 0.25 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ InstallAudioPlayerHooks(); InstallMuteButton(); ApplyAudioMuteToTracked(); });
    dispatch_resume(timer);
}
