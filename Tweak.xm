#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static UIButton *gSaveButton = nil;
static NSHashTable *gTrackedPlayers = nil;
static NSMutableSet *gHookedClasses = nil;
static NSURL *gCurrentVideoURL = nil;
static BOOL gAdBlockEnabled = YES;

@interface TTKPlusButtonTarget : NSObject
@end

static BOOL IsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static void ShowMessage(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) { window = w; break; }
            }
            if (window) break;
        }
        if (!window) return;
        UILabel *label = [UILabel new];
        label.text = text;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        label.numberOfLines = 2;
        label.frame = CGRectMake(20, window.bounds.size.height - 110, window.bounds.size.width - 40, 48);
        label.layer.cornerRadius = 10;
        label.layer.masksToBounds = YES;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [window addSubview:label];
        [UIView animateWithDuration:0.25 delay:1.8 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL finished){ [label removeFromSuperview]; }];
    });
}

static void TrackPlayer(id obj) {
    if (!obj || !gTrackedPlayers) return;
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
    if (!gTikTokMuted || !gTrackedPlayers) return;
    @synchronized (gTrackedPlayers) { for (id player in gTrackedPlayers.allObjects) ApplyMute(player); }
}

@implementation TTKPlusButtonTarget
- (void)tapMute:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gMuteButton setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
    });
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
- (void)tapSave:(id)sender {
    NSURL *url = gCurrentVideoURL;
    if (!url) { ShowMessage(@"No video URL captured yet"); return; }
    NSString *s = url.absoluteString.lowercaseString;
    if ([s containsString:@".m3u8"]) { ShowMessage(@"This video uses a streaming playlist; direct HD save is unavailable for this clip"); return; }
    if (![url.scheme.lowercaseString isEqualToString:@"http"] && ![url.scheme.lowercaseString isEqualToString:@"https"]) { ShowMessage(@"Video URL is not downloadable"); return; }
    ShowMessage(@"Saving video…");
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { ShowMessage(@"Download failed"); return; }
        NSString *ext = @"mp4";
        NSString *mime = [response.MIMEType lowercaseString];
        if ([mime containsString:@"quicktime"]) ext = @"mov";
        NSString *name = [NSString stringWithFormat:@"TikTok_%@.%@", @((long long)[NSDate date].timeIntervalSince1970), ext];
        NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        if (![data writeToURL:file atomically:YES]) { ShowMessage(@"Could not save downloaded file"); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) { window = w; break; }
                }
                if (window) break;
            }
            UIViewController *vc = window.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) share.popoverPresentationController.sourceView = gSaveButton;
            [vc presentViewController:share animated:YES completion:nil];
        });
    }];
    [task resume];
}
@end

static TTKPlusButtonTarget *gButtonTarget = nil;

static void ConfigureAudioMixing(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    AVAudioSessionCategory cat = s.category;
    AVAudioSessionCategoryOptions opts = s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers;
    NSError *err = nil;
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback] || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] || [cat isEqualToString:AVAudioSessionCategoryMultiRoute]) [s setCategory:cat mode:s.mode options:opts error:&err];
}

static UIWindow *TopWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) return w;
        }
    }
    return nil;
}

static void InstallButtons(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *target = TopWindow();
        if (!target) return;
        if (!gButtonTarget) gButtonTarget = [TTKPlusButtonTarget new];
        if (!gMuteButton || !gMuteButton.superview) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(target.bounds.size.width - 102, 60, 88, 38);
            b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
            b.layer.cornerRadius = 10.0;
            b.layer.masksToBounds = YES;
            [b setTitle:(gTikTokMuted ? @"UNMUTE" : @"MUTE") forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
            b.accessibilityIdentifier = @"TikTokPlusMuteButton";
            [b addTarget:gButtonTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            [target addSubview:b]; gMuteButton = b;
        }
        if (!gSaveButton || !gSaveButton.superview) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(target.bounds.size.width - 102, 104, 88, 38);
            b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
            b.layer.cornerRadius = 10.0;
            b.layer.masksToBounds = YES;
            [b setTitle:@"HD SAVE" forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
            b.accessibilityIdentifier = @"TikTokPlusSaveButton";
            [b addTarget:gButtonTarget action:@selector(tapSave:) forControlEvents:UIControlEventTouchUpInside];
            [target addSubview:b]; gSaveButton = b;
        }
    });
}

