#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

void TikTokPlusInstallMuteButton(void);

static BOOL gPrivateTikTokMuted = NO;
static __weak id gCurrentFeedCell;
static __weak id gCurrentPlayerController;
static __weak id gCurrentPlayer;

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
    if (!root || depth > 5) return;
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

static IMP gSetVolumeOrig;
static IMP gSetMutedOrig;
static IMP gSetAudioVolumeOrig;
static IMP gSetAudioMutedOrig;
static IMP gSetPlayerVolumeOrig;
static IMP gMuteOrig;

static void PTSetVolume(id self, SEL sel, float value) {
    if (PTIsTikTok() && gPrivateTikTokMuted) value = 0.0f;
    if (gSetVolumeOrig) ((void(*)(id,SEL,float))gSetVolumeOrig)(self,sel,value);
}

static void PTSetMuted(id self, SEL sel, BOOL value) {
    if (PTIsTikTok() && gPrivateTikTokMuted) value = YES;
    if (gSetMutedOrig) ((void(*)(id,SEL,BOOL))gSetMutedOrig)(self,sel,value);
}

static void PTSetAudioVolume(id self, SEL sel, float value) {
    if (PTIsTikTok() && gPrivateTikTokMuted) value = 0.0f;
    if (gSetAudioVolumeOrig) ((void(*)(id,SEL,float))gSetAudioVolumeOrig)(self,sel,value);
}

static void PTSetAudioMuted(id self, SEL sel, BOOL value) {
    if (PTIsTikTok() && gPrivateTikTokMuted) value = YES;
    if (gSetAudioMutedOrig) ((void(*)(id,SEL,BOOL))gSetAudioMutedOrig)(self,sel,value);
}

static void PTSetPlayerVolume(id self, SEL sel, float value) {
    if (PTIsTikTok() && gPrivateTikTokMuted) value = 0.0f;
    if (gSetPlayerVolumeOrig) ((void(*)(id,SEL,float))gSetPlayerVolumeOrig)(self,sel,value);
}

static void PTMute(id self, SEL sel) {
    if (gMuteOrig) ((void(*)(id,SEL))gMuteOrig)(self,sel);
}

static void PTSwizzleSelector(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !class_getInstanceMethod(cls,sel) || *original) return;
    Method method = class_getInstanceMethod(cls,sel);
    *original = method_getImplementation(method);
    method_setImplementation(method,replacement);
}

static void PTInstallPlayerAudioHooks(void) {
    Class cls = NSClassFromString(@"AWEPlayVideoPlayerController");
    if (!cls) return;
    PTSwizzleSelector(cls,@selector(setVolume:),(IMP)PTSetVolume,&gSetVolumeOrig);
    PTSwizzleSelector(cls,@selector(setMuted:),(IMP)PTSetMuted,&gSetMutedOrig);
    PTSwizzleSelector(cls,@selector(setAudioVolume:),(IMP)PTSetAudioVolume,&gSetAudioVolumeOrig);
    PTSwizzleSelector(cls,@selector(setAudioMuted:),(IMP)PTSetAudioMuted,&gSetAudioMutedOrig);
    PTSwizzleSelector(cls,@selector(setPlayerVolume:),(IMP)PTSetPlayerVolume,&gSetPlayerVolumeOrig);
    PTSwizzleSelector(cls,@selector(mute),(IMP)PTMute,&gMuteOrig);
}

static void PTApplyCurrentPlayer(void) {
    if (!gPrivateTikTokMuted) return;
    PTInstallPlayerAudioHooks();
    PTMuteObject(gCurrentPlayer);
    PTMuteObject(gCurrentPlayerController);
    PTMuteObject(PTObject(gCurrentPlayerController,@selector(player)));
    PTMuteObject(PTObject(gCurrentPlayerController,@selector(currentPlayer)));
    PTScanObject(gCurrentFeedCell,0);
    PTScanObject(gCurrentPlayerController,0);
    PTScanObject(gCurrentPlayer,0);
}

%hook AWEPlayVideoPlayerController
- (void)playerWillLoopPlaying:(id)player {
    gCurrentPlayerController = self;
    gCurrentPlayer = player;
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTApplyCurrentPlayer();
    }
}
- (void)play {
    gCurrentPlayerController = self;
    id player = PTObject(self,@selector(player));
    if (!player) player = PTObject(self,@selector(currentPlayer));
    if (player) gCurrentPlayer = player;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTApplyCurrentPlayer();
    %orig;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTApplyCurrentPlayer();
}
%end

%hook AWEFeedCellViewController
- (void)containerDidFullyDisplayWithReason:(NSInteger)reason {
    gCurrentFeedCell = self;
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        PTInstallPlayerAudioHooks();
        if (gPrivateTikTokMuted) PTApplyCurrentPlayer();
    }
}
- (void)playerWillLoopPlaying:(id)player {
    gCurrentFeedCell = self;
    gCurrentPlayer = player;
    %orig;
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTApplyCurrentPlayer();
    }
}
%end

%ctor {
    if (!PTIsTikTok()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            gPrivateTikTokMuted = [note.userInfo[@"muted"] boolValue];
            PTInstallPlayerAudioHooks();
            if (gPrivateTikTokMuted) PTApplyCurrentPlayer();
        }];
    });
}
