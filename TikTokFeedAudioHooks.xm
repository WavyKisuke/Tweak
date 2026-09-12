#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL isGloballyMuted = YES;

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

static TTKFeedMuteButtonTarget *gMuteTarget;

static void TTKSetupMuteButton(UIView *view) {
    if (!view || view.window == nil) return;

    static NSInteger const kMuteButtonTag = 190612;
    UIButton *button = (UIButton *)[view viewWithTag:kMuteButtonTag];
    if (button && [button isKindOfClass:UIButton.class]) {
        [view bringSubviewToFront:button];
        return;
    }

    if (!gMuteTarget) gMuteTarget = [TTKFeedMuteButtonTarget new];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = kMuteButtonTag;
    btn.frame = CGRectMake(16.0, 60.0, 44.0, 44.0);
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    btn.layer.cornerRadius = 22.0;
    btn.clipsToBounds = YES;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = UIColor.whiteColor.CGColor;
    [btn setTitle:(isGloballyMuted ? @"🔇" : @"🔊") forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:20.0];
    [btn addTarget:gMuteTarget action:@selector(toggleMuteState:) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:btn];
    [view bringSubviewToFront:btn];
}

static BOOL TTKLooksLikeVideoContainer(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01 || view.window == nil) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString;
    if ([name containsString:@"video"] ||
        [name containsString:@"aweme"] ||
        [name containsString:@"feed"] ||
        [name containsString:@"player"]) return YES;

    return NO;
}

static void TTKInstallButtonOnViewTree(UIView *root) {
    if (!root) return;

    if (TTKLooksLikeVideoContainer(root)) {
        TTKSetupMuteButton(root);
        return;
    }

    for (UIView *subview in root.subviews) {
        TTKInstallButtonOnViewTree(subview);
    }
}

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (self.window && TTKLooksLikeVideoContainer(self)) {
        TTKSetupMuteButton(self);
    }
}

- (void)layoutSubviews {
    %orig;
    if (self.window && TTKLooksLikeVideoContainer(self)) {
        UIButton *button = (UIButton *)[self viewWithTag:190612];
        if (button) {
            button.frame = CGRectMake(16.0, 60.0, 44.0, 44.0);
            [self bringSubviewToFront:button];
        }
    }
}
%end

%hook UICollectionViewCell
- (void)didMoveToWindow {
    %orig;
    if (self.window) TTKSetupMuteButton(self);
}

- (void)layoutSubviews {
    %orig;
    if (self.window) {
        TTKSetupMuteButton(self);
        UIButton *button = (UIButton *)[self viewWithTag:190612];
        if (button) {
            button.frame = CGRectMake(16.0, 60.0, 44.0, 44.0);
            [self bringSubviewToFront:button];
        }
    }
}
%end

// Fallback player volume enforcement.
%hook IESVideoPlayer
- (void)setVolume:(float)volume {
    %orig(isGloballyMuted ? 0.0f : volume);
}
%end

%ctor {
    if (!NSBundle.mainBundle.bundleIdentifier.lowercaseString.length) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        TTKInstallButtonOnViewTree(UIApplication.sharedApplication.keyWindow);
    });
}
