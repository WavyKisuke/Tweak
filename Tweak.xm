#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static NSMutableArray *gTrackedPlayers = nil;

@interface TTKAudioMixButtonTarget : NSObject
@end
@implementation TTKAudioMixButtonTarget
- (void)tap:(UIButton *)sender {
    gTikTokMuted = !gTikTokMuted;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gMuteButton setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
    });
    @synchronized (gTrackedPlayers) {
        for (id player in [gTrackedPlayers copy]) {
            Class cls = object_getClass(player);
            if (!player) continue;
            if (gTikTokMuted) {
                SEL sels[] = { sel_registerName("mute:"), sel_registerName("unfocusedMute:"), sel_registerName("mutePlayer:") };
                for (NSUInteger i = 0; i < 3; i++) {
                    if ([cls instancesRespondToSelector:sels[i]]) {
                        ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], YES);
                        break;
                    }
                }
                if ([cls instancesRespondToSelector:@selector(setVolume:)]) {
                    ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), 0.0f);
                }
            } else {
                SEL sels[] = { sel_registerName("unfocusedMute:"), sel_registerName("mute:") };
                for (NSUInteger i = 0; i < 2; i++) {
                    if ([cls instancesRespondToSelector:sels[i]]) {
                        ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], NO);
                        break;
                    }
                }
            }
        }
    }
}
@end

static TTKAudioMixButtonTarget *gButtonTarget = nil;

static BOOL IsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static void TrackPlayer(id obj) {
    if (!obj || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) {
        if (![gTrackedPlayers containsObject:obj]) [gTrackedPlayers addObject:obj];
    }
}

static void SetPlayerMuted(id player, BOOL muted) {
    if (!player) return;
    Class cls = object_getClass(player);
    if (muted) {
        SEL sels[] = { sel_registerName("mute:"), sel_registerName("unfocusedMute:"), sel_registerName("mutePlayer:") };
        for (NSUInteger i = 0; i < 3; i++) {
            if ([cls instancesRespondToSelector:sels[i]]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], YES);
                break;
            }
        }
        if ([cls instancesRespondToSelector:@selector(setVolume:)])
            ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), 0.0f);
    } else {
        SEL sels[] = { sel_registerName("unfocusedMute:"), sel_registerName("mute:") };
        for (NSUInteger i = 0; i < 2; i++) {
            if ([cls instancesRespondToSelector:sels[i]]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(player, sels[i], NO);
                break;
            }
        }
    }
}

static void ApplyMute(void) {
    @synchronized (gTrackedPlayers) {
        for (id player in [gTrackedPlayers copy]) SetPlayerMuted(player, gTikTokMuted);
    }
}

static void ConfigureAudioMixing(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    AVAudioSessionCategory cat = s.category;
    if (!cat) return;
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback] ||
        [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
        [cat isEqualToString:AVAudioSessionCategoryMultiRoute]) {
        AVAudioSessionCategoryOptions opts = s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers;
        NSError *err = nil;
        [s setCategory:cat mode:s.mode options:opts error:&err];
    }
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

static void HookSetVolume(Class cls) {
    SEL sel = @selector(setVolume:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP old = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(^(id self, float volume) {
        TrackPlayer(self);
        ((void (*)(id, SEL, float))old)(self, sel, gTikTokMuted ? 0.0f : volume);
    });
    method_setImplementation(m, replacement);
}

static void InstallPlayerHooks(void) {
    NSArray *names = @[@"TTKECMMKVideoPlayer", @"BDXLynxVideoPlayerPro", @"IESMMBGAVPlayer", @"IESMMBGVideoPlayer", @"VEEffectVideoPlayer"];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        HookSetVolume(cls);
        HookMuteMethod(cls, sel_registerName("mute:"));
        HookMuteMethod(cls, sel_registerName("unfocusedMute:"));
        HookMuteMethod(cls, sel_registerName("mutePlayer:"));
    }
}

static void InstallButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gMuteButton) return;
        UIWindow *target = nil;
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) { target = w; break; }
        }
        if (!target) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ InstallButton(); });
            return;
        }
        gButtonTarget = [TTKAudioMixButtonTarget new];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(target.bounds.size.width - 92, 60, 82, 40);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        b.layer.cornerRadius = 10;
        b.layer.masksToBounds = YES;
        [b setTitle:@"MUTE" forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [b addTarget:gButtonTarget action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        b.accessibilityIdentifier = @"TikTokAudioMixMuteButton";
        [target addSubview:b];
        gMuteButton = b;
    });
}

%hook AVAudioSession
- (BOOL)setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTok() && ([category isEqualToString:AVAudioSessionCategoryPlayback] || [category isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [category isEqualToString:AVAudioSessionCategoryMultiRoute]))
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (IsTikTok() && ([category isEqualToString:AVAudioSessionCategoryPlayback] || [category isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [category isEqualToString:AVAudioSessionCategoryMultiRoute]))
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    return %orig(category, options, outError);
}
%end

%ctor {
    if (!IsTikTok()) return;
    gTrackedPlayers = [NSMutableArray array];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ConfigureAudioMixing();
        InstallPlayerHooks();
        InstallButton();
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 0.25 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        ConfigureAudioMixing();
        if (gTikTokMuted) ApplyMute();
        if (!gMuteButton) InstallButton();
    });
    dispatch_resume(timer);
}
