#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <stdarg.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static UIButton *gDebugButton = nil;
static UITextView *gDebugView = nil;
static UIView *gDebugPanel = nil;
static NSMutableArray<NSString *> *gDebugLines = nil;
static NSHashTable<AVPlayer *> *gPlayers = nil;
static NSHashTable<AVAudioPlayer *> *gAudioPlayers = nil;
static NSHashTable<AVAudioEngine *> *gEngines = nil;
static NSHashTable<AVAudioPlayerNode *> *gPlayerNodes = nil;
static NSHashTable<AVAudioMixerNode *> *gMixerNodes = nil;
static NSHashTable<AVAudioEnvironmentNode *> *gEnvironmentNodes = nil;
static NSHashTable<AVSampleBufferAudioRenderer *> *gSampleRenderers = nil;
static dispatch_source_t gMuteTimer = nil;

static BOOL IsTikTok(void) { return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"]; }

static UIWindow *TopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindow *fallback = nil;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0.01 || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
                if (window.isKeyWindow) return window;
                if (!fallback) fallback = window;
            }
            if (fallback) return fallback;
        }
    }
    return nil;
}

static void DebugLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], message];
    if (!gDebugLines) gDebugLines = [NSMutableArray array];
    @synchronized (gDebugLines) { [gDebugLines addObject:line]; if (gDebugLines.count > 500) [gDebugLines removeObjectsInRange:NSMakeRange(0, gDebugLines.count - 500)]; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDebugView) return;
        NSArray *lines; @synchronized (gDebugLines) { lines = [gDebugLines copy]; }
        gDebugView.text = [lines componentsJoinedByString:@"\n"];
        if (gDebugView.text.length) [gDebugView scrollRangeToVisible:NSMakeRange(gDebugView.text.length - 1, 1)];
    });
}

static void TrackPlayer(AVPlayer *p) { if (!p || !gPlayers) return; @synchronized(gPlayers){[gPlayers addObject:p];} DebugLog(@"PATH AVPlayer tracked"); }
static void TrackAudioPlayer(AVAudioPlayer *p) { if (!p || !gAudioPlayers) return; @synchronized(gAudioPlayers){[gAudioPlayers addObject:p];} DebugLog(@"PATH AVAudioPlayer tracked"); }
static void TrackEngine(AVAudioEngine *p) { if (!p || !gEngines) return; @synchronized(gEngines){[gEngines addObject:p];} DebugLog(@"PATH AVAudioEngine tracked"); }
static void TrackPlayerNode(AVAudioPlayerNode *p) { if (!p || !gPlayerNodes) return; @synchronized(gPlayerNodes){[gPlayerNodes addObject:p];} DebugLog(@"PATH AVAudioPlayerNode tracked"); }
static void TrackMixerNode(AVAudioMixerNode *p) { if (!p || !gMixerNodes) return; @synchronized(gMixerNodes){[gMixerNodes addObject:p];} DebugLog(@"PATH AVAudioMixerNode tracked"); }
static void TrackEnvironmentNode(AVAudioEnvironmentNode *p) { if (!p || !gEnvironmentNodes) return; @synchronized(gEnvironmentNodes){[gEnvironmentNodes addObject:p];} DebugLog(@"PATH AVAudioEnvironmentNode tracked"); }
static void TrackSampleRenderer(AVSampleBufferAudioRenderer *p) { if (!p || !gSampleRenderers) return; @synchronized(gSampleRenderers){[gSampleRenderers addObject:p];} DebugLog(@"PATH AVSampleBufferAudioRenderer tracked"); }

