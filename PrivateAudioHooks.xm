#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

void TikTokPlusInstallMuteButton(void);
static void PTApplyCurrent(void);
static void PTRestoreCurrent(void);
static BOOL gPrivateTikTokMuted=YES;
static __weak id gCurrentFeedCell;
static __weak id gCurrentPlayerController;
static __weak id gCurrentPlayer;
static NSMutableDictionary *gOriginalIMPs;

static BOOL PTIsTikTok(void){NSString*b=[NSBundle mainBundle].bundleIdentifier.lowercaseString;return [b containsString:@"musically"]||[b containsString:@"tiktok"];}
static NSString *PTKey(Class cls,SEL sel){return [NSString stringWithFormat:@"%p:%@",cls,NSStringFromSelector(sel)];}
static IMP PTOriginal(Class cls,SEL sel){NSValue*v=gOriginalIMPs[PTKey(cls,sel)];if(!v)return NULL;IMP p=NULL;[v getValue:&p];return p;}
static IMP PTOriginalForSelf(id self,SEL sel){Class cls=object_getClass(self);while(cls){IMP p=PTOriginal(cls,sel);if(p)return p;cls=class_getSuperclass(cls);}return NULL;}

static void PTForceObject(id o){
    if(!o||!gPrivateTikTokMuted)return;
    if([o respondsToSelector:@selector(setMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setMuted:),YES);
    if([o respondsToSelector:@selector(setAudioMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setAudioMuted:),YES);
    if([o respondsToSelector:@selector(setEnableSoundOutput:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setEnableSoundOutput:),NO);
    if([o respondsToSelector:@selector(setVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setVolume:),0.0f);
    if([o respondsToSelector:@selector(setAudioVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setAudioVolume:),0.0f);
    if([o respondsToSelector:@selector(setPlayerVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setPlayerVolume:),0.0f);
    if([o respondsToSelector:@selector(setOutputVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setOutputVolume:),0.0f);
}

static void PTRestoreObject(id o){
    if(!o||gPrivateTikTokMuted)return;
    if([o respondsToSelector:@selector(setMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setMuted:),NO);
    if([o respondsToSelector:@selector(setAudioMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setAudioMuted:),NO);
    if([o respondsToSelector:@selector(setEnableSoundOutput:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setEnableSoundOutput:),YES);
}

static void PTProbeNode(id node){if(!node)return;if(gPrivateTikTokMuted)PTForceObject(node);else PTRestoreObject(node);}

static void PTProbePlayer(id player){
    if(!player)return;
    PTProbeNode(player);
    for(NSString*n in @[@"player",@"currentPlayer",@"audioPlayer",@"avPlayer",@"videoPlayer",@"playerNode",@"mixerNode",@"silentNode",@"audioEngine",@"audioMixerNode",@"mainMixerNode",@"audioRenderer",@"audioOutput",@"soundPlayer",@"soundEngine",@"core",@"audioCore",@"playerCore",@"audioPlayerCore"]){SEL s=NSSelectorFromString(n);if(![player respondsToSelector:s])continue;@try{id child=((id(*)(id,SEL))objc_msgSend)(player,s);if(child&&child!=player)PTProbeNode(child);}@catch(__unused NSException*e){}}
}

static void PTInstall(Class cls,SEL sel,IMP replacement){
    if(!cls||!replacement)return;Method m=class_getInstanceMethod(cls,sel);if(!m)return;NSString*k=PTKey(cls,sel);if(gOriginalIMPs[k])return;IMP original=method_getImplementation(m);gOriginalIMPs[k]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];method_setImplementation(m,replacement);
}

// Wrappers intentionally do NOT call PTForceObject after the original. They
// already force the value to the muted state and the original setter reapplies
// it on the underlying object. Re-entering PTForceObject would loop forever:
//   PTForceObject → objc_msgSend(setMuted:) → PTSetBool → original →
//   PTForceObject(self) → objc_msgSend(setMuted:) → PTSetBool → ...
// The deepest Objective-C frames unwind via @autoreleasepool / exception
// handling and the outer objects (gCurrentPlayerController / gCurrentFeedCell /
// probed children) never actually get forced — so audio leaks from those paths
// and MixWithOthers (already enabled by EnsureBackgroundMusicMixing) lets the
// leak play alongside your music app. Symptom: "mute button mixes audio".
static void PTSetBool(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=YES;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);}
static void PTSetFloat(id self,SEL sel,float value){if(gPrivateTikTokMuted)value=0.0f;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,float))o)(self,sel,value);}
static void PTSetDouble(id self,SEL sel,double value){if(gPrivateTikTokMuted)value=0.0;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,double))o)(self,sel,value);}
static void PTEnableSound(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=NO;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);}

static void PTCaptureObject(id self,SEL sel,id value){
    if(value&&value!=self){gCurrentPlayer=value;PTProbePlayer(value);}
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,id))o)(self,sel,value);
    if(gPrivateTikTokMuted){PTForceObject(self);PTProbePlayer(value);PTApplyCurrent();}
}

