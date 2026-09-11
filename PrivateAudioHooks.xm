#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gPrivateTikTokMuted = NO;
static BOOL PTIsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }
static BOOL PTSetBool(id o, SEL s, BOOL v) { if (!o || ![o respondsToSelector:s]) return NO; ((void(*)(id,SEL,BOOL))objc_msgSend)(o,s,v); return YES; }
static BOOL PTSetFloat(id o, SEL s, float v) { if (!o || ![o respondsToSelector:s]) return NO; ((void(*)(id,SEL,float))objc_msgSend)(o,s,v); return YES; }
static id PTObject(id o, SEL s) { if (!o || ![o respondsToSelector:s]) return nil; return ((id(*)(id,SEL))objc_msgSend)(o,s); }

static void PTMuteObject(id obj) {
    if (!obj) return;
    PTSetBool(obj,@selector(setMuted:),gPrivateTikTokMuted);
    PTSetBool(obj,@selector(setMute:),gPrivateTikTokMuted);
    PTSetBool(obj,@selector(setAudioMuted:),gPrivateTikTokMuted);
    if (gPrivateTikTokMuted) {
        PTSetFloat(obj,@selector(setVolume:),0.0f);
        PTSetFloat(obj,@selector(setAudioVolume:),0.0f);
        PTSetFloat(obj,@selector(setPlayerVolume:),0.0f);
        if ([obj respondsToSelector:@selector(mute)]) ((void(*)(id,SEL))objc_msgSend)(obj,@selector(mute));
    }
}

static void PTScanObject(id root, NSInteger depth) {
    if (!root || depth > 3) return;
    PTMuteObject(root);
    Class cls = object_getClass(root);
    if (!cls) return;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls,&count);
    for (unsigned int i=0;i<count;i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id child = object_getIvar(root,ivars[i]);
        if (!child || child == root) continue;
        if ([child isKindOfClass:[NSArray class]]) { for (id x in child) PTScanObject(x,depth+1); }
        else if ([child isKindOfClass:[NSSet class]]) { for (id x in child) PTScanObject(x,depth+1); }
        else if ([child isKindOfClass:[NSDictionary class]]) { for (id x in [child allValues]) PTScanObject(x,depth+1); }
        else PTScanObject(child,depth+1);
    }
    free(ivars);
}

static void PTApplyToPlayer(id player) { if (player) PTScanObject(player,0); }

%hook AWEPlayVideoPlayerController
- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTApplyToPlayer(player);
}
- (void)play {
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        id p = PTObject(self,@selector(player));
        if (!p) p = PTObject(self,@selector(currentPlayer));
        PTApplyToPlayer(p);
        PTMuteObject(self);
    }
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) {
        id p = PTObject(self,@selector(player));
        if (!p) p = PTObject(self,@selector(currentPlayer));
        PTApplyToPlayer(p);
        PTMuteObject(self);
    }
}
- (void)setVolume:(float)v { if (PTIsTikTok() && gPrivateTikTokMuted) v=0.0f; %orig; }
- (void)setMuted:(BOOL)v { if (PTIsTikTok() && gPrivateTikTokMuted) v=YES; %orig; }
%end

%hook AWEFeedCellViewController
- (void)containerDidFullyDisplayWithReason:(NSInteger)reason {
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTScanObject(self,0);
}
- (void)playerWillLoopPlaying:(id)player {
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTApplyToPlayer(player);
}
%end

%ctor {
    if (!PTIsTikTok()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            gPrivateTikTokMuted = [note.userInfo[@"muted"] boolValue];
            if (!gPrivateTikTokMuted) return;
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                for (UIWindow *window in scene.windows) {
                    if (!window.hidden && window.rootViewController) PTScanObject(window.rootViewController,0);
                }
            }
        }];
    });
}
