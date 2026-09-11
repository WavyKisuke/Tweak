#import <UIKit/UIKit.h>

// Standalone mute control. This UI is intentionally independent from the
// audio-hook initialization path so it cannot disappear just because TikTok
// creates/replaces its feed window later.

@interface TTKPlusAudioTarget : NSObject
- (void)tapMute:(id)sender;
@end

static UIButton *gStandaloneMuteButton = nil;
static TTKPlusAudioTarget *gStandaloneMuteTarget = nil;
static BOOL gStandaloneMuted = NO;
static dispatch_source_t gMuteUITimer = nil;

static BOOL MUIsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *MUTopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindow *fallback = nil;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0.01 || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
                if (window.isKeyWindow) return window;
                if (!fallback) fallback = window;
            }
            if (fallback) return fallback;
        }
    }
    return nil;
}

static void MUInstallButton(void) {
    if (!MUIsTikTok()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = MUTopWindow();
        if (!window) return;

        if (!gStandaloneMuteTarget) {
            gStandaloneMuteTarget = [TTKPlusAudioTarget new];
        }

        // Reuse the button if it is already attached to this window.
        if (gStandaloneMuteButton && gStandaloneMuteButton.superview == window) {
            [window bringSubviewToFront:gStandaloneMuteButton];
            return;
        }

        [gStandaloneMuteButton removeFromSuperview];
        gStandaloneMuteButton = nil;

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        // Keep it in the same upper-right control area as HD SAVE, but above it.
        button.frame = CGRectMake(window.bounds.size.width - 102.0, 60.0, 88.0, 38.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
        button.layer.cornerRadius = 10.0;
        button.layer.masksToBounds = YES;
        button.accessibilityIdentifier = @"TikTokPlusMuteButton";
        [button setTitle:gStandaloneMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        [button addTarget:gStandaloneMuteTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];

        [window addSubview:button];
        [window bringSubviewToFront:button];
        gStandaloneMuteButton = button;
    });
}

%ctor {
    if (!MUIsTikTok()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            MUInstallButton();
        }];

        // TikTok can create/rebuild its feed window after the tweak loads.
        MUInstallButton();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MUInstallButton(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MUInstallButton(); });

        // Keep the control above TikTok's feed views. This also handles scene/window
        // replacement while the app is running.
        if (!gMuteUITimer) {
            gMuteUITimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(gMuteUITimer,
                                      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                                      (uint64_t)(1 * NSEC_PER_SEC),
                                      (uint64_t)(100 * NSEC_PER_MSEC));
            dispatch_source_set_event_handler(gMuteUITimer, ^{
                MUInstallButton();
            });
            dispatch_resume(gMuteUITimer);
        }
    });
}
