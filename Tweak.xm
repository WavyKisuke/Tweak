#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void TikTokPlusInstallMuteButton(void);
static BOOL gAdBlockEnabled = YES;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindow *TopWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal && w.rootViewController && w.isKeyWindow) return w;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal && w.rootViewController) return w;
    }
    return nil;
}

static BOOL TextLooksLikeAd(NSString *text) {
    if (!text.length) return NO;
    NSString *s = text.lowercaseString;
    NSArray *markers = @[@"sponsored", @"promoted", @"advertisement", @"paid partnership", @"ad ·", @"ad •"];
    for (NSString *m in markers) if ([s containsString:m]) return YES;
    return NO;
}
static BOOL ClassLooksLikeAd(UIView *v) {
    NSString *n = NSStringFromClass(v.class).lowercaseString;
    NSArray *tokens = @[@"sponsored", @"advertisement", @"promoted", @"adcell", @"adview", @"adcontainer", @"awead", @"ttkad"];
    for (NSString *t in tokens) if ([n containsString:t]) return YES;
    return NO;
}
static BOOL ViewLooksLikeAd(UIView *v) {
    if (ClassLooksLikeAd(v)) return YES;
    if ([v isKindOfClass:UILabel.class] && TextLooksLikeAd(((UILabel *)v).text)) return YES;
    if ([v isKindOfClass:UIButton.class] && TextLooksLikeAd([((UIButton *)v) titleForState:UIControlStateNormal])) return YES;
    return TextLooksLikeAd(v.accessibilityLabel);
}
static void ScanForAds(UIView *root) {
    if (!gAdBlockEnabled || !root.window) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (ViewLooksLikeAd(v)) v.hidden = YES;
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void RemoveLegacyHDButton(UIView *root) {
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:UIButton.class]) {
            UIButton *b=(UIButton *)v;
            NSString *title=[b titleForState:UIControlStateNormal].lowercaseString ?: @"";
            NSString *access=b.accessibilityLabel.lowercaseString ?: @"";
            BOOL oldHD=(title.length && ([title isEqualToString:@"hd"] || [title containsString:@"hd save"] || [title containsString:@"save hd"] || [access containsString:@"hd save"]));
            if (oldHD) { [b removeFromSuperview]; continue; }
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void RefreshTikTokUI(void) {
    if (!IsTikTok()) return;
    TikTokPlusInstallMuteButton();
    UIWindow *w = TopWindow();
    if (w && w.rootViewController.view) {
        RemoveLegacyHDButton(w.rootViewController.view);
        if (gAdBlockEnabled) ScanForAds(w.rootViewController.view);
    }
}

%ctor {
    if (!IsTikTok()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ RefreshTikTokUI(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RefreshTikTokUI(); });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ RefreshTikTokUI(); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ RefreshTikTokUI(); }];
        if (@available(iOS 13.0, *)) [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ RefreshTikTokUI(); }];
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 200), NSEC_PER_MSEC * 500, NSEC_PER_MSEC * 100);
    __block int attempts = 0;
    dispatch_source_set_event_handler(timer, ^{
        RefreshTikTokUI();
        if (++attempts >= 30) {
            dispatch_source_cancel(timer);
            dispatch_source_t steady = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(steady, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_MSEC * 100);
            dispatch_source_set_event_handler(steady, ^{ RefreshTikTokUI(); });
            dispatch_resume(steady);
        }
    });
    dispatch_resume(timer);
}
