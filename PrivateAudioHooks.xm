#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

void TikTokPlusInstallMuteButton(void);
static void PTApplyCurrent(void);
static BOOL gPrivateTikTokMuted=NO;
static __weak id gCurrentFeedCell;
static __weak id gCurrentPlayerController;
static __weak id gCurrentPlayer;
static NSMutableDictionary *gOriginalIMPs;
static NSMutableArray *gAudioFindings;
static UILabel *gAudioDiagLabel;
static __weak UIWindow *gDiagWindow;

static BOOL PTIsTikTok(void){
    NSString*b=[NSBundle mainBundle].bundleIdentifier.lowercaseString;
    return [b containsString:@"musically"]||[b containsString:@"tiktok"];
}
static NSString *PTKey(Class cls,SEL sel){return [NSString stringWithFormat:@"%p:%@",cls,NSStringFromSelector(sel)];}
static IMP PTOriginal(Class cls,SEL sel){NSValue*v=gOriginalIMPs[PTKey(cls,sel)];if(!v)return NULL;IMP p=NULL;[v getValue:&p];return p;}
static IMP PTOriginalForSelf(id self,SEL sel){Class cls=object_getClass(self);while(cls){IMP p=PTOriginal(cls,sel);if(p)return p;cls=class_getSuperclass(cls);}return NULL;}

static void PTAddFinding(NSString *text){
    if(!text.length)return;
    dispatch_async(dispatch_get_main_queue(),^{
        if(!gAudioFindings)gAudioFindings=[NSMutableArray array];
        if([gAudioFindings containsObject:text])return;
        [gAudioFindings addObject:text];
        if(gAudioFindings.count>32)[gAudioFindings removeObjectAtIndex:0];
        gAudioDiagLabel.text=[gAudioFindings componentsJoinedByString:@"\n"];
        gAudioDiagLabel.numberOfLines=0;
    });
}

static void PTDescribeClass(Class cls,NSString *origin){
    if(!cls)return;
    NSString *name=NSStringFromClass(cls);
    PTAddFinding([NSString stringWithFormat:@"%@ => %@",origin,name]);
    unsigned int count=0; Method *methods=class_copyMethodList(cls,&count);
    NSMutableArray *hits=[NSMutableArray array];
    for(unsigned int i=0;i<count;i++){
        NSString *s=NSStringFromSelector(method_getName(methods[i])); NSString*l=s.lowercaseString;
        if([l containsString:@"audio"]||[l containsString:@"player"]||[l containsString:@"volume"]||[l containsString:@"mute"]||[l containsString:@"engine"]||[l containsString:@"mixer"]||[l containsString:@"sound"]||[l containsString:@"render"]||[l containsString:@"node"]){
            if(![hits containsObject:s])[hits addObject:s];
        }
    }
    free(methods); [hits sortUsingSelector:@selector(compare:)];
    for(NSUInteger i=0;i<hits.count&&i<22;i++)PTAddFinding([NSString stringWithFormat:@"  %@",hits[i]]);
}