static void ApplyMuteState(void) {
    DebugLog(@"MUTE %@ players=%lu audio=%lu engines=%lu nodes=%lu mixers=%lu env=%lu sample=%lu", gTikTokMuted?@"ON":@"OFF", (unsigned long)gPlayers.count,(unsigned long)gAudioPlayers.count,(unsigned long)gEngines.count,(unsigned long)gPlayerNodes.count,(unsigned long)gMixerNodes.count,(unsigned long)gEnvironmentNodes.count,(unsigned long)gSampleRenderers.count);
    for (AVPlayer *p in gPlayers.allObjects) { p.muted=gTikTokMuted; if(gTikTokMuted)p.volume=0.0; }
    for (AVAudioPlayer *p in gAudioPlayers.allObjects) if(gTikTokMuted)p.volume=0.0;
    for (AVAudioEngine *e in gEngines.allObjects) e.mainMixerNode.outputVolume=gTikTokMuted?0.0:1.0;
    for (AVAudioPlayerNode *n in gPlayerNodes.allObjects) n.volume=gTikTokMuted?0.0:1.0;
    for (AVAudioMixerNode *n in gMixerNodes.allObjects) n.outputVolume=gTikTokMuted?0.0:1.0;
    for (AVAudioEnvironmentNode *n in gEnvironmentNodes.allObjects) n.outputVolume=gTikTokMuted?0.0:1.0;
    for (AVSampleBufferAudioRenderer *r in gSampleRenderers.allObjects) { r.muted=gTikTokMuted; if(gTikTokMuted)r.volume=0.0; }
}

// Public bridge used by the standalone UI and private TikTok audio bridge.
void TikTokPlusSetMuted(BOOL muted) {
    if (!IsTikTok()) return;
    gTikTokMuted = muted;
    DebugLog(@"BRIDGE MUTE -> %@", muted?@"ON":@"OFF");
    dispatch_async(dispatch_get_main_queue(), ^{ [gMuteButton setTitle:gTikTokMuted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal]; });
    ApplyMuteState();
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TikTokPlusMuteChanged" object:nil userInfo:@{@"muted":@(muted)}];
}

@interface TTKPlusAudioTarget : NSObject @end
@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender { TikTokPlusSetMuted(!gTikTokMuted); }
- (void)tapDebug:(id)sender { dispatch_async(dispatch_get_main_queue(), ^{ gDebugPanel.hidden=!gDebugPanel.hidden; }); }
- (void)tapCloseDebug:(id)sender { gDebugPanel.hidden=YES; }
@end

static TTKPlusAudioTarget *gAudioTarget=nil;
static void InstallDebugOverlay(UIWindow *window) {
    if(!window||gDebugButton)return;
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; b.frame=CGRectMake(window.bounds.size.width-102,104,88,34); b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin; b.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.68]; b.layer.cornerRadius=9; [b setTitle:@"DEBUG" forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:13]; [b addTarget:gAudioTarget action:@selector(tapDebug:) forControlEvents:UIControlEventTouchUpInside]; [window addSubview:b]; gDebugButton=b;
    CGFloat w=MIN(window.bounds.size.width-24,520),h=MIN(window.bounds.size.height-170,420); UIView *panel=[[UIView alloc]initWithFrame:CGRectMake(12,145,w,h)]; panel.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; panel.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.92]; panel.layer.cornerRadius=12; panel.hidden=YES;
    UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(12,8,w-70,28)]; title.text=@"TikTokPlus Audio Diagnostics"; title.textColor=UIColor.whiteColor; title.font=[UIFont boldSystemFontOfSize:14]; [panel addSubview:title];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem]; close.frame=CGRectMake(w-48,5,40,34); [close setTitle:@"×" forState:UIControlStateNormal]; [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; close.titleLabel.font=[UIFont boldSystemFontOfSize:24]; [close addTarget:gAudioTarget action:@selector(tapCloseDebug:) forControlEvents:UIControlEventTouchUpInside]; [panel addSubview:close];
    UITextView *tv=[[UITextView alloc]initWithFrame:CGRectMake(8,42,w-16,h-50)]; tv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; tv.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.35]; tv.textColor=UIColor.greenColor; tv.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]; tv.editable=NO; tv.text=@"Waiting for audio events..."; [panel addSubview:tv]; [window addSubview:panel]; gDebugPanel=panel; gDebugView=tv; DebugLog(@"DEBUG OVERLAY READY");
}
static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ UIWindow *window=TopWindow(); if(!window)return; if(!gAudioTarget)gAudioTarget=[TTKPlusAudioTarget new];
        if(gMuteButton && gMuteButton.superview==window){[window bringSubviewToFront:gMuteButton];return;}
        [gMuteButton removeFromSuperview]; UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; b.frame=CGRectMake(window.bounds.size.width-102,60,88,38); b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin; b.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:.68]; b.layer.cornerRadius=10; [b setTitle:gTikTokMuted?@"UNMUTE":@"MUTE" forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside]; [window addSubview:b]; gMuteButton=b; InstallDebugOverlay(window); DebugLog(@"UI MUTE BUTTON READY"); });
}

