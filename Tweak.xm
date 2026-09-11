#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSMutableSet *gHookedClasses = nil;

@interface TTKAMButtonTarget : NSObject
@end
@implementation TTKAMButtonTarget
- (void)tap:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gMuteButton setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
    });
    @synchronized (gTrackedPlayers) {
        for (id player in gTrackedPlayers.allObjects) {
            Class cls = object_getClass(player);
            SEL muteSel = sel_registerName("mute:");
            SEL unfocusedSel = sel_registerName("unfocusedMute:");
            SEL mutePlayerSel = sel_registerName("mutePlayer:");
            if ([cls instancesRespondToSelector:muteSel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, muteSel, gTikTokMuted);
            else if ([cls instancesRespondToSelector:unfocusedSel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, unfocusedSel, gTikTokMuted);
            else if ([cls instancesRespondToSelector:mutePlayerSel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(player, mutePlayerSel, gTikTokMuted);
            else if ([cls instancesRespondToSelector:@selector(setVolume:)]) ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), gTikTokMuted ? 0.0f : 1.0f);
        }
    }
}
@end

static TTKAMButtonTarget *gButtonTarget = nil;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static void TrackPlayer(id obj) {
    if (!obj) return;
    @synchronized (gTrackedPlayers) { [gTrackedPlayers addObject:obj]; }
}

static void ApplyMute(id player) {
    if (!player || !gTikTokMuted) return;
    Class cls = object_getClass(player);
    SEL sels[] = { sel_registerName("mute:"), sel_registerName("unfocusedMute:"), sel_registerName("mutePlayer:") };
    for (NSUInteger i = 0; i < 3; i++) {
        if ([cls instancesRespondToSelector:sels[i]]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], YES); return; }
    }
    if ([cls instancesRespondToSelector:@selector(setVolume:)]) ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), 0.0f);
}

static void ApplyMuteToTrackedPlayers(void) {
    if (!gTikTokMuted) return;
    @synchronized (gTrackedPlayers) { for (id player in gTrackedPlayers.allObjects) ApplyMute(player); }
}

static void ConfigureAudioMixing(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    AVAudioSessionCategory cat = s.category;
    AVAudioSessionCategoryOptions opts = s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers;
    NSError *err = nil;
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback] || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [cat isEqualToString:AVAudioSessionCategoryMultiRoute]) [s setCategory:cat mode:s.mode options:opts error:&err];
}

static void InstallButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gMuteButton && gMuteButton.superview) return;
        UIWindow *target = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) { target = w; break; }
            }
            if (target) break;
        }
        if (!target) return;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(target.bounds.size.width - 100, 60, 88, 38);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        b.layer.cornerRadius = 10.0;
        b.layer.masksToBounds = YES;
        [b setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        b.accessibilityIdentifier = @"TikTokAudioMixMuteButton";
        if (!gButtonTarget) gButtonTarget = [TTKAMButtonTarget new];
        [b addTarget:gButtonTarget action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        [target addSubview:b];
        gMuteButton = b;
    });
}

static void HookSetVolume(Class cls) {
    SEL sel = @selector(setVolume:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP old = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(^(id self, float volume) {
        TrackPlayer(self);
        if (gTikTokMuted) volume = 0.0f;
        ((void (*)(id, SEL, float))old)(self, sel, volume);
    });
    method_setImplementation(m, replacement);
}

static void HookMuteMethod(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP old = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(^(id self, BOOL mute) {
        TrackPlayer(self);
        ((void (*)(id, SEL, BOOL))old)(self, sel, gTikTokMuted ? YES : mute);
    });
    method_setImplementation(m, replacement);
}

static void InstallPlayerHooks(void) {
    NSArray<NSString *> *names = @[@"TTKECMMKVideoPlayer", @"BDXLynxVideoPlayerPro", @"IESMMBGAVPlayer", @"IESMMBGVideoPlayer", @"VEEffectVideoPlayer"];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls || [gHookedClasses containsObject:name]) continue;
        BOOL found = class_getInstanceMethod(cls, @selector(setVolume:)) || class_getInstanceMethod(cls, sel_registerName("mute:")) || class_getInstanceMethod(cls, sel_registerName("unfocusedMute:")) || class_getInstanceMethod(cls, sel_registerName("mutePlayer:"));
        if (!found) continue;
        HookSetVolume(cls);
        HookMuteMethod(cls, sel_registerName("mute:"));
        HookMuteMethod(cls, sel_registerName("unfocusedMute:"));
        HookMuteMethod(cls, sel_registerName("mutePlayer:"));
        [gHookedClasses addObject:name];
    }
}

%hook AVAudioSession
- (BOOL)setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTok() && ([category isEqualToString:AVAudioSessionCategoryPlayback] || [category isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [category isEqualToString:AVAudioSessionCategoryMultiRoute])) options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, mode, options, outError);
}
- (BOOL)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTok() && ([category isEqualToString:AVAudioSessionCategoryPlayback] || [category isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [category isEqualToString:AVAudioSessionCategoryMultiRoute])) options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, options, outError);
}
%end

%ctor {
    if (!IsTikTok()) return;
    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gHookedClasses = [NSMutableSet set];
    dispatch_async(dispatch_get_main_queue(), ^{ InstallPlayerHooks(); InstallButton(); });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 0.25 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ ConfigureAudioMixing(); InstallPlayerHooks(); InstallButton(); ApplyMuteToTrackedPlayers(); });
    dispatch_resume(timer);
}
