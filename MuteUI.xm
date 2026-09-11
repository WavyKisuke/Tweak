#import <UIKit/UIKit.h>

// Standalone UI initializer for the mute control.
// It deliberately does not depend on AudioHooks.xm's static UI state.

@interface TTKPlusAudioTarget : NSObject
- (void)tapMute:(id)sender;
@end

static UIButton *gStandaloneMuteButton = nil;
static TTKPlusAudioTarget *gStandaloneMuteTarget = nil;
static BOOL gStandaloneMuted = NO;

static BOOL MUIsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *MUTopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    if (window.isKeyWindow) return window;
                }
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    return window;
                }
            }
        }
    }
    return nil;
}

static void MUInstallButton(void) {
    if (!MUIsTikTok()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = MUTopWindow();
        if (!window) return;

        if (gStandaloneMuteButton && gStandaloneMuteButton.superview == window) {
            return;
        }

        // If the button was recreated by a new scene/window, remove the stale instance.
        [gStandaloneMuteButton removeFromSuperview];
        gStandaloneMuteButton = nil;

        if (!gStandaloneMuteTarget) {
            gStandaloneMuteTarget = [TTKPlusAudioTarget new];
        }

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(window.bounds.size.width - 102.0, 60.0, 88.0, 38.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        button.layer.cornerRadius = 10.0;
        button.layer.masksToBounds = YES;
        button.accessibilityIdentifier = @"TikTokPlusMuteButton";
        [button setTitle:@"MUTE" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        [button addTarget:gStandaloneMuteTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];

        // Keep the standalone UI state in sync with the action that actually performs the mute.
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            gStandaloneMuted = !gStandaloneMuted;
            [button setTitle:gStandaloneMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
        }] forControlEvents:UIControlEventTouchUpInside];

        [window addSubview:button];
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

        // TikTok may not have created its first UIWindow when the dylib loads.
        MUInstallButton();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MUInstallButton();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MUInstallButton();
        });
    });
}
