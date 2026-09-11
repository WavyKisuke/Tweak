#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

void TikTokPlusInstallMuteButton(void);

static BOOL gPrivateTikTokMuted = NO;

static BOOL PTIsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static id PTObject(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object, selector);
}

static void PTMuteObject(id object) {
    if (!object || !gPrivateTikTokMuted) return;
    if ([object respondsToSelector:@selector(setMuted:)]) ((void(*)(id,SEL,BOOL))objc_msgSend)(object,@selector(setMuted:),YES);
    if ([object respondsToSelector:@selector(setMute:)]) ((void(*)(id,SEL,BOOL))objc_msgSend)(object,@selector(setMute:),YES);
    if ([object respondsToSelector:@selector(setAudioMuted:)]) ((void(*)(id,SEL,BOOL))objc_msgSend)(object,@selector(setAudioMuted:),YES);
    if ([object respondsToSelector:@selector(setVolume:)]) ((void(*)(id,SEL,float))objc_msgSend)(object,@selector(setVolume:),0.0f);
    if ([object respondsToSelector:@selector(setAudioVolume:)]) ((void(*)(id,SEL,float))objc_msgSend)(object,@selector(setAudioVolume:),0.0f);
    if ([object respondsToSelector:@selector(setPlayerVolume:)]) ((void(*)(id,SEL,float))objc_msgSend)(object,@selector(setPlayerVolume:),0.0f);
    if ([object respondsToSelector:@selector(mute)]) ((void(*)(id,SEL))objc_msgSend)(object,@selector(mute));
}

static void PTScanObject(id root, NSInteger depth) {
    if (!root || depth > 3) return;
    PTMuteObject(root);
    Class cls = object_getClass(root);
    if (!cls) return;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls,&count);
    for (unsigned int i=0; i<count; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id child = object_getIvar(root,ivars[i]);
        if (!child || child == root) continue;
        if ([child isKindOfClass:[NSArray class]]) {
            for (id x in child) PTScanObject(x,depth+1);
        } else if ([child isKindOfClass:[NSSet class]]) {
            for (id x in child) PTScanObject(x,depth+1);
        } else if ([child isKindOfClass:[NSDictionary class]]) {
            for (id x in [child allValues]) PTScanObject(x,depth+1);
        } else {
            PTScanObject(child,depth+1);
        }
    }
    free(ivars);
}

%hook AWEPlayVideoPlayerController
- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTScanObject(player,0);
    }
}
- (void)play {
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        PTMuteObject(self);
        PTScanObject(PTObject(self,@selector(player)),0);
        PTScanObject(PTObject(self,@selector(currentPlayer)),0);
    }
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        PTMuteObject(self);
        PTScanObject(PTObject(self,@selector(player)),0);
        PTScanObject(PTObject(self,@selector(currentPlayer)),0);
    }
}
%end

%hook AWEFeedCellViewController
- (void)containerDidFullyDisplayWithReason:(NSInteger)reason {
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTScanObject(self,0);
    }
}
- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTScanObject(player,0);
    }
}
%end

%ctor {
    if (!PTIsTikTok()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            gPrivateTikTokMuted = [note.userInfo[@"muted"] boolValue];
            if (!gPrivateTikTokMuted) return;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (!window.hidden && window.rootViewController) PTScanObject(window.rootViewController,0);
                }
            }
        }];
    });
}
