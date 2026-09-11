#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
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
        if(gAudioFindings.count>24)[gAudioFindings removeObjectAtIndex:0];
        NSString *body=[gAudioFindings componentsJoinedByString:@"\n"];
        gAudioDiagLabel.text=body;
        gAudioDiagLabel.numberOfLines=0;
    });
}

static void PTDescribeClass(Class cls,NSString *origin){
    if(!cls)return;
    NSString *name=NSStringFromClass(cls);
    PTAddFinding([NSString stringWithFormat:@"%@ => %@",origin,name]);
    unsigned int count=0;
    Method *methods=class_copyMethodList(cls,&count);
    NSMutableArray *hits=[NSMutableArray array];
    for(unsigned int i=0;i<count;i++){
        NSString *s=NSStringFromSelector(method_getName(methods[i]));
        NSString *l=s.lowercaseString;
        if([l containsString:@"audio"]||[l containsString:@"player"]||[l containsString:@"volume"]||[l containsString:@"mute"]||[l containsString:@"engine"]||[l containsString:@"mixer"]||[l containsString:@"sound"]||[l containsString:@"render"]||[l containsString:@"track"]){
            if(![hits containsObject:s])[hits addObject:s];
        }
    }
    free(methods);
    [hits sortUsingSelector:@selector(compare:)];
    NSUInteger max=18;
    for(NSUInteger i=0;i<hits.count&&i<max;i++)PTAddFinding([NSString stringWithFormat:@"  %@",hits[i]]);
}

static void PTForceObject(id o){
    if(!o||!gPrivateTikTokMuted)return;
    if([o respondsToSelector:@selector(setMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setMuted:),YES);
    if([o respondsToSelector:@selector(setAudioMuted:)])((void(*)(id,SEL,BOOL))objc_msgSend)(o,@selector(setAudioMuted:),YES);
    if([o respondsToSelector:@selector(setVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setVolume:),0.0f);
    if([o respondsToSelector:@selector(setAudioVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setAudioVolume:),0.0f);
    if([o respondsToSelector:@selector(setPlayerVolume:)])((void(*)(id,SEL,float))objc_msgSend)(o,@selector(setPlayerVolume:),0.0f);
}

static void PTProbePlayer(id player){
    if(!player)return;
    PTDescribeClass(object_getClass(player),@"PLAYER");
    PTForceObject(player);
    NSArray *selectors=@[@"player",@"currentPlayer",@"audioPlayer",@"avPlayer",@"videoPlayer",@"playerNode",@"audioEngine",@"audioMixerNode",@"mainMixerNode",@"audioUnit",@"audioRenderer",@"audioOutput",@"soundPlayer",@"soundEngine"];
    for(NSString *name in selectors){
        SEL s=NSSelectorFromString(name);
        if([player respondsToSelector:s]){
            @try{
                id child=((id(*)(id,SEL))objc_msgSend)(player,s);
                if(child&&child!=player){
                    PTDescribeClass(object_getClass(child),name);
                    PTForceObject(child);
                }
            }@catch(__unused NSException *e){}
        }
    }
}

static void PTScanControllerMethods(id obj,NSString *origin){
    if(!obj)return;
    PTDescribeClass(object_getClass(obj),origin);
}

static UIWindow *PTDiagWindow(void){
    UIApplication *app=UIApplication.sharedApplication;
    UIWindow *best=nil;
    for(UIWindow *w in app.windows){
        if(w.hidden||w.alpha<0.01)continue;
        if(w.windowLevel==UIWindowLevelNormal&&w.rootViewController){best=w;break;}
    }
    return best;
}

static void PTInstallDiagUI(void){
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow *w=PTDiagWindow();
        if(!w)return;
        gDiagWindow=w;
        if(!gAudioDiagLabel){
            gAudioDiagLabel=[UILabel new];
            gAudioDiagLabel.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.78];
            gAudioDiagLabel.textColor=UIColor.whiteColor;
            gAudioDiagLabel.font=[UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
            gAudioDiagLabel.layer.cornerRadius=6;
            gAudioDiagLabel.layer.masksToBounds=YES;
            gAudioDiagLabel.textAlignment=NSTextAlignmentLeft;
            gAudioDiagLabel.numberOfLines=0;
            gAudioDiagLabel.text=@"TikTokPlus audio scan: waiting for player...";
        }
        if(gAudioDiagLabel.superview!=w){[gAudioDiagLabel removeFromSuperview];[w addSubview:gAudioDiagLabel];}
        CGFloat width=MIN(360.0,w.bounds.size.width-16.0);
        gAudioDiagLabel.frame=CGRectMake(8.0,w.bounds.size.height-300.0,width,292.0);
        [w bringSubviewToFront:gAudioDiagLabel];
    });
}

static void PTInstall(Class cls,SEL sel,IMP replacement){
    if(!cls||!replacement)return;
    Method m=class_getInstanceMethod(cls,sel);
    if(!m)return;
    NSString*k=PTKey(cls,sel);
    if(gOriginalIMPs[k])return;
    IMP original=method_getImplementation(m);
    gOriginalIMPs[k]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];
    method_setImplementation(m,replacement);
    PTAddFinding([NSString stringWithFormat:@"HOOK %@ :: %@",NSStringFromClass(cls),NSStringFromSelector(sel)]);
}

