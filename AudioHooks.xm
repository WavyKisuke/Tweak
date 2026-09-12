#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL gTikTokMuted=YES;
static float gTikTokVolume=0.0f;
static UIButton *gMuteButton;
static UIView *gVolumePanel;
static UISlider *gVolumeSlider;
static UILabel *gVolumeLabel;
static id gAudioTarget;
static NSHashTable *gPlayers;
static NSHashTable *gAudioObjects;
static NSMapTable *gBaseVolumes;
static NSMutableDictionary *gAVOriginals;

static BOOL IsTikTok(void){
    NSString *b=NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [b containsString:@"musically"] || [b containsString:@"tiktok"];
}

static NSString *AVKey(Class c,SEL s){ return [NSString stringWithFormat:@"%p:%@",c,NSStringFromSelector(s)]; }
static IMP AVOriginal(id self,SEL sel){
    Class c=object_getClass(self);
    while(c){
        NSValue *v=gAVOriginals[AVKey(c,sel)];
        if(v){ IMP p=NULL; [v getValue:&p]; return p; }
        c=class_getSuperclass(c);
    }
    return NULL;
}

static void EnsureBackgroundMusicMixing(void){
    if(!IsTikTok()) return;
    AVAudioSession *s=AVAudioSession.sharedInstance;
    NSString *category=s.category;
    if(!category.length) category=AVAudioSessionCategoryPlayback;
    AVAudioSessionCategoryOptions options=s.categoryOptions|AVAudioSessionCategoryOptionMixWithOthers;
    [s setCategory:category mode:s.mode options:options error:nil];
}

static void ForceMuteObject(id o){
    if(!o || !gTikTokMuted) return;
    if([o respondsToSelector:@selector(setMuted:)]) [o setMuted:YES];
    if([o respondsToSelector:@selector(setVolume:)]) [o setVolume:0.0f];
    if([o respondsToSelector:@selector(setOutputVolume:)]) [o setOutputVolume:0.0f];
}

static void RestoreAudioObject(id o){
    if(!o || gTikTokMuted) return;
    if([o respondsToSelector:@selector(setMuted:)]) [o setMuted:NO];
    NSNumber *base=[gBaseVolumes objectForKey:o];
    if(base){
        float v=base.floatValue*gTikTokVolume;
        IMP oimp=AVOriginal(o,@selector(setVolume:));
        if(oimp)((void(*)(id,SEL,float))oimp)(o,@selector(setVolume:),v);
        IMP miximp=AVOriginal(o,@selector(setOutputVolume:));
        if(miximp)((void(*)(id,SEL,float))miximp)(o,@selector(setOutputVolume:),v);
    }
}

static void ApplyMuteState(void){
    for(id o in gPlayers.allObjects) {
        if(gTikTokMuted) ForceMuteObject(o); else RestoreAudioObject(o);
    }
    for(id o in gAudioObjects.allObjects) {
        if(gTikTokMuted) ForceMuteObject(o); else RestoreAudioObject(o);
    }
}

static void ApplyTikTokVolume(void){
    if(gTikTokVolume<=0.001f){
        gTikTokMuted=YES;
        ApplyMuteState();
        return;
    }
    gTikTokMuted=NO;
    for(id o in gPlayers.allObjects) RestoreAudioObject(o);
    for(id o in gAudioObjects.allObjects) RestoreAudioObject(o);
}

static void UpdateVolumeUI(void){
    dispatch_async(dispatch_get_main_queue(),^{
        NSInteger pct=(NSInteger)lrintf(gTikTokVolume*100.0f);
        [gMuteButton setTitle:gTikTokMuted?@"🔇  0%":([NSString stringWithFormat:@"🔊  %ld%%",(long)pct]) forState:UIControlStateNormal];
        gVolumeSlider.value=gTikTokVolume;
        gVolumeLabel.text=[NSString stringWithFormat:@"TikTok volume: %ld%%",(long)pct];
    });
}

