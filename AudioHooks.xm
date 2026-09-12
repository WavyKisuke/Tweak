#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL gTikTokMuted=YES;
static UIButton *gMuteButton;
static UIWindow *gMuteWindow;
static id gAudioTarget;
static NSHashTable *gPlayers;
static NSHashTable *gAudioObjects;
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
    AVAudioSessionCategoryOptions o=s.categoryOptions;
    if(o&AVAudioSessionCategoryOptionMixWithOthers) return;
    NSString *c=s.category;
    if(!c.length) return;
    NSError *e=nil;
    BOOL ok=[s setCategory:c mode:s.mode options:o|AVAudioSessionCategoryOptionMixWithOthers error:&e];
    if(!ok && [c isEqualToString:AVAudioSessionCategorySoloAmbient])
        [s setCategory:AVAudioSessionCategoryAmbient mode:s.mode options:o|AVAudioSessionCategoryOptionMixWithOthers error:nil];
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
}

static void ApplyMuteState(void){
    for(id o in gPlayers.allObjects) {
        if(gTikTokMuted) ForceMuteObject(o); else RestoreAudioObject(o);
    }
    for(id o in gAudioObjects.allObjects) {
        if(gTikTokMuted) ForceMuteObject(o); else RestoreAudioObject(o);
    }
}

void TikTokPlusSetMuted(BOOL muted){
    if(!IsTikTok()) return;
    gTikTokMuted=muted;
    dispatch_async(dispatch_get_main_queue(),^{
        [gMuteButton setTitle:muted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal];
    });
    EnsureBackgroundMusicMixing();
    ApplyMuteState();
    [[NSNotificationCenter defaultCenter]postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(muted)}];
}

@interface TTKPlusAudioTarget:NSObject @end
@implementation TTKPlusAudioTarget
-(void)tapMute:(id)sender{ TikTokPlusSetMuted(!gTikTokMuted); }
@end

@interface TTKMuteWindow:UIWindow @end
@implementation TTKMuteWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e{
    UIView *hit=[super hitTest:p withEvent:e];
    if(hit==self || hit==self.rootViewController.view) return nil;
    return hit;
}
@end

static UIWindow *TTKFindHostWindow(void){
    for(UIWindow *w in UIApplication.sharedApplication.windows){
        if(w.hidden || w.alpha<=0.01 || w.windowLevel!=UIWindowLevelNormal) continue;
        if(w.rootViewController && w!=gMuteWindow) return w;
    }
    return nil;
}

static void InstallMuteButton(void){
    dispatch_async(dispatch_get_main_queue(),^{
        if(!IsTikTok()) return;
        UIWindow *host=TTKFindHostWindow();
        if(!host) return;
        if(!gAudioTarget) gAudioTarget=[TTKPlusAudioTarget new];
        if(!gMuteWindow){
            TTKMuteWindow *w=[[TTKMuteWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
            w.backgroundColor=UIColor.clearColor;
            w.windowLevel=UIWindowLevelNormal+1.0;
            w.rootViewController=[UIViewController new];
            w.rootViewController.view.backgroundColor=UIColor.clearColor;
            w.userInteractionEnabled=YES;
            gMuteWindow=w;
        }
        gMuteWindow.frame=host.bounds;
        gMuteWindow.hidden=NO;
        gMuteWindow.rootViewController.view.frame=gMuteWindow.bounds;
        if(!gMuteButton){
            UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
            b.tag=190611;
            b.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.82];
            b.layer.cornerRadius=10.0;
            b.layer.masksToBounds=YES;
            [b setTitle:@"MUTE" forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font=[UIFont boldSystemFontOfSize:14];
            [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            gMuteButton=b;
            [gMuteWindow.rootViewController.view addSubview:b];
        }
        CGFloat top=MAX(host.safeAreaInsets.top+8.0,44.0);
        gMuteButton.frame=CGRectMake(MAX(8.0,host.bounds.size.width-110.0),top,96.0,42.0);
        gMuteButton.hidden=NO;
        [gMuteButton setTitle:gTikTokMuted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal];
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
    if(gTikTokMuted) ForceMuteObject(self);
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL))o)(self,sel);
    if(gTikTokMuted) ForceMuteObject(self);
}
static void TTKSetMuted(id self,SEL sel,BOOL v){
    [gAudioObjects addObject:self];
    if(gTikTokMuted) v=YES;
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,BOOL))o)(self,sel,v);
}
static void TTKSetVolume(id self,SEL sel,float v){
    [gAudioObjects addObject:self];
    if(gTikTokMuted) v=0.0f;
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,float))o)(self,sel,v);
}
static void TTKEngine(id self,SEL sel,NSError **e){
    [gAudioObjects addObject:self];
    IMP o=AVOriginal(self,sel);
    if(o)((BOOL(*)(id,SEL,NSError**))o)(self,sel,e);
    if(gTikTokMuted && [self respondsToSelector:@selector(mainMixerNode)])
        [[self mainMixerNode]setOutputVolume:0.0f];
}

/* Keep the system AV player silent while allowing other/injected audio to remain separate. */
static void TTKAVPlayerItemSetAudioMix(id self,SEL sel,AVAudioMix *mix){
    IMP o=AVOriginal(self,sel);
    if(o)((void(*)(id,SEL,AVAudioMix *))o)(self,sel,nil);
}

static NSArray *TTKAVPlayerItemTracks(id self,SEL sel){
    IMP o=AVOriginal(self,sel);
    NSArray *tracks=o?((NSArray *(*)(id,SEL))o)(self,sel):nil;
    if(!tracks) return tracks;
    for(AVPlayerItemTrack *track in tracks){
        AVAssetTrack *assetTrack=track.assetTrack;
        if(assetTrack && [assetTrack.mediaType isEqualToString:AVMediaTypeAudio])
            track.enabled=NO;
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
    SaveAndHook(NSClassFromString(@"AVAudioMixerNode"),@selector(setOutputVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEnvironmentNode"),@selector(setOutputVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(play),(IMP)TTKPlay);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setMuted:),(IMP)TTKSetMuted);
    SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setVolume:),(IMP)TTKSetVolume);
    SaveAndHook(NSClassFromString(@"AVAudioEngine"),@selector(startAndReturnError:),(IMP)TTKEngine);
    InstallAVPlayerItemHooks();
}

%hook AVMutableAudioMixInputParameters
- (void)setVolume:(float)v {
    if(gTikTokMuted) v=0.0f;
    %orig(v);
}
%end

%ctor{
    if(!IsTikTok()) return;
    gPlayers=[NSHashTable weakObjectsHashTable];
    gAudioObjects=[NSHashTable weakObjectsHashTable];
    gAVOriginals=[NSMutableDictionary dictionary];
    InstallAVHooks();
    EnsureBackgroundMusicMixing();
    dispatch_async(dispatch_get_main_queue(),^{
        InstallMuteButton();
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){ InstallMuteButton(); }];
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