static BOOL StringLooksLikeAd(NSString *text) {
    if (!gAdBlockEnabled || text.length == 0) return NO;
    NSString *s = text.lowercaseString;
    NSArray *markers = @[@"sponsored", @"promoted", @"advertisement", @"paid partnership", @"paid partnership with", @"ad ·", @"ad •"];
    for (NSString *m in markers) if ([s containsString:m]) return YES;
    return NO;
}

static void ScanAndHideAds(UIView *view) {
    if (!view || view.hidden) return;
    NSString *label = view.accessibilityLabel;
    if (StringLooksLikeAd(label)) {
        UIView *candidate = view;
        while (candidate.superview && ![candidate isKindOfClass:NSClassFromString(@"UICollectionViewCell")] && ![candidate isKindOfClass:NSClassFromString(@"UITableViewCell")]) candidate = candidate.superview;
        if (candidate != view.superview) candidate.hidden = YES;
        return;
    }
    if ([view isKindOfClass:[UILabel class]] && StringLooksLikeAd(((UILabel *)view).text)) {
        UIView *candidate = view;
        while (candidate.superview && ![candidate isKindOfClass:NSClassFromString(@"UICollectionViewCell")] && ![candidate isKindOfClass:NSClassFromString(@"UITableViewCell")]) candidate = candidate.superview;
        candidate.hidden = YES;
        return;
    }
    for (UIView *sub in view.subviews) ScanAndHideAds(sub);
}

static void HideAds(void) {
    if (!gAdBlockEnabled) return;
    UIWindow *w = TopWindow();
    if (w) ScanAndHideAds(w);
}

static void HookSetVolume(Class cls) {
    SEL sel = @selector(setVolume:); Method m = class_getInstanceMethod(cls, sel); if (!m) return;
    IMP old = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(^(id self, float volume) {
        TrackPlayer(self); if (gTikTokMuted) volume = 0.0f;
        ((void (*)(id, SEL, float))old)(self, sel, volume);
    });
    method_setImplementation(m, replacement);
}

static void HookMuteMethod(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel); if (!m) return;
    IMP old = method_getImplementation(m);
    IMP replacement = imp_implementationWithBlock(^(id self, BOOL mute) {
        TrackPlayer(self); ((void (*)(id, SEL, BOOL))old)(self, sel, gTikTokMuted ? YES : mute);
    });
    method_setImplementation(m, replacement);
}

static void InstallPlayerHooks(void) {
    NSArray<NSString *> *names = @[@"TTKECMMKVideoPlayer", @"BDXLynxVideoPlayerPro", @"IESMMBGAVPlayer", @"IESMMBGVideoPlayer", @"VEEffectVideoPlayer"];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name); if (!cls || [gHookedClasses containsObject:name]) continue;
        BOOL found = class_getInstanceMethod(cls, @selector(setVolume:)) || class_getInstanceMethod(cls, sel_registerName("mute:")) || class_getInstanceMethod(cls, sel_registerName("unfocusedMute:")) || class_getInstanceMethod(cls, sel_registerName("mutePlayer:"));
        if (!found) continue;
        HookSetVolume(cls); HookMuteMethod(cls, sel_registerName("mute:")); HookMuteMethod(cls, sel_registerName("unfocusedMute:")); HookMuteMethod(cls, sel_registerName("mutePlayer:"));
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

%hook AVPlayerItem
- (instancetype)initWithURL:(NSURL *)URL {
    id result = %orig;
    if (IsTikTok() && URL) gCurrentVideoURL = URL;
    return result;
}
- (instancetype)initWithAsset:(AVAsset *)asset {
    id result = %orig;
    if (IsTikTok() && [asset isKindOfClass:[AVURLAsset class]]) gCurrentVideoURL = ((AVURLAsset *)asset).URL;
    return result;
}
%end

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    if (IsTikTok() && item.asset) {
        AVAsset *asset = item.asset;
        if ([asset isKindOfClass:[AVURLAsset class]]) gCurrentVideoURL = ((AVURLAsset *)asset).URL;
    }
    %orig(item);
}
%end

%ctor {
    if (!IsTikTok()) return;
    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gHookedClasses = [NSMutableSet set];
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 0.25 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        ConfigureAudioMixing();
        InstallPlayerHooks();
        InstallButtons();
        ApplyMuteToTrackedPlayers();
        HideAds();
    });
    dispatch_resume(timer);
}