static void PTForceObject(id o){
    if(!o||!gPrivateTikTokMuted)return;
    if([o respondsToSelector:@selector(setMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setMuted:),YES);
    if([o respondsToSelector:@selector(setAudioMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setAudioMuted:),YES);
    if([o respondsToSelector:@selector(setVolume:)]){
        Method m=class_getInstanceMethod(object_getClass(o),@selector(setVolume:));
        const char *t=m?method_getTypeEncoding(m):NULL;
        if(t && strchr(t,'d'))((void(*)(id,SEL,double))objc_msgSend)(o,@selector(setVolume:),0.0);
        else ((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setVolume:),0.0f);
    }
    if([o respondsToSelector:@selector(setAudioVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setAudioVolume:),0.0f);
    if([o respondsToSelector:@selector(setPlayerVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setPlayerVolume:),0.0f);
}

static void PTProbeNode(id node,NSString *label){
    if(!node)return;
    PTAddFinding([NSString stringWithFormat:@"%@ => %@",label,NSStringFromClass([node class])]);
    PTForceObject(node);
    if([node respondsToSelector:@selector(setOutputVolume:)])((void(*)(id,SEL,float))objc_msgSend)(node,@selector(setOutputVolume:),0.0f);
}

static void PTProbeCore(id core){
    if(!core)return;
    PTAddFinding([NSString stringWithFormat:@"CORE => %@",NSStringFromClass([core class])]);
    NSArray *sels=@[@"playerNode",@"mixerNode",@"silentNode"];
    for(NSString *n in sels){
        SEL s=NSSelectorFromString(n);
        if([core respondsToSelector:s]){@try{ id node=((id(*)(id,SEL))objc_msgSend)(core,s); PTProbeNode(node,n); }@catch(__unused NSException*e){}}
    }
    PTForceObject(core);
}

static void PTProbeMLK(id player){
    if(!player)return;
    PTAddFinding([NSString stringWithFormat:@"MLK => %@",NSStringFromClass([player class])]);
    PTDescribeClass([player class],@"MLK CLASS");
    PTForceObject(player);
    if([player respondsToSelector:@selector(setEnableSoundOutput:)]){
        ((void(*)(id,SEL,BOOL))objc_msgSend)(player,@selector(setEnableSoundOutput:),gPrivateTikTokMuted?NO:YES);
        PTAddFinding(@"setEnableSoundOutput: hooked/forced");
    }
    if([player respondsToSelector:@selector(setVolume:)])PTForceObject(player);
    NSArray *coreSels=@[@"core",@"audioCore",@"playerCore",@"audioPlayerCore"];
    for(NSString*n in coreSels){SEL s=NSSelectorFromString(n);if([player respondsToSelector:s]){@try{id core=((id(*)(id,SEL))objc_msgSend)(player,s);PTProbeCore(core);} @catch(__unused NSException*e){}}}
}

static void PTProbePlayer(id player){
    if(!player)return;
    PTDescribeClass([player class],@"PLAYER");
    PTForceObject(player);
    PTProbeMLK(player);
    NSArray *selectors=@[@"player",@"currentPlayer",@"audioPlayer",@"avPlayer",@"videoPlayer",@"playerNode",@"audioEngine",@"audioMixerNode",@"mainMixerNode",@"audioUnit",@"audioRenderer",@"audioOutput",@"soundPlayer",@"soundEngine",@"core",@"audioCore",@"playerCore"];
    for(NSString *name in selectors){SEL s=NSSelectorFromString(name);if([player respondsToSelector:s]){@try{id child=((id(*)(id,SEL))objc_msgSend)(player,s);if(child&&child!=player){PTDescribeClass([child class],name);PTForceObject(child);PTProbeNode(child,name);}}@catch(__unused NSException*e){}}}
}

static void PTScanControllerMethods(id obj,NSString *origin){if(!obj)return;PTDescribeClass([obj class],origin);}

static UIWindow *PTDiagWindow(void){
    UIApplication *app=UIApplication.sharedApplication; UIWindow *best=nil;
    for(UIWindow*w in app.windows){if(w.hidden||w.alpha<.01)continue;if(w.windowLevel==UIWindowLevelNormal&&w.rootViewController){best=w;break;}}
    return best;
}
static void PTInstallDiagUI(void){
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow*w=PTDiagWindow();if(!w)return;gDiagWindow=w;
        if(!gAudioDiagLabel){gAudioDiagLabel=[UILabel new];gAudioDiagLabel.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.78];gAudioDiagLabel.textColor=UIColor.whiteColor;gAudioDiagLabel.font=[UIFont systemFontOfSize:9];gAudioDiagLabel.layer.cornerRadius=6;gAudioDiagLabel.layer.masksToBounds=YES;gAudioDiagLabel.numberOfLines=0;gAudioDiagLabel.text=@"TikTokPlus audio scan: waiting...";}
        if(gAudioDiagLabel.superview!=w){[gAudioDiagLabel removeFromSuperview];[w addSubview:gAudioDiagLabel];}
        CGFloat width=MIN(370.0,w.bounds.size.width-16.0);gAudioDiagLabel.frame=CGRectMake(8,w.bounds.size.height-310,width,302);[w bringSubviewToFront:gAudioDiagLabel];
    });
}

static void PTInstall(Class cls,SEL sel,IMP replacement){
    if(!cls||!replacement)return; Method m=class_getInstanceMethod(cls,sel);if(!m)return;NSString*k=PTKey(cls,sel);if(gOriginalIMPs[k])return;IMP original=method_getImplementation(m);gOriginalIMPs[k]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];method_setImplementation(m,replacement);PTAddFinding([NSString stringWithFormat:@"HOOK %@ :: %@",NSStringFromClass(cls),NSStringFromSelector(sel)]);
}

static void PTSetBool(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=YES;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);}
static void PTSetFloat(id self,SEL sel,float value){if(gPrivateTikTokMuted)value=0;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,float))o)(self,sel,value);}
static void PTSetDouble(id self,SEL sel,double value){if(gPrivateTikTokMuted)value=0;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,double))o)(self,sel,value);}
static void PTEnableSound(id self,SEL sel,BOOL value){if(gPrivateTikTokMuted)value=NO;IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);PTAddFinding([NSString stringWithFormat:@"%@ enableSoundOutput=%@",NSStringFromClass([self class]),value?@"YES":@"NO"]);}

