#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton;
static id gAudioTarget;
static UIWindow *gMuteWindow;
static NSHashTable *gPlayers;
static NSHashTable *gAudioObjects;
static NSMutableDictionary *gAVOriginals;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindowScene *ActiveScene(void) {
    if (@available(iOS 13.0,*)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static NSString *AVKey(Class cls, SEL sel) { return [NSString stringWithFormat:@"%p:%@",cls,NSStringFromSelector(sel)]; }
static IMP AVOriginal(id self, SEL sel) { Class cls=object_getClass(self); while(cls){ NSValue *v=gAVOriginals[AVKey(cls,sel)]; if(v){ IMP p=NULL; [v getValue:&p]; return p; } cls=class_getSuperclass(cls); } return NULL; }

// Background-audio strategy inspired by PleaseDontStopTheMusic: make TikTok's
// audio session cooperative with music already playing. We never deactivate the
// session and never manipulate the background app's session from inside TikTok.
static void EnsureBackgroundMusicMixing(void) {
    if (!IsTikTok()) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions options = s.categoryOptions;
    if (options & AVAudioSessionCategoryOptionMixWithOthers) return;
    NSString *category = s.category;
    if (!category.length) return;
    NSError *error = nil;
    BOOL ok = [s setCategory:category mode:s.mode options:(options | AVAudioSessionCategoryOptionMixWithOthers) error:&error];
    if (!ok && [category isEqualToString:AVAudioSessionCategorySoloAmbient]) {
        [s setCategory:AVAudioSessionCategoryAmbient mode:s.mode options:(options | AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    }
}

static void ForceMuteObject(id object) {
    if(!object||!gTikTokMuted)return;
    if([object respondsToSelector:@selector(setMuted:)]) [object setMuted:YES];
    if([object respondsToSelector:@selector(setVolume:)]) [object setVolume:0.0f];
    if([object respondsToSelector:@selector(setOutputVolume:)]) [object setOutputVolume:0.0f];
}
static void ApplyMuteState(void) { if(!gTikTokMuted)return; for(id o in gPlayers.allObjects)ForceMuteObject(o); for(id o in gAudioObjects.allObjects)ForceMuteObject(o); }

void TikTokPlusSetMuted(BOOL muted) {
    if(!IsTikTok()) return;
    gTikTokMuted=muted;
    dispatch_async(dispatch_get_main_queue(),^{
        [gMuteButton setTitle:gTikTokMuted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal];
    });
    EnsureBackgroundMusicMixing();
    ApplyMuteState();
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(muted)}];
}

@interface TTKPlusAudioTarget:NSObject @end
@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender { TikTokPlusSetMuted(!gTikTokMuted); }
@end

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        if (!IsTikTok()) return;
        UIWindowScene *scene = ActiveScene();
        if (!scene) return;
        if (!gAudioTarget) gAudioTarget=[TTKPlusAudioTarget new];
        if (!gMuteWindow) {
            gMuteWindow=[[UIWindow alloc] initWithWindowScene:scene];
            gMuteWindow.backgroundColor=UIColor.clearColor;
            gMuteWindow.windowLevel=UIWindowLevelAlert + 1.0;
            gMuteWindow.rootViewController=[UIViewController new];
            gMuteWindow.rootViewController.view.backgroundColor=UIColor.clearColor;
            gMuteWindow.userInteractionEnabled=YES;
        } else if (gMuteWindow.windowScene != scene) {
            gMuteWindow.windowScene=scene;
        }
        gMuteWindow.frame=scene.coordinateSpace.bounds;
        if (!gMuteButton) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            button.frame=CGRectMake(MAX(8.0,gMuteWindow.bounds.size.width-110.0),60.0,96.0,42.0);
            button.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleBottomMargin;
            button.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.82];
            button.layer.cornerRadius=10.0;
            button.layer.zPosition=10000.0;
            [button setTitle:gTikTokMuted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont boldSystemFontOfSize:14.0];
            [button addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            [gMuteWindow.rootViewController.view addSubview:button];
            gMuteButton=button;
        }
        gMuteButton.frame=CGRectMake(MAX(8.0,gMuteWindow.bounds.size.width-110.0),60.0,96.0,42.0);
        gMuteButton.hidden=NO;
        gMuteButton.alpha=1.0;
        [gMuteWindow makeKeyAndVisible];
    });
}

