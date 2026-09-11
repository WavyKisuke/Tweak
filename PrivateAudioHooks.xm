#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

void TikTokPlusInstallMuteButton(void);

static BOOL gPrivateTikTokMuted = NO;
static __weak id gCurrentFeedCell;
static __weak id gCurrentPlayerController;
static __weak id gCurrentPlayer;
static NSMutableDictionary *gOriginalIMPs;

static BOOL PTIsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static NSString *PTKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(sel)];
}

static IMP PTOriginal(Class cls, SEL sel) {
    NSValue *value = gOriginalIMPs[PTKey(cls, sel)];
    return value ? (IMP)value.pointerValue : NULL;
}

static void PTForceObject(id object) {
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
    if (!root || depth > 4 || !gPrivateTikTokMuted) return;
    PTForceObject(root);
    Class cls = object_getClass(root);
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls,&count);
    for (unsigned int i=0;i<count;i++) {
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

static void PTInstall(Class cls, SEL sel, IMP replacement) {
    if (!cls || !replacement) return;
    Method method = class_getInstanceMethod(cls,sel);
    if (!method) return;
    NSString *key = PTKey(cls,sel);
    if (gOriginalIMPs[key]) return;
    gOriginalIMPs[key] = [NSValue valueWithPointer:method_getImplementation(method)];
    method_setImplementation(method,replacement);
}

static void PTSetBool(id self, SEL sel, BOOL value) {
    if (gPrivateTikTokMuted) value = YES;
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL,BOOL))orig)(self,sel,value);
}

static void PTSetFloat(id self, SEL sel, float value) {
    if (gPrivateTikTokMuted) value = 0.0f;
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL,float))orig)(self,sel,value);
}

static void PTMute(id self, SEL sel) {
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL))orig)(self,sel);
}

static void PTPlayerLoop(id self, SEL sel, id player) {
    gCurrentPlayerController = self;
    gCurrentPlayer = player;
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL,id))orig)(self,sel,player);
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) { PTForceObject(self); PTScanObject(player,0); }
    }
}

static void PTFeedDisplay(id self, SEL sel, NSInteger reason) {
    gCurrentFeedCell = self;
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL,NSInteger))orig)(self,sel,reason);
    if (PTIsTikTok()) {
        TikTokPlusInstallMuteButton();
        if (gPrivateTikTokMuted) PTScanObject(self,0);
    }
}

static void PTControllerPlay(id self, SEL sel) {
    gCurrentPlayerController = self;
    if (PTIsTikTok() && gPrivateTikTokMuted) PTForceObject(self);
    IMP orig = PTOriginal(object_getClass(self),sel);
    if (orig) ((void(*)(id,SEL))orig)(self,sel);
    if (PTIsTikTok() && gPrivateTikTokMuted) PTScanObject(self,0);
}

static void InstallPrivateHooks(void) {
    Class controller = NSClassFromString(@"AWEPlayVideoPlayerController");
    Class cell = NSClassFromString(@"AWEFeedCellViewController");
    if (!controller && !cell) return;

    PTInstall(controller,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);
    PTInstall(controller,@selector(play),(IMP)PTControllerPlay);
    PTInstall(cell,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);
    PTInstall(cell,@selector(containerDidFullyDisplayWithReason:),(IMP)PTFeedDisplay);

    NSArray *boolSelectors = @[@"setMuted:",@"setMute:",@"setAudioMuted:"];
    NSArray *floatSelectors = @[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:"];
    NSArray *voidSelectors = @[@"mute"];
    if (controller) {
        for (NSString *name in boolSelectors) PTInstall(controller,NSSelectorFromString(name),(IMP)PTSetBool);
        for (NSString *name in floatSelectors) PTInstall(controller,NSSelectorFromString(name),(IMP)PTSetFloat);
        for (NSString *name in voidSelectors) PTInstall(controller,NSSelectorFromString(name),(IMP)PTMute);
    }
    if (cell) {
        for (NSString *name in boolSelectors) PTInstall(cell,NSSelectorFromString(name),(IMP)PTSetBool);
        for (NSString *name in floatSelectors) PTInstall(cell,NSSelectorFromString(name),(IMP)PTSetFloat);
        for (NSString *name in voidSelectors) PTInstall(cell,NSSelectorFromString(name),(IMP)PTMute);
    }
}

static void PTApplyCurrent(void) {
    if (!gPrivateTikTokMuted) return;
    PTForceObject(gCurrentPlayer);
    PTForceObject(gCurrentPlayerController);
    if ([gCurrentPlayerController respondsToSelector:@selector(player)]) PTForceObject(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));
    if ([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]) PTForceObject(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));
    PTScanObject(gCurrentFeedCell,0);
    PTScanObject(gCurrentPlayerController,0);
    PTScanObject(gCurrentPlayer,0);
}

%ctor {
    if (!PTIsTikTok()) return;
    gOriginalIMPs = [NSMutableDictionary dictionary];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            gPrivateTikTokMuted = [note.userInfo[@"muted"] boolValue];
            if (gPrivateTikTokMuted) PTApplyCurrent();
        }];
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{ InstallPrivateHooks(); TikTokPlusInstallMuteButton(); if (gPrivateTikTokMuted) PTApplyCurrent(); });
    dispatch_resume(timer);
}
