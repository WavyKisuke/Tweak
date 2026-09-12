#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void TikTokPlusInstallMuteButton(void);
static BOOL gAdBlockEnabled = YES;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindow *TopWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) return w;
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

// Remove the old HD/SAVE control even if an older injected dylib created it.
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

%ctor {
    if (!IsTikTok()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TikTokPlusInstallMuteButton();
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 250 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        TikTokPlusInstallMuteButton();
        UIWindow *w = TopWindow();
        if (w && w.rootViewController.view) {
            RemoveLegacyHDButton(w.rootViewController.view);
            if (gAdBlockEnabled) ScanForAds(w.rootViewController.view);
        }
    });
    dispatch_resume(timer);
}
