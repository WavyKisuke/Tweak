#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL isGloballyMuted = YES;
static UIButton *gMuteButton = nil;
static UIWindow *gMuteHostWindow = nil;
static id gMuteTarget = nil;
static NSInteger const kMuteButtonTag = 190612;

@interface TTKFeedMuteButtonTarget : NSObject
@end

@implementation TTKFeedMuteButtonTarget
- (void)toggleMuteState:(UIButton *)sender {
    isGloballyMuted = !isGloballyMuted;
    [sender setTitle:(isGloballyMuted ? @"🔇" : @"🔊") forState:UIControlStateNormal];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TikTokPlusToggleMute"
                                                        object:@(isGloballyMuted)];
}
@end

static UIWindow *TTKActiveWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *window in ws.windows) {
                if (window.isKeyWindow && !window.hidden && window.alpha > 0.01) return window;
            }
            for (UIWindow *window in ws.windows) {
                if (!window.hidden && window.alpha > 0.01 && window.rootViewController) return window;
            }
        }
    }

    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow && !window.hidden && window.alpha > 0.01) return window;
    }
    return UIApplication.sharedApplication.keyWindow;
}

static void TTKInstallMuteButton(void) {
    if (!NSBundle.mainBundle.bundleIdentifier.lowercaseString.length) return;

    UIWindow *host = TTKActiveWindow();
    if (!host || !host.rootViewController) return;

    if (gMuteButton && gMuteHostWindow == host && gMuteButton.superview) {
        [host bringSubviewToFront:gMuteButton];
        return;
    }

    if (gMuteButton) {
        [gMuteButton removeFromSuperview];
        gMuteButton = nil;
    }

    if (!gMuteTarget) gMuteTarget = [TTKFeedMuteButtonTarget new];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = kMuteButtonTag;
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
    btn.layer.cornerRadius = 22.0;
    btn.clipsToBounds = YES;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = UIColor.whiteColor.CGColor;
    btn.layer.zPosition = 10000.0;
    btn.accessibilityLabel = @"TikTok video mute";
    btn.accessibilityIdentifier = @"TikTokPlusMuteButton";
    btn.titleLabel.font = [UIFont systemFontOfSize:20.0];
    [btn setTitle:(isGloballyMuted ? @"🔇" : @"🔊") forState:UIControlStateNormal];
    [btn addTarget:gMuteTarget action:@selector(toggleMuteState:) forControlEvents:UIControlEventTouchUpInside];

    [host addSubview:btn];
    gMuteButton = btn;
    gMuteHostWindow = host;

    [host bringSubviewToFront:btn];
}

static void TTKLayoutMuteButton(void) {
    if (!gMuteButton || !gMuteHostWindow) return;

    UIWindow *host = gMuteHostWindow;
    CGFloat top = MAX(60.0, host.safeAreaInsets.top + 16.0);
    gMuteButton.frame = CGRectMake(16.0, top, 44.0, 44.0);
    [host bringSubviewToFront:gMuteButton];
}

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        TTKInstallMuteButton();
        TTKLayoutMuteButton();
    });
}

- (void)layoutSubviews {
    %orig;
    if (self == gMuteHostWindow) TTKLayoutMuteButton();
}
%end

// Keep the feed video's AVPlayer-backed volume at zero while muted.
%hook IESVideoPlayer
- (void)setVolume:(float)volume {
    %orig(isGloballyMuted ? 0.0f : volume);
}
%end

%ctor {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    if (!bundleID.length) return;
    if (![bundleID containsString:@"tiktok"] && ![bundleID containsString:@"musically"]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        TTKInstallMuteButton();
        TTKLayoutMuteButton();

        // TikTok creates/replaces windows and feed views after launch, so retry
        // briefly until the active scene/window is established.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                           dispatch_get_main_queue());
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, 0),
                                  500 * NSEC_PER_MSEC,
                                  100 * NSEC_PER_MSEC);
        __block NSInteger attempts = 0;
        dispatch_source_set_event_handler(timer, ^{
            TTKInstallMuteButton();
            TTKLayoutMuteButton();
            attempts++;
            if (attempts >= 20) dispatch_source_cancel(timer);
        });
        dispatch_resume(timer);
    });
}