%hook AVPlayer
- (instancetype)init { AVPlayer *p=%orig; if(IsTikTok())TrackPlayer(p); return p; }
- (instancetype)initWithURL:(NSURL *)URL { if(IsTikTok())DebugLog(@"CALL AVPlayer initWithURL"); AVPlayer *p=%orig; if(IsTikTok())TrackPlayer(p); return p; }
- (void)play { if(IsTikTok()&&gTikTokMuted){self.muted=YES;self.volume=0;} %orig; if(IsTikTok()&&gTikTokMuted){self.muted=YES;self.volume=0;} }
- (void)setMuted:(BOOL)muted { if(IsTikTok()&&gTikTokMuted)muted=YES; %orig; }
- (void)setVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVQueuePlayer
- (instancetype)init { AVQueuePlayer*p=%orig; if(IsTikTok())TrackPlayer(p); return p; }
- (void)play { if(IsTikTok()&&gTikTokMuted){self.muted=YES;self.volume=0;} %orig; if(IsTikTok()&&gTikTokMuted){self.muted=YES;self.volume=0;} }
- (void)setMuted:(BOOL)muted { if(IsTikTok()&&gTikTokMuted)muted=YES; %orig; }
- (void)setVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error { AVAudioPlayer*p=%orig; if(IsTikTok())TrackAudioPlayer(p); return p; }
- (void)play { if(IsTikTok()&&gTikTokMuted)self.volume=0; %orig; if(IsTikTok()&&gTikTokMuted)self.volume=0; }
- (void)setVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVAudioEngine
- (instancetype)init { AVAudioEngine*e=%orig; if(IsTikTok())TrackEngine(e); return e; }
- (void)startAndReturnError:(NSError **)error { %orig; if(IsTikTok()&&gTikTokMuted)self.mainMixerNode.outputVolume=0; }
%end
%hook AVAudioPlayerNode
- (instancetype)init { AVAudioPlayerNode*n=%orig; if(IsTikTok())TrackPlayerNode(n); return n; }
- (void)play { if(IsTikTok()&&gTikTokMuted)self.volume=0; %orig; if(IsTikTok()&&gTikTokMuted)self.volume=0; }
- (void)setVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVAudioMixerNode
- (instancetype)init { AVAudioMixerNode*n=%orig; if(IsTikTok())TrackMixerNode(n); return n; }
- (void)setOutputVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVAudioEnvironmentNode
- (instancetype)init { AVAudioEnvironmentNode*n=%orig; if(IsTikTok())TrackEnvironmentNode(n); return n; }
- (void)setOutputVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end
%hook AVSampleBufferAudioRenderer
- (instancetype)init { AVSampleBufferAudioRenderer*r=%orig; if(IsTikTok())TrackSampleRenderer(r); return r; }
- (void)setMuted:(BOOL)muted { if(IsTikTok()&&gTikTokMuted)muted=YES; %orig; }
- (void)setVolume:(float)volume { if(IsTikTok()&&gTikTokMuted)volume=0; %orig; }
%end

%ctor {
    if(!IsTikTok())return;
    gPlayers=[NSHashTable weakObjectsHashTable]; gAudioPlayers=[NSHashTable weakObjectsHashTable]; gEngines=[NSHashTable weakObjectsHashTable]; gPlayerNodes=[NSHashTable weakObjectsHashTable]; gMixerNodes=[NSHashTable weakObjectsHashTable]; gEnvironmentNodes=[NSHashTable weakObjectsHashTable]; gSampleRenderers=[NSHashTable weakObjectsHashTable]; gDebugLines=[NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(), ^{
        InstallMuteButton();
        [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification*n){InstallMuteButton();}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{InstallMuteButton();});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{InstallMuteButton();});
    });
    gMuteTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue()); dispatch_source_set_timer(gMuteTimer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),(uint64_t)(1*NSEC_PER_SEC),(uint64_t)(100*NSEC_PER_MSEC)); dispatch_source_set_event_handler(gMuteTimer,^{if(gTikTokMuted)ApplyMuteState();InstallMuteButton();}); dispatch_resume(gMuteTimer);
}