void TikTokPlusInstallMuteButton(void){if(IsTikTok())InstallMuteButton();}
static void SaveAndHook(Class cls,SEL sel,IMP replacement){if(!cls||!replacement)return;Method m=class_getInstanceMethod(cls,sel);if(!m)return;NSString *key=AVKey(cls,sel);if(gAVOriginals[key])return;IMP original=method_getImplementation(m);gAVOriginals[key]=[NSValue valueWithBytes:&original objCType:@encode(IMP)];method_setImplementation(m,replacement);}
static void TTK_AVPlayerPlay(id self,SEL cmd){[gPlayers addObject:self];if(gTikTokMuted)ForceMuteObject(self);IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL))o)(self,cmd);if(gTikTokMuted)ForceMuteObject(self);}
static void TTK_AVPlayerSetMuted(id self,SEL cmd,BOOL value){if(gTikTokMuted)value=YES;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,BOOL))o)(self,cmd,value);}
static void TTK_AVPlayerSetVolume(id self,SEL cmd,float value){if(gTikTokMuted)value=0.0f;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,float))o)(self,cmd,value);}
static void TTK_AVAudioPlayerPlay(id self,SEL cmd){[gAudioObjects addObject:self];if(gTikTokMuted)ForceMuteObject(self);IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL))o)(self,cmd);if(gTikTokMuted)ForceMuteObject(self);}
static void TTK_AVAudioPlayerSetVolume(id self,SEL cmd,float value){if(gTikTokMuted)value=0.0f;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,float))o)(self,cmd,value);}
static void TTK_AVAudioPlayerNodePlay(id self,SEL cmd){[gAudioObjects addObject:self];if(gTikTokMuted)ForceMuteObject(self);IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL))o)(self,cmd);if(gTikTokMuted)ForceMuteObject(self);}
static void TTK_AVAudioMixerSetOutputVolume(id self,SEL cmd,float value){if(gTikTokMuted)value=0.0f;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,float))o)(self,cmd,value);}
static void TTK_AVAudioEnvironmentSetOutputVolume(id self,SEL cmd,float value){if(gTikTokMuted)value=0.0f;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,float))o)(self,cmd,value);}
static void TTK_AVSamplePlay(id self,SEL cmd){[gAudioObjects addObject:self];if(gTikTokMuted)ForceMuteObject(self);IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL))o)(self,cmd);if(gTikTokMuted)ForceMuteObject(self);}
static void TTK_AVSampleSetMuted(id self,SEL cmd,BOOL value){if(gTikTokMuted)value=YES;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,BOOL))o)(self,cmd,value);}
static void TTK_AVSampleSetVolume(id self,SEL cmd,float value){if(gTikTokMuted)value=0.0f;IMP o=AVOriginal(self,cmd);if(o)((void(*)(id,SEL,float))o)(self,cmd,value);}
static BOOL TTK_AVAudioEngineStart(id self,SEL cmd,NSError **error){IMP o=AVOriginal(self,cmd);BOOL r=o?((BOOL(*)(id,SEL,NSError**))o)(self,cmd,error):NO;if(gTikTokMuted&&[self respondsToSelector:@selector(mainMixerNode)])[[self mainMixerNode]setOutputVolume:0.0f];return r;}
static BOOL IsSubclassOf(Class cls,Class parent){while(cls){if(cls==parent)return YES;cls=class_getSuperclass(cls);}return NO;}
static BOOL ClassDefinesSelector(Class cls,SEL sel){unsigned int n=0;Method *ms=class_copyMethodList(cls,&n);BOOL found=NO;for(unsigned int i=0;i<n;i++)if(method_getName(ms[i])==sel){found=YES;break;}free(ms);return found;}
static void InstallAVHooks(void){Class player=NSClassFromString(@"AVPlayer");SaveAndHook(player,@selector(play),(IMP)TTK_AVPlayerPlay);SaveAndHook(player,@selector(setMuted:),(IMP)TTK_AVPlayerSetMuted);SaveAndHook(player,@selector(setVolume:),(IMP)TTK_AVPlayerSetVolume);if(player){int count=objc_getClassList(NULL,0);if(count>0){Class *classes=(Class*)malloc(sizeof(Class)*count);count=objc_getClassList(classes,count);for(int i=0;i<count;i++){Class cls=classes[i];if(cls==player||!IsSubclassOf(cls,player))continue;if(ClassDefinesSelector(cls,@selector(play)))SaveAndHook(cls,@selector(play),(IMP)TTK_AVPlayerPlay);if(ClassDefinesSelector(cls,@selector(setMuted:)))SaveAndHook(cls,@selector(setMuted:),(IMP)TTK_AVPlayerSetMuted);if(ClassDefinesSelector(cls,@selector(setVolume:)))SaveAndHook(cls,@selector(setVolume:),(IMP)TTK_AVPlayerSetVolume);}free(classes);}}SaveAndHook(NSClassFromString(@"AVAudioPlayer"),@selector(play),(IMP)TTK_AVAudioPlayerPlay);SaveAndHook(NSClassFromString(@"AVAudioPlayer"),@selector(setVolume:),(IMP)TTK_AVAudioPlayerSetVolume);SaveAndHook(NSClassFromString(@"AVAudioPlayerNode"),@selector(play),(IMP)TTK_AVAudioPlayerNodePlay);SaveAndHook(NSClassFromString(@"AVAudioMixerNode"),@selector(setOutputVolume:),(IMP)TTK_AVAudioMixerSetOutputVolume);SaveAndHook(NSClassFromString(@"AVAudioEnvironmentNode"),@selector(setOutputVolume:),(IMP)TTK_AVAudioEnvironmentSetOutputVolume);SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(play),(IMP)TTK_AVSamplePlay);SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setMuted:),(IMP)TTK_AVSampleSetMuted);SaveAndHook(NSClassFromString(@"AVSampleBufferAudioRenderer"),@selector(setVolume:),(IMP)TTK_AVSampleSetVolume);SaveAndHook(NSClassFromString(@"AVAudioEngine"),@selector(startAndReturnError:),(IMP)TTK_AVAudioEngineStart);}
%ctor {if(!IsTikTok())return;gPlayers=[NSHashTable weakObjectsHashTable];gAudioObjects=[NSHashTable weakObjectsHashTable];gAVOriginals=[NSMutableDictionary dictionary];InstallAVHooks();EnsureBackgroundMusicMixing();dispatch_async(dispatch_get_main_queue(),^{InstallMuteButton();});dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);dispatch_source_set_event_handler(timer,^{InstallAVHooks();InstallMuteButton();EnsureBackgroundMusicMixing();if(gTikTokMuted)ApplyMuteState();});dispatch_resume(timer);}