static void PTSetBool(id self,SEL sel,BOOL value){
    if(gPrivateTikTokMuted)value=YES;
    IMP o=PTOriginalForSelf(self,sel);
    if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);
}
static void PTSetFloat(id self,SEL sel,float value){
    if(gPrivateTikTokMuted)value=0.0f;
    IMP o=PTOriginalForSelf(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,value);
}
static void PTPlayerLoop(id self,SEL sel,id player){
    gCurrentPlayerController=self;
    gCurrentPlayer=player;
    PTScanControllerMethods(self,@"CONTROLLER");
    PTProbePlayer(player);
    IMP o=PTOriginalForSelf(self,sel);
    if(o)((void(*)(id,SEL,id))o)(self,sel,player);
    TikTokPlusInstallMuteButton();
    if(gPrivateTikTokMuted){PTForceObject(self);PTProbePlayer(player);PTApplyCurrent();}
}
static void PTFeedDisplay(id self,SEL sel,NSInteger reason){
    gCurrentFeedCell=self;
    PTScanControllerMethods(self,@"FEED CELL");
    IMP o=PTOriginalForSelf(self,sel);
    if(o)((void(*)(id,SEL,NSInteger))o)(self,sel,reason);
    TikTokPlusInstallMuteButton();
    if(gPrivateTikTokMuted)PTForceObject(self);
}
static void PTControllerPlay(id self,SEL sel){
    gCurrentPlayerController=self;
    PTScanControllerMethods(self,@"CONTROLLER PLAY");
    if(gPrivateTikTokMuted)PTForceObject(self);
    IMP o=PTOriginalForSelf(self,sel);
    if(o)((void(*)(id,SEL))o)(self,sel);
    if(gPrivateTikTokMuted)PTApplyCurrent();
}

static void InstallPrivateHooks(void){
    Class controller=NSClassFromString(@"AWEPlayVideoPlayerController");
    Class cell=NSClassFromString(@"AWEFeedCellViewController");
    if(!controller&&!cell)return;
    PTInstall(controller,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);
    PTInstall(controller,@selector(play),(IMP)PTControllerPlay);
    PTInstall(cell,@selector(playerWillLoopPlaying:),(IMP)PTPlayerLoop);
    PTInstall(cell,@selector(containerDidFullyDisplayWithReason:),(IMP)PTFeedDisplay);
    NSArray *b=@[@"setMuted:",@"setAudioMuted:"];
    NSArray *f=@[@"setVolume:",@"setAudioVolume:",@"setPlayerVolume:"];
    if(controller){for(NSString*n in b)PTInstall(controller,NSSelectorFromString(n),(IMP)PTSetBool);for(NSString*n in f)PTInstall(controller,NSSelectorFromString(n),(IMP)PTSetFloat);}
    if(cell){for(NSString*n in b)PTInstall(cell,NSSelectorFromString(n),(IMP)PTSetBool);for(NSString*n in f)PTInstall(cell,NSSelectorFromString(n),(IMP)PTSetFloat);}
}

static void PTApplyCurrent(void){
    if(!gPrivateTikTokMuted)return;
    PTForceObject(gCurrentPlayer);
    PTForceObject(gCurrentPlayerController);
    PTForceObject(gCurrentFeedCell);
    if([gCurrentPlayerController respondsToSelector:@selector(player)]){
        @try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(player)));}@catch(__unused NSException *e){}
    }
    if([gCurrentPlayerController respondsToSelector:@selector(currentPlayer)]){
        @try{PTProbePlayer(((id(*)(id,SEL))objc_msgSend)(gCurrentPlayerController,@selector(currentPlayer)));}@catch(__unused NSException *e){}
    }
    PTProbePlayer(gCurrentPlayer);
}

%ctor{
    if(!PTIsTikTok())return;
    gOriginalIMPs=[NSMutableDictionary dictionary];
    gAudioFindings=[NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(),^{
        PTInstallDiagUI();
        [[NSNotificationCenter defaultCenter]addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification*n){
            gPrivateTikTokMuted=[n.userInfo[@"muted"]boolValue];
            if(gPrivateTikTokMuted)PTApplyCurrent();
        }];
    });
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        InstallPrivateHooks();
        PTInstallDiagUI();
        TikTokPlusInstallMuteButton();
        if(gPrivateTikTokMuted)PTApplyCurrent();
    });
    dispatch_resume(timer);
}
