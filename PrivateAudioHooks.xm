#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

void TikTokPlusInstallMuteButton(void);
static void PTApplyCurrent(void);
static void PTRestoreCurrent(void);
static BOOL gPrivateTikTokMuted=NO;
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
    if([o respondsToSelector:@selector(setVolume:)]&&[o respondsToSelector:@selector(volume)]){@try{float v=((float(*)(id,SEL))objc_msgSend)(o,@selector(volume));if(v<=.001f)((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setVolume:),1.0f);}@catch(__unused NSException*e){}}
    if([o respondsToSelector:@selector(setAudioVolume:)]&&[o respondsToSelector:@selector(audioVolume)]){@try{float v=((float(*)(id,SEL))objc_msgSend)(o,@selector(audioVolume));if(v<=.001f)((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setAudioVolume:),1.0f);}@catch(__unused NSException*e){}}
    if([o respondsToSelector:@selector(setPlayerVolume:)]&&[o respondsToSelector:@selector(playerVolume)]){@try{float v=((float(*)(id,SEL))objc_msgSend)(o,@selector(playerVolume));if(v<=.001f)((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setPlayerVolume:),1.0f);}@catch(__unused NSException*e){}}
    if([o respondsToSelector:@selector(setOutputVolume:)]&&[o respondsToSelector:@selector(outputVolume)]){@try{float v=((float(*)(id,SEL))objc_msgSend)(o,@selector(outputVolume));if(v<=.001f)((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setOutputVolume:),1.0f);}@catch(__unused NSException*e){}}
}

static void PTProbeNode(id node){
    if(!node)return;
    if(gPrivateTikTokMuted)PTForceObject(node);else PTRestoreObject(node);
}

static void PTProbeCore(id core){
    if(!core)return;
    PTProbeNode(core);
    for(NSString*n in @[@"playerNode",@"mixerNode",@"silentNode",@"mainMixerNode"]){SEL s=NSSelectorFromString(n);if([core respondsToSelector:s]){@try{id node=((id(*)(id,SEL))objc_msgSend)(core,s);PTProbeNode(node);}@catch(__unused NSException*e){}}}
}

/* Walk the small object graph exposed by TikTok's feed-player wrappers. */
static void PTProbePlayer(id player){
    if(!player)return;
    PTProbeNode(player);
    for(NSString*n in @[@"player",@"currentPlayer",@"audioPlayer",@"avPlayer",@"videoPlayer",@"playerNode",@"mixerNode",@"silentNode",@"audioEngine",@"audioMixerNode",@"mainMixerNode",@"audioRenderer",@"audioOutput",@"soundPlayer",@"soundEngine",@"core",@"audioCore",@"playerCore",@"audioPlayerCore"]){SEL s=NSSelectorFromString(n);if(![player respondsToSelector:s])continue;@try{id child=((id(*)(id,SEL))objc_msgSend)(player,s);if(child&&child!=player)PTProbeNode(child);}@catch(__unused NSException*e){}}
    for(NSString*n in @[@"player",@"currentPlayer",@"avPlayer",@"audioPlayer"]){SEL s=NSSelectorFromString(n);if(![player respondsToSelector:s])continue;@try{id child=((id(*)(id,SEL))objc_msgSend)(player,s);if(child&&child!=player)PTProbePlayer(child);}@catch(__unused NSException*e){}}
}

static void PTInstall(Class cls,SEL sel,IMP replacement){
    if(!cls||!replacement)return;Method m=class_getInstanceMethod(cls,sel);if(!m)return;NSString*k=PTKey(cls,sel);if(gOriginalIMPs[k])return;IMP original=method_getImplementation(m);gOriginalIMPs[k]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];method_setImplementation(m,replacement);
}

static void PTSetBool(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=YES;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);if(gPrivateTikTokMuted)PTForceObject(self);}
static void PTSetFloat(id self,SEL sel,float value){if(gPrivateTikTokMuted)value=0.0f;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,float))o)(self,sel,value);if(gPrivateTikTokMuted)PTForceObject(self);}
static void PTSetDouble(id self,SEL sel,double value){if(gPrivateTikTokMuted)value=0.0;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,double))o)(self,sel,value);if(gPrivateTikTokMuted)PTForceObject(self);}
static void PTEnableSound(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=NO;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);if(gPrivateTikTokMuted)PTForceObject(self);}

static void PTCaptureObject(id self,SEL sel,id value){
    if(value&&value!=self){gCurrentPlayer=value;PTProbePlayer(value);}
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,id))o)(self,sel,value);
    if(gPrivateTikTokMuted){PTForceObject(self);PTProbePlayer(value);PTApplyCurrent();}
}

static void PTPlayerLoop(id self,SEL sel,id player){
    gCurrentPlayerController=self;gCurrentPlayer=player;
    IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,id))o)(self,sel,player);
    TikTokPlusInstallMuteButton();PTProbePlayer(player);
    if(gPrivateTikTokMuted){PTForceObject(self);PTApplyCurrent();}else PTRestoreObject(self);
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
    Class mlk=NSClassFromString(@"MLKAudioPlayer");if(!mlk)mlk=NSClassFromString(@"MaLiangKit.MLKAudioPlayer");
    if(mlk){PTInstall(mlk,@selector(setEnableSoundOutput:),(IMP)PTEnableSound);Method vm=class_getInstanceMethod(mlk,@selector(setVolume:));if(vm){const char*t=method_getTypeEncoding(vm);PTInstall(mlk,@selector(setVolume:),(t&&strchr(t,'d'))?(IMP)PTSetDouble:(IMP)PTSetFloat);}}
}

static void PTApplyCurrent(void){
    if(!gPrivateTikTokMuted)return;
    PTForceObject(gCurrentPlayer);PTForceObject(gCurrentPlayerController);PTForceObject(gCurrentFeedCell);PTProbePlayer(gCurrentPlayer);
    if([gCurrentPlayerController respondsToSelector:@selector(player)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayer respondsToSelector:@selector(player)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayer,@selector(player)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayer respondsToSelector:@selector(avPlayer)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayer,@selector(avPlayer)));}@catch(__unused NSException*e){}}
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