static void PTPlayerLoop(id self,SEL sel,id player){gCurrentPlayerController=self;gCurrentPlayer=player;PTScanControllerMethods(self,@"CONTROLLER");PTProbePlayer(player);IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,id))o)(self,sel,player);TikTokPlusInstallMuteButton();if(gPrivateTikTokMuted){PTForceObject(self);PTProbePlayer(player);PTApplyCurrent();}}
static void PTFeedDisplay(id self,SEL sel,NSInteger reason){gCurrentFeedCell=self;PTScanControllerMethods(self,@"FEED CELL");IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL,NSInteger))o)(self,sel,reason);TikTokPlusInstallMuteButton();if(gPrivateTikTokMuted)PTForceObject(self);}
static void PTControllerPlay(id self,SEL sel){gCurrentPlayerController=self;PTScanControllerMethods(self,@"CONTROLLER PLAY");if(gPrivateTikTokMuted)PTForceObject(self);IMP o=PTOriginalForSelf(self,sel);if(o)((void(*)(id,SEL))o)(self,sel);if(gPrivateTikTokMuted)PTApplyCurrent();}

static void InstallPrivateHooks(void){
    Class controller=NSClassFromString(@"AWEPlayVideoPlayerController");Class cell=NSClassFromString(@"AWEFeedCellViewController");
    if(controller||cell){
        PTInstall(controller,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);PTInstall(controller,@selector(play),(IMP)PTControllerPlay);PTInstall(cell,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);PTInstall(cell,@selector(containerDidFullyDisplayWithReason:),(IMP)PTFeedDisplay);
        NSArray*b=@[@"setMuted:",@"setAudioMuted:"];NSArray*f=@[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:"];
        if(controller){for(NSString*n in b)PTInstall(controller,NSSelectorFromString(n),(IMP)PTSetBool);for(NSString*n in f){SEL s=NSSelectorFromString(n);Method m=class_getInstanceMethod(controller,s);if(m){const char*t=method_getTypeEncoding(m);PTInstall(controller,s,(IMP)((t&&strchr(t,'d'))?PTSetDouble:PTSetFloat));}}}
        if(cell){for(NSString*n in b)PTInstall(cell,NSSelectorFromString(n),(IMP)PTSetBool);for(NSString*n in f)PTInstall(cell,NSSelectorFromString(n),(IMP)PTSetFloat);}
    }
    Class mlk=NSClassFromString(@"MLKAudioPlayer");
    if(!mlk)mlk=NSClassFromString(@"MaLiangKit.MLKAudioPlayer");
    if(mlk){
        PTAddFinding([NSString stringWithFormat:@"FOUND %@",NSStringFromClass(mlk)]);
        PTDescribeClass(mlk,@"MLKAudioPlayer");
        PTInstall(mlk,@selector(setEnableSoundOutput:),(IMP)PTEnableSound);
        Method vm=class_getInstanceMethod(mlk,@selector(setVolume:));
        if(vm){const char*t=method_getTypeEncoding(vm);PTInstall(mlk,@selector(setVolume:),(IMP)((t&&strchr(t,'d'))?PTSetDouble:PTSetFloat));}
    }
    Class core=NSClassFromString(@"AudioPlayerCore");
    if(!core)core=NSClassFromString(@"MaLiangKit.AudioPlayerCore");
    if(core){PTAddFinding([NSString stringWithFormat:@"FOUND %@",NSStringFromClass(core)]);PTDescribeClass(core,@"AudioPlayerCore");}
}

static void PTApplyCurrent(void){
    if(!gPrivateTikTokMuted)return;PTForceObject(gCurrentPlayer);PTForceObject(gCurrentPlayerController);PTForceObject(gCurrentFeedCell);PTProbeMLK(gCurrentPlayer);
    if([gCurrentPlayerController respondsToSelector:@selector(player)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));}@catch(__unused NSException*e){}}
    if([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]){@try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));}@catch(__unused NSException*e){}}
}

%ctor{
    if(!PTIsTikTok())return;gOriginalIMPs=[NSMutableDictionary dictionary];gAudioFindings=[NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(),^{PTInstallDiagUI();[[NSNotificationCenter defaultCenter]addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*n){gPrivateTikTokMuted=[n.userInfo[@"muted"]boolValue];if(gPrivateTikTokMuted)PTApplyCurrent();}];});
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);dispatch_source_set_event_handler(timer,^{InstallPrivateHooks();PTInstallDiagUI();TikTokPlusInstallMuteButton();if(gPrivateTikTokMuted)PTApplyCurrent();});dispatch_resume(timer);
}