void TikTokPlusSetMuted(BOOL muted){
    if(!IsTikTok()) return;
    if(muted){
        gTikTokMuted=YES;
        gTikTokVolume=0.0f;
    }else{
        if(gTikTokVolume<=0.001f) gTikTokVolume=1.0f;
        gTikTokMuted=NO;
    }
    EnsureBackgroundMusicMixing();
    ApplyMuteState();
    UpdateVolumeUI();
    [[NSNotificationCenter defaultCenter]postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(gTikTokMuted),@"volume":@(gTikTokVolume)}];
}

static void SetTikTokVolume(float volume){
    if(!IsTikTok()) return;
    gTikTokVolume=MAX(0.0f,MIN(1.0f,volume));
    gTikTokMuted=(gTikTokVolume<=0.001f);
    EnsureBackgroundMusicMixing();
    ApplyTikTokVolume();
    UpdateVolumeUI();
    [[NSNotificationCenter defaultCenter]postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(gTikTokMuted),@"volume":@(gTikTokVolume)}];
}

@interface TTKPlusAudioTarget:NSObject @end
@implementation TTKPlusAudioTarget
-(void)tapMute:(id)sender{
    if(gVolumePanel){ gVolumePanel.hidden=!gVolumePanel.hidden; UpdateVolumeUI(); return; }
}
-(void)sliderChanged:(UISlider *)sender{ SetTikTokVolume(sender.value); }
-(void)closeVolumePanel:(id)sender{ gVolumePanel.hidden=YES; }
-(void)muteFromPanel:(id)sender{ SetTikTokVolume(0.0f); }
@end

static UIWindow *TTKFindHostWindow(void){
    UIApplication *app=UIApplication.sharedApplication;
    UIWindow *key=nil;
    for(UIWindow *w in app.windows){
        if(w.hidden || w.alpha<=0.01 || w.windowLevel!=UIWindowLevelNormal) continue;
        if(!w.rootViewController) continue;
        if(w.isKeyWindow) key=w;
    }
    if(key) return key;
    if(@available(iOS 13.0,*)){
        for(UIScene *scene in app.connectedScenes){
            if(scene.activationState!=UISceneActivationStateForegroundActive) continue;
            if(![scene isKindOfClass:UIWindowScene.class]) continue;
            for(UIWindow *w in ((UIWindowScene *)scene).windows){
                if(w.hidden || w.alpha<=0.01 || w.windowLevel!=UIWindowLevelNormal) continue;
                if(w.rootViewController) return w;
            }
        }
    }
    for(UIWindow *w in app.windows){
        if(!w.hidden && w.alpha>0.01 && w.windowLevel==UIWindowLevelNormal && w.rootViewController) return w;
    }
    return nil;
}

