#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gPrivateTikTokMuted = NO;

static BOOL PTIsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static BOOL PTSetBool(id obj, SEL sel, BOOL value) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
    return YES;
}

static BOOL PTSetFloat(id obj, SEL sel, float value) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    ((void (*)(id, SEL, float))objc_msgSend)(obj, sel, value);
    return YES;
}

static id PTObject(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void PTMuteObject(id obj) {
    if (!obj) return;

    PTSetBool(obj, @selector(setMuted:), gPrivateTikTokMuted);
    PTSetBool(obj, @selector(setMute:), gPrivateTikTokMuted);
    PTSetBool(obj, @selector(setAudioMuted:), gPrivateTikTokMuted);

    if (gPrivateTikTokMuted) {
        PTSetFloat(obj, @selector(setVolume:), 0.0f);
        PTSetFloat(obj, @selector(setAudioVolume:), 0.0f);
        PTSetFloat(obj, @selector(setPlayerVolume:), 0.0f);
        if ([obj respondsToSelector:@selector(mute)]) {
            ((void (*)(id, SEL))objc_msgSend)(obj, @selector(mute));
        }
    }
}

static void PTScanObject(id root, NSInteger depth) {
    if (!root || depth > 3) return;
    PTMuteObject(root);

    Class cls = object_getClass(root);
    if (!cls) return;

    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *type = ivar_getTypeEncoding(ivar);
        if (!type || type[0] != '@') continue;
        id child = object_getIvar(root, ivar);
        if (!child || child == root) continue;

        if ([child isKindOfClass:[NSArray class]]) {
            for (id item in child) PTScanObject(item, depth + 1);
        } else if ([child isKindOfClass:[NSDictionary class]]) {
            for (id item in [child allValues]) PTScanObject(item, depth + 1);
        } else {
            PTScanObject(child, depth + 1);
        }
    }
    free(ivars);
}

static void PTApplyToCurrentTikTokPlayers(void) {
    if (!PTIsTikTok()) return;
    Class controllerClass = NSClassFromString(@"AWEPlayVideoPlayerController");
    if (controllerClass) {
        // Existing controller instances are reached again through the feed lifecycle hooks.
        // The notification also causes newly-created players to be handled on their next play.
    }
}

%hook AWEPlayVideoPlayerController
- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok()) PTScanObject(player, 0);
}

- (void)play {
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        id player = PTObject(self, @selector(player));
        if (!player) player = PTObject(self, @selector(currentPlayer));
        PTApplyToPlayerArgument(player);
        PTMuteObject(self);
    }
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        id player = PTObject(self, @selector(player));
        if (!player) player = PTObject(self, @selector(currentPlayer));
        PTApplyToPlayerArgument(player);
        PTMuteObject(self);
    }
}

- (void)setVolume:(float)volume {
    if (PTIsTikTok() && gPrivateTikTokMuted) volume = 0.0f;
    %orig;
}

- (void)setMuted:(BOOL)muted {
    if (PTIsTikTok() && gPrivateTikTokMuted) muted = YES;
    %orig;
}
%end

%hook AWEFeedCellViewController
- (void)containerDidFullyDisplayWithReason:(NSInteger)reason {
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTScanObject(self, 0);
}

- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok()) PTScanObject(player, 0);
}
%end

%ctor {
    if (!PTIsTikTok()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteStateChanged"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            NSNumber *value = note.userInfo[@"muted"];
            gPrivateTikTokMuted = value.boolValue;

            if (gPrivateTikTokMuted) {
                // Apply immediately to any controller objects reachable from the current UI.
                for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                    if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                    for (UIWindow *window in scene.windows) {
                        if (!window.hidden && window.rootViewController) PTScanObject(window.rootViewController, 0);
                    }
                }
            }
        }];
    });
}