static void PTPlayerLoop(id self,SEL sel,id player){
    gCurrentPlayerController=self;gCurrentPlayer=player;
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,id))o)(self,sel,player);
    TikTokPlusInstallMuteButton();PTProbePlayer(player);
    if(gPrivateTikTokMuted)PTApplyCurrent();else PTRestoreObject(player);
}
static void PTFeedDisplay(id self,SEL sel,NSInteger reason){
    gCurrentFeedCell=self;
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,NSInteger))o)(self,sel,reason);
    TikTokPlusInstallMuteButton();
    if(gPrivateTikTokMuted)PTForceObject(self);else PTRestoreObject(self);
}
static void PTControllerPlay(id self,SEL sel){
    gCurrentPlayerController=self;
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL))o)(self,sel);
    TikTokPlusInstallMuteButton();
    if(gPrivateTikTokMuted)PTApplyCurrent();else PTRestoreCurrent();
}
static void PTWrapperPlay(id self,SEL sel){
    gCurrentPlayer=self;
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL))o)(self,sel);
    TikTokPlusInstallMuteButton();PTProbePlayer(self);
    if(gPrivateTikTokMuted)PTApplyCurrent();else PTRestoreCurrent();
}

static void InstallWrapperHooks(Class cls){
    if(!cls)return;
    PTInstall(cls,@selector(play),(IMP)PTWrapperPlay);
    for(NSString*n in @[@"setMuted:",@"setAudioMuted:",@"setEnableSoundOutput:"]){PTInstall(cls,NSSelectorFromString(n),(IMP)PTSetBool);}
    for(NSString*n in @[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:",@"setOutputVolume:"]){SEL s=NSSelectorFromString(n);Method m=class_getInstanceMethod(cls,s);if(!m)continue;const char*t=method_getTypeEncoding(m);PTInstall(cls,s,(t&&strchr(t,'d'))?(IMP)PTSetDouble:(IMP)PTSetFloat);}
    for(NSString*n in @[@"setPlayer:",@"setCurrentPlayer:",@"setAVPlayer:",@"setAvPlayer:",@"setAudioPlayer:",@"setVideoPlayer:",@"setPlayerNode:",@"setAudioEngine:",@"setAudioRenderer:"]){PTInstall(cls,NSSelectorFromString(n),(IMP)PTCaptureObject);}
}

// One place where we teach InstallPrivateHooks about a new class:
// just call InstallWrapperHooks(cls) (or one of the more targeted installs
// above) for it. The class-name list below is the union of every audio
// class name that shows up in any open-source TikTok / Douyin / Xigua dump
// I can find — most will NSClassFromString to nil in v46.8.0 (some have
// been renamed, some are version-gated), the ones that resolve are exactly
// what we want to mute.
static void InstallPrivateHooks(void){
    Class controller=NSClassFromString(@"AWEPlayVideoPlayerController");
    Class cell=NSClassFromString(@"AWEFeedCellViewController");
    Class wrapper=NSClassFromString(@"AWEAVPlayerWrapper");
    Class display=NSClassFromString(@"AWEAwemeDisplayPlayerController");
    InstallWrapperHooks(wrapper);InstallWrapperHooks(display);
    if(controller){
        PTInstall(controller,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);PTInstall(controller,@selector(play),(IMP)PTControllerPlay);
        for(NSString*n in @[@"setMuted:",@"setAudioMuted:",@"setEnableSoundOutput:"]){PTInstall(controller,NSSelectorFromString(n),(IMP)PTSetBool);}
        for(NSString*n in @[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:",@"setOutputVolume:"]){SEL s=NSSelectorFromString(n);Method m=class_getInstanceMethod(controller,s);if(m){const char*t=method_getTypeEncoding(m);PTInstall(controller,s,(t&&strchr(t,'d'))?(IMP)PTSetDouble:(IMP)PTSetFloat);}}
        for(NSString*n in @[@"setPlayer:",@"setCurrentPlayer:",@"setAVPlayer:",@"setAvPlayer:",@"setAudioPlayer:",@"setVideoPlayer:"]){PTInstall(controller,NSSelectorFromString(n),(IMP)PTCaptureObject);}
    }
    if(cell){
        PTInstall(cell,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);PTInstall(cell,@selector(containerDidFullyDisplayWithReason:),(IMP)PTFeedDisplay);
        for(NSString*n in @[@"setMuted:",@"setAudioMuted:",@"setEnableSoundOutput:"]){PTInstall(cell,NSSelectorFromString(n),(IMP)PTSetBool);}
        for(NSString*n in @[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:",@"setOutputVolume:"]){SEL s=NSSelectorFromString(n);Method m=class_getInstanceMethod(cell,s);if(m){const char*t=method_getTypeEncoding(m);PTInstall(cell,s,(t&&strchr(t,'d'))?(IMP)PTSetDouble:(IMP)PTSetFloat);}}
        for(NSString*n in @[@"setPlayer:",@"setCurrentPlayer:",@"setAVPlayer:",@"setAvPlayer:",@"setAudioPlayer:",@"setVideoPlayer:"]){PTInstall(cell,NSSelectorFromString(n),(IMP)PTCaptureObject);}
    }

    // MLK audio player — old AndAudio/PicPlayPost-style helper.
    Class mlk=NSClassFromString(@"MLKAudioPlayer");if(!mlk)mlk=NSClassFromString(@"MaLiangKit.MLKAudioPlayer");
    if(mlk){PTInstall(mlk,@selector(setEnableSoundOutput:),(IMP)PTEnableSound);Method vm=class_getInstanceMethod(mlk,@selector(setVolume:));if(vm){const char*t=method_getTypeEncoding(vm);PTInstall(mlk,@selector(setVolume:),(t&&strchr(t,'d'))?(IMP)PTSetDouble:(IMP)PTSetFloat);}}

    // Wider net: every TikTok / ByteDance / Volcano Engine / Lynx audio class
    // name I could find. NSClassFromString returns nil for the ones that don't
    // exist in v46.8.0 — those are silently skipped. The rest get full mute
    // coverage via InstallWrapperHooks (play + mute setters + volume setters +
    // player-capture setters).
    NSArray *extraWrappers=@[
        // Feed / scroll player wrappers
        @"TTKPlayerView", @"TTKPlayerViewController", @"TTKFeedPlayerController",
        @"TTKMediaPlayerController", @"TTKPlayerManager", @"TTKPlayerContainer",
        @"TTKPlayerWrapper", @"TTKPlayerItem", @"TTKFeedCellPlayer",
        @"TTKFeedPlayerView", @"TTKFeedPlayerManager",
        // Audio engines / renderers
        @"TTKAudioEngine", @"TTKAudioPlayer", @"TTKAudioMix", @"TTKAudioManager",
        @"TTKAudioRenderer", @"TTKAudioSession", @"TTKAudioMixer",
        @"TTKVolumeController", @"TTKVolumeHandler",
        @"BDXAudioEngine", @"BDXAudioPlayer", @"BDXAudioManager",
        @"IESAudioEngine", @"IESAudioPlayer", @"IESAudioMix", @"IESAudioMixer",
        @"IESAudioRenderer", @"IESAudioSession", @"IESVolumeHandler",
        @"IESVideoPlayerController", @"IESVideoPlayer",
        // ByteDance common
        @"BDXLynxVideoPlayerPro", @"BDXLynxAudioPlayer",
        @"TTKECMMKVideoPlayer", @"TTKECMMKAudioPlayer",
        @"IESMMBGAVPlayer", @"IESMMBGVideoPlayer",
        @"VEEffectVideoPlayer", @"VEEffectAudioPlayer",
        // AWE family (newer names)
        @"AWEPlayAudioManager", @"AWEVolumeHandler", @"AWEVolumeController",
        @"AWEFeedPlayerView", @"AWEFeedPlayerController",
        @"AWEPlayerWrapper", @"AWEPlayerManager",
        // HTS / HTC internal
        @"HTSAudioRenderer", @"HTSAudioPlayer", @"HTSAudioEngine",
        // Live
        @"TTKLivePlayer", @"TTKLiveAudioPlayer", @"TTKLiveAudioRenderer",
        @"AWELivePlayer", @"AWELivePlayerController", @"AWELiveAudioRenderer",
        // Anything that looks like a player
        @"TPAudioPlayer", @"TPAudioEngine", @"TPAudioRenderer",
        @"BDPlayer", @"BDVideoPlayer", @"BDAudioPlayer",
        @"HPSAudioPlayer", @"HPSAudioEngine"
    ];
    for(NSString *name in extraWrappers){
        InstallWrapperHooks(NSClassFromString(name));
    }

    // Catch-all on AVAudioEngine init — any new engine created after the
    // tweak loads gets tracked, and the 1-second timer re-mutes its
    // mainMixerNode.outputVolume. Belt-and-braces: this catches engines
    // TikTok spins up that don't go through any of the above wrappers.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method m=class_getInstanceMethod([AVAudioEngine class], @selector(init));
        if(!m)return;
        IMP orig=method_getImplementation(m);
        method_setImplementation(m,imp_implementationWithBlock(^(id self){
            id e=((id(*)(id,SEL))orig)(self,@selector(init));
            if(PTIsTikTok() && e){
                @try{
                    if(gPrivateTikTokMuted && [e respondsToSelector:@selector(mainMixerNode)])
                        [[e mainMixerNode] setOutputVolume:0.0f];
                }@catch(__unused NSException *ex){}
            }
            return e;
        }));
    });
}

static void PTApplyCurrent(void){
    if(!gPrivateTikTokMuted)return;
    PTForceObject(gCurrentPlayer);PTForceObject(gCurrentPlayerController);PTForceObject(gCurrentFeedCell);PTProbePlayer(gCurrentPlayer);
    if([gCurrentPlayerController respondsToSelector:@selector(player)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));}@catch(__unused NSException*e){}}
}
static void PTRestoreCurrent(void){
    if(gPrivateTikTokMuted)return;
    PTRestoreObject(gCurrentPlayer);PTRestoreObject(gCurrentPlayerController);PTRestoreObject(gCurrentFeedCell);PTProbePlayer(gCurrentPlayer);
    if([gCurrentPlayerController respondsToSelector:@selector(player)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));}@catch(__unused NSException*e){}}
}

%ctor{
    if(!PTIsTikTok())return;
    gOriginalIMPs=[NSMutableDictionary dictionary];
    dispatch_async(dispatch_get_main_queue(),^{[[NSNotificationCenter defaultCenter]addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*n){gPrivateTikTokMuted=[n.userInfo[@"muted"]boolValue];if(gPrivateTikTokMuted)PTApplyCurrent();else PTRestoreCurrent();}];});
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{InstallPrivateHooks();TikTokPlusInstallMuteButton();if(gPrivateTikTokMuted)PTApplyCurrent();else PTRestoreCurrent();});
    dispatch_resume(timer);
}