static void InstallVolumePanel(UIWindow *host){
    if(!host) return;
    if(!gAudioTarget) gAudioTarget=[TTKPlusAudioTarget new];
    if(!gVolumePanel){
        UIView *p=[[UIView alloc]initWithFrame:CGRectZero];
        p.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.92];
        p.layer.cornerRadius=14.0;
        p.layer.borderWidth=1.0;
        p.layer.borderColor=UIColor.whiteColor.CGColor;
        p.hidden=YES;

        UILabel *title=[[UILabel alloc]initWithFrame:CGRectZero];
        title.text=@"TikTok Volume";
        title.textColor=UIColor.whiteColor;
        title.font=[UIFont boldSystemFontOfSize:15.0];
        title.textAlignment=NSTextAlignmentCenter;
        [p addSubview:title];

        gVolumeLabel=[[UILabel alloc]initWithFrame:CGRectZero];
        gVolumeLabel.textColor=UIColor.whiteColor;
        gVolumeLabel.font=[UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        gVolumeLabel.textAlignment=NSTextAlignmentCenter;
        [p addSubview:gVolumeLabel];

        gVolumeSlider=[[UISlider alloc]initWithFrame:CGRectZero];
        gVolumeSlider.minimumValue=0.0f;
        gVolumeSlider.maximumValue=1.0f;
        [gVolumeSlider addTarget:gAudioTarget action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [p addSubview:gVolumeSlider];

        UIButton *mute=[UIButton buttonWithType:UIButtonTypeSystem];
        [mute setTitle:@"MUTE" forState:UIControlStateNormal];
        [mute setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        mute.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:.16];
        mute.layer.cornerRadius=8.0;
        [mute addTarget:gAudioTarget action:@selector(muteFromPanel:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:mute];

        UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];
        [done setTitle:@"DONE" forState:UIControlStateNormal];
        [done setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        done.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:.16];
        done.layer.cornerRadius=8.0;
        [done addTarget:gAudioTarget action:@selector(closeVolumePanel:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:done];

        title.tag=1; gVolumeLabel.tag=2; gVolumeSlider.tag=3; mute.tag=4; done.tag=5;
        gVolumePanel=p;
        [host addSubview:p];
    }
    if(gVolumePanel.superview!=host){ [gVolumePanel removeFromSuperview]; [host addSubview:gVolumePanel]; }
    CGFloat width=270.0, height=126.0;
    CGFloat x=MAX(8.0,(host.bounds.size.width-width)/2.0);
    CGFloat y=MAX(host.safeAreaInsets.top+58.0,100.0);
    gVolumePanel.frame=CGRectMake(x,y,width,height);
    for(UIView *v in gVolumePanel.subviews){
        switch(v.tag){
            case 1:v.frame=CGRectMake(10,8,width-20,22);break;
            case 2:v.frame=CGRectMake(10,30,width-20,20);break;
            case 3:v.frame=CGRectMake(16,51,width-32,30);break;
            case 4:v.frame=CGRectMake(16,88,112,28);break;
            case 5:v.frame=CGRectMake(width-128,88,112,28);break;
        }
    }
    UpdateVolumeUI();
    [host bringSubviewToFront:gVolumePanel];
}

static void InstallMuteButton(void){
    dispatch_async(dispatch_get_main_queue(),^{
        if(!IsTikTok()) return;
        UIWindow *host=TTKFindHostWindow();
        if(!host) return;
        if(!gAudioTarget) gAudioTarget=[TTKPlusAudioTarget new];
        InstallVolumePanel(host);
        UIButton *b=gMuteButton;
        if(!b || b.superview!=host){
            if(b) [b removeFromSuperview];
            b=[UIButton buttonWithType:UIButtonTypeSystem];
            b.tag=190611;
            b.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.86];
            b.layer.cornerRadius=12.0;
            b.layer.borderWidth=1.0;
            b.layer.borderColor=UIColor.whiteColor.CGColor;
            b.layer.masksToBounds=YES;
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font=[UIFont boldSystemFontOfSize:13.0];
            b.accessibilityLabel=@"TikTok audio volume";
            b.accessibilityHint=@"Double tap to open TikTok volume control";
            [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            gMuteButton=b;
            [host addSubview:b];
        }
        CGFloat top=MAX(host.safeAreaInsets.top+10.0,44.0);
        CGFloat width=112.0;
        CGFloat x=host.bounds.size.width-width-12.0;
        b.frame=CGRectMake(MAX(8.0,x),top,width,44.0);
        b.hidden=NO;
        b.userInteractionEnabled=YES;
        [host bringSubviewToFront:b];
        if(!gVolumePanel.hidden) [host bringSubviewToFront:gVolumePanel];
        UpdateVolumeUI();
    });
}

void TikTokPlusInstallMuteButton(void){ InstallMuteButton(); }

static void SaveAndHook(Class c,SEL s,IMP r){
    if(!c||!r) return;
    Method m=class_getInstanceMethod(c,s);
    if(!m) return;
    NSString *k=AVKey(c,s);
    if(gAVOriginals[k]) return;
    IMP o=method_getImplementation(m);
    gAVOriginals[k]=[NSValue valueWithBytes:&o objCType:@encode(IMP)];
    method_setImplementation(m,r);
}

static void TTKPlay(id self,SEL sel){
    [gPlayers addObject:self];
    [gAudioObjects addObject:self];
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL))o)(self,sel);
    if(gTikTokMuted) ForceMuteObject(self); else RestoreAudioObject(self);
}
static void TTKSetMuted(id self,SEL sel,BOOL v){
    [gAudioObjects addObject:self];
    if(gTikTokMuted) v=YES;
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,BOOL))o)(self,sel,v);
}
static void TTKSetVolume(id self,SEL sel,float v){
    [gAudioObjects addObject:self];
    if(gBaseVolumes) [gBaseVolumes setObject:@(v) forKey:self];
    float out=gTikTokMuted?0.0f:(v*gTikTokVolume);
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,out);
}
static void TTKSetOutputVolume(id self,SEL sel,float v){
    [gAudioObjects addObject:self];
    if(gBaseVolumes) [gBaseVolumes setObject:@(v) forKey:self];
    float out=gTikTokMuted?0.0f:(v*gTikTokVolume);
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,out);
}
static void TTKEngine(id self,SEL sel,NSError **e){
    [gAudioObjects addObject:self];
    IMP o=AVOriginal(self,sel);
    if(o)((BOOL(*)(id,SEL,NSError**))o)(self,sel,e);
    if(gTikTokMuted && [self respondsToSelector:@selector(mainMixerNode)])
        [[self mainMixerNode]setOutputVolume:0.0f];
}

