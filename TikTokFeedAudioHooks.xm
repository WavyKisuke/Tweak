#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

void TikTokPlusInstallMuteButton(void);

static BOOL gFeedMuted = YES;
static NSMutableDictionary *gFeedOriginals;

static BOOL FeedIsTikTok(void){
    NSString *b=NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [b containsString:@"musically"] || [b containsString:@"tiktok"];
}

static NSString *FeedKey(Class c, SEL s){
    return [NSString stringWithFormat:@"%p:%@",c,NSStringFromSelector(s)];
}

static IMP FeedOriginal(id self, SEL sel){
    Class c=object_getClass(self);
    while(c){
        NSValue *v=gFeedOriginals[FeedKey(c,sel)];
        if(v){ IMP p=NULL; [v getValue:&p]; return p; }
        c=class_getSuperclass(c);
    }
    return NULL;
}

static void FeedSetBool(id self, SEL sel, BOOL value){
    if(gFeedMuted) value=YES;
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,BOOL))o)(self,sel,value);
}

static void FeedSetVolume(id self, SEL sel, float value){
    if(gFeedMuted) value=0.0f;
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,value);
}

static void FeedSetDouble(id self, SEL sel, double value){
    if(gFeedMuted) value=0.0;
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,double))o)(self,sel,value);
}

static void FeedMute(id self, SEL sel){
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL))o)(self,sel);
    if(gFeedMuted){
        if([self respondsToSelector:@selector(setMuted:)])
            ((void(*)(id,SEL,BOOL))objc_msgSend)(self,@selector(setMuted:),YES);
        if([self respondsToSelector:@selector(setVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(self,@selector(setVolume:),0.0f);
    }
}

static void FeedPlay(id self, SEL sel){
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL))o)(self,sel);
    if(gFeedMuted){
        if([self respondsToSelector:@selector(setMuted:)])
            ((void(*)(id,SEL,BOOL))objc_msgSend)(self,@selector(setMuted:),YES);
        if([self respondsToSelector:@selector(setVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(self,@selector(setVolume:),0.0f);
        if([self respondsToSelector:@selector(setAudioPlayVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(self,@selector(setAudioPlayVolume:),0.0f);
        if([self respondsToSelector:@selector(setOriginalSoundVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(self,@selector(setOriginalSoundVolume:),0.0f);
        if([self respondsToSelector:@selector(setVoiceoverVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(self,@selector(setVoiceoverVolume:),0.0f);
    }
}

static void FeedCapture(id self, SEL sel, id value){
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,id))o)(self,sel,value);
    if(gFeedMuted && value && value!=self){
        if([value respondsToSelector:@selector(setMuted:)])
            ((void(*)(id,SEL,BOOL))objc_msgSend)(value,@selector(setMuted:),YES);
        if([value respondsToSelector:@selector(setVolume:)])
            ((void(*)(id,SEL,float))objc_msgSend)(value,@selector(setVolume:),0.0f);
    }
}

/* Dedicated hooks requested for TikTok's feed/audio/model path. */
static void FeedControllerSetVolume(id self, SEL sel, float volume){
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,0.0f);
}

static void FeedMusicSetVolume(id self, SEL sel, float volume){
    IMP o=FeedOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,0.0f);
}

static BOOL FeedMusicIsPlaying(id self, SEL sel){
    return NO;
}

static BOOL FeedModelIsMuted(id self, SEL sel){
    return YES;
}

static void FeedInstall(Class cls, SEL sel, IMP replacement){
    if(!cls||!replacement)return;
    Method m=class_getInstanceMethod(cls,sel);
    if(!m)return;
    NSString *k=FeedKey(cls,sel);
    if(gFeedOriginals[k])return;
    IMP original=method_getImplementation(m);
    gFeedOriginals[k]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];
    method_setImplementation(m,replacement);
}

static void FeedInstallClass(Class cls){
    if(!cls)return;
    FeedInstall(cls,@selector(play),(IMP)FeedPlay);
    FeedInstall(cls,@selector(mute),(IMP)FeedMute);
    for(NSString *n in @[@"setMuted:",@"setMute:",@"setIsMuted:",@"setAudioMuted:"])
        FeedInstall(cls,NSSelectorFromString(n),(IMP)FeedSetBool);

    for(NSString *n in @[
        @"setVolume:",@"setAudioVolume:",@"setPlayerVolume:",@"setOutputVolume:",
        @"setAudioPlayVolume:",@"setOriginalSoundVolume:",@"setVoiceoverVolume:",
        @"setMusicVolume:",@"setBGMVolume:",@"setBgMusicVolume:"]){
        SEL s=NSSelectorFromString(n);
        Method m=class_getInstanceMethod(cls,s);
        if(!m)continue;
        const char *t=method_getTypeEncoding(m);
        FeedInstall(cls,s,(t&&strchr(t,'d'))?(IMP)FeedSetDouble:(IMP)FeedSetVolume);
    }

    for(NSString *n in @[@"setPlayer:",@"setCurrentPlayer:",@"setAVPlayer:",@"setAvPlayer:",@"setVideoPlayer:",@"setAudioPlayer:"])
        FeedInstall(cls,NSSelectorFromString(n),(IMP)FeedCapture);
}

%ctor{
    if(!FeedIsTikTok())return;
    gFeedOriginals=[NSMutableDictionary dictionary];
    dispatch_async(dispatch_get_main_queue(),^{
        [[NSNotificationCenter defaultCenter]addObserverForName:@"TikTokPlusMuteChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            gFeedMuted=[n.userInfo[@"muted"] boolValue];
        }];
    });

    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{
        if(!FeedIsTikTok())return;

        /* Existing player/controller paths. */
        FeedInstallClass(NSClassFromString(@"AWEAVPlayerWrapper"));
        FeedInstallClass(NSClassFromString(@"AWEAwemeDisplayPlayerController"));
        FeedInstallClass(NSClassFromString(@"AWEAwemePlayMediaPlayerControllerLegacy"));
        FeedInstallClass(NSClassFromString(@"AWEPlayVideoPlayerController"));
        FeedInstallClass(NSClassFromString(@"AWEFeedCellViewController"));

        /* Explicit feed/audio/model hooks requested for this build. */
        Class feedController=NSClassFromString(@"AWEFeedTableViewController");
        FeedInstall(feedController,@selector(setVolume:),(IMP)FeedControllerSetVolume);

        Class musicPlayer=NSClassFromString(@"AWEMusicPlayer");
        FeedInstall(musicPlayer,@selector(setVolume:),(IMP)FeedMusicSetVolume);
        FeedInstall(musicPlayer,@selector(isPlaying),(IMP)FeedMusicIsPlaying);

        Class awemeModel=NSClassFromString(@"AWEAwemeModel");
        FeedInstall(awemeModel,@selector(isMuted),(IMP)FeedModelIsMuted);

        TikTokPlusInstallMuteButton();
    });
    dispatch_resume(timer);
}