static void TTKAVPlayerItemSetAudioMix(id self,SEL sel,AVAudioMix *mix){
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,AVAudioMix *))o)(self,sel,gTikTokMuted?nil:mix);
}

static NSArray *TTKAVPlayerItemTracks(id self,SEL sel){
    IMP o=AVOriginal(self,sel);
    NSArray *tracks=o?((NSArray *(*)(id,SEL))o)(self,sel):nil;
    if(!tracks) return tracks;
    for(AVPlayerItemTrack *track in tracks){
        if(track.assetTrack && [track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio])
            track.enabled=!gTikTokMuted;
    }
    return tracks;
}

static void InstallAVPlayerItemHooks(void){
    Class c=NSClassFromString(@"AVPlayerItem");
    SaveAndHook(c,@selector(setAudioMix:),(IMP)TTKAVPlayerItemSetAudioMix);
    SaveAndHook(c,@selector(tracks),(IMP)TTKAVPlayerItemTracks);
}

static void InstallAVHooks(void){
    SaveAndHook(NSClassFromString(@"AVPlayer"),@selector(play),(IMP)TTKPlay);
    SaveAndHook(NSClassFromString(@"AVPlayer"),@selector(setMuted:),(IMP)TTKSetMuted);
    SaveAndHook(NSClassFromString(@"AVPlayer"),@selector(setVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioPlayer"),@selector(play),(IMP)TTKPlay);
    SaveAndHook(NSClassFromString(@"AVAudioPlayer"),@selector(setVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioPlayerNode"),@selector(play),(IMP)TTKPlay);
    SaveAndHook(NSClassFromString(@"AVAudioPlayerNode"),@selector(setVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioMixerNode"),@selector(setOutputVolume:),(IMP)TTKSetOutputVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEnvironmentNode"),@selector(setOutputVolume:),(IMP)TTKSetOutputVolume);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(play),(IMP)TTKPlay);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setMuted:),(IMP)TTKSetMuted);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEngine"),@selector(startAndReturnError:),(IMP)TTKEngine);
    InstallAVPlayerItemHooks();
}

%hook AVMutableAudioMixInputParameters
- (void)setVolume:(float)v {
    %orig(gTikTokMuted?0.0f:(v*gTikTokVolume));
}
%end

%ctor{
    if(!IsTikTok()) return;
    gPlayers=[NSHashTable weakObjectsHashTable];
    gAudioObjects=[NSHashTable weakObjectsHashTable];
    gBaseVolumes=[NSMapTable weakToStrongObjectsMapTable];
    gAVOriginals=[NSMutableDictionary dictionary];
    InstallAVHooks();
    EnsureBackgroundMusicMixing();
    dispatch_async(dispatch_get_main_queue(),^{
        InstallMuteButton();
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){
            InstallMuteButton();
            EnsureBackgroundMusicMixing();
            ApplyMuteState();
        }];
        [[NSNotificationCenter defaultCenter]addObserverForName:@"TikTokPlusToggleMute" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){
            TikTokPlusSetMuted([n.object boolValue]);
        }];
    });
    dispatch_source_t t=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(t,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t,^{
        InstallAVHooks();
        InstallMuteButton();
        EnsureBackgroundMusicMixing();
        ApplyMuteState();
    });
    dispatch_resume(t);
}
