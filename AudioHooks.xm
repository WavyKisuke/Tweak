#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <stdarg.h>

static BOOL gTikTokMuted = NO;
static UIButton *gMuteButton = nil;
static UIButton *gDebugButton = nil;
static UITextView *gDebugView = nil;
static UIView *gDebugPanel = nil;
static NSHashTable<AVPlayer *> *gTrackedPlayers = nil;
static NSHashTable<AVAudioPlayer *> *gTrackedAudioPlayers = nil;
static NSHashTable<AVAudioEngine *> *gTrackedEngines = nil;
static NSHashTable<AVAudioPlayerNode *> *gTrackedPlayerNodes = nil;
static NSHashTable<AVAudioMixerNode *> *gTrackedMixerNodes = nil;
static NSHashTable<AVAudioEnvironmentNode *> *gTrackedEnvironmentNodes = nil;
static NSHashTable<AVSampleBufferAudioRenderer *> *gTrackedSampleRenderers = nil;
static NSMutableArray<NSString *> *gDebugLines = nil;
static dispatch_source_t gMuteTimer = nil;

static BOOL IsTikTokAudio(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *AudioTopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal && w.rootViewController) {
                    if (w.isKeyWindow || !gMuteButton || !gMuteButton.superview) return w;
                }
            }
        }
    }
    return nil;
}

static void DebugLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], msg];
    @synchronized (gDebugLines) {
        if (!gDebugLines) gDebugLines = [NSMutableArray array];
        [gDebugLines addObject:line];
        if (gDebugLines.count > 500) [gDebugLines removeObjectsInRange:NSMakeRange(0, gDebugLines.count - 500)];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDebugView) return;
        NSArray *lines = nil;
        @synchronized (gDebugLines) { lines = [gDebugLines copy]; }
        gDebugView.text = [lines componentsJoinedByString:@"\n"];
        if (gDebugView.text.length) [gDebugView scrollRangeToVisible:NSMakeRange(gDebugView.text.length - 1, 1)];
    });
}

static void TrackPlayer(AVPlayer *p) {
    if (!p || !gTrackedPlayers) return;
    @synchronized(gTrackedPlayers) { [gTrackedPlayers addObject:p]; }
    DebugLog(@"PATH AVPlayer tracked");
}
static void TrackAudioPlayer(AVAudioPlayer *p) {
    if (!p || !gTrackedAudioPlayers) return;
    @synchronized(gTrackedAudioPlayers) { [gTrackedAudioPlayers addObject:p]; }
    DebugLog(@"PATH AVAudioPlayer tracked");
}
static void TrackEngine(AVAudioEngine *e) {
    if (!e || !gTrackedEngines) return;
    @synchronized(gTrackedEngines) { [gTrackedEngines addObject:e]; }
    DebugLog(@"PATH AVAudioEngine tracked");
}
static void TrackPlayerNode(AVAudioPlayerNode *n) {
    if (!n || !gTrackedPlayerNodes) return;
    @synchronized(gTrackedPlayerNodes) { [gTrackedPlayerNodes addObject:n]; }
    DebugLog(@"PATH AVAudioPlayerNode tracked");
}
static void TrackMixerNode(AVAudioMixerNode *n) {
    if (!n || !gTrackedMixerNodes) return;
    @synchronized(gTrackedMixerNodes) { [gTrackedMixerNodes addObject:n]; }
    DebugLog(@"PATH AVAudioMixerNode tracked");
}
static void TrackEnvironmentNode(AVAudioEnvironmentNode *n) {
    if (!n || !gTrackedEnvironmentNodes) return;
    @synchronized(gTrackedEnvironmentNodes) { [gTrackedEnvironmentNodes addObject:n]; }
    DebugLog(@"PATH AVAudioEnvironmentNode tracked");
}
static void TrackSampleRenderer(AVSampleBufferAudioRenderer *r) {
    if (!r || !gTrackedSampleRenderers) return;
    @synchronized(gTrackedSampleRenderers) { [gTrackedSampleRenderers addObject:r]; }
    DebugLog(@"PATH AVSampleBufferAudioRenderer tracked");
}

static void ApplyMuteState(void) {
    DebugLog(@"MUTE STATE = %@ | players=%lu audioPlayers=%lu engines=%lu nodes=%lu mixers=%lu env=%lu sample=%lu", gTikTokMuted ? @"ON" : @"OFF", (unsigned long)gTrackedPlayers.count, (unsigned long)gTrackedAudioPlayers.count, (unsigned long)gTrackedEngines.count, (unsigned long)gTrackedPlayerNodes.count, (unsigned long)gTrackedMixerNodes.count, (unsigned long)gTrackedEnvironmentNodes.count, (unsigned long)gTrackedSampleRenderers.count);
    for (AVPlayer *p in gTrackedPlayers.allObjects) { p.muted = gTikTokMuted; if (gTikTokMuted) p.volume = 0; }
    for (AVAudioPlayer *p in gTrackedAudioPlayers.allObjects) if (gTikTokMuted) p.volume = 0;
    for (AVAudioEngine *e in gTrackedEngines.allObjects) e.mainMixerNode.outputVolume = gTikTokMuted ? 0 : 1;
    for (AVAudioPlayerNode *n in gTrackedPlayerNodes.allObjects) n.volume = gTikTokMuted ? 0 : 1;
    for (AVAudioMixerNode *n in gTrackedMixerNodes.allObjects) n.outputVolume = gTikTokMuted ? 0 : 1;
    for (AVAudioEnvironmentNode *n in gTrackedEnvironmentNodes.allObjects) n.outputVolume = gTikTokMuted ? 0 : 1;
    for (AVSampleBufferAudioRenderer *r in gTrackedSampleRenderers.allObjects) { r.muted = gTikTokMuted; if (gTikTokMuted) r.volume = 0; }
}

@interface TTKPlusAudioTarget : NSObject
@end
@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    DebugLog(@"UI MUTE tapped -> %@", gTikTokMuted ? @"ON" : @"OFF");
    [gMuteButton setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
    ApplyMuteState();
}
- (void)tapDebug:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDebugPanel) return;
        gDebugPanel.hidden = !gDebugPanel.hidden;
        if (!gDebugPanel.hidden && gDebugView.text.length) [gDebugView scrollRangeToVisible:NSMakeRange(gDebugView.text.length - 1, 1)];
    });
}
- (void)tapCloseDebug:(id)sender {
    gDebugPanel.hidden = YES;
}
@end
static TTKPlusAudioTarget *gAudioTarget = nil;

static void InstallDebugOverlay(UIWindow *w) {
    if (gDebugButton || !w) return;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(w.bounds.size.width - 102, 104, 88, 34);
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.68];
    b.layer.cornerRadius = 9;
    [b setTitle:@"DEBUG" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.accessibilityIdentifier = @"TikTokPlusDebugButton";
    [b addTarget:gAudioTarget action:@selector(tapDebug:) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:b];
    gDebugButton = b;

    CGFloat width = MIN(w.bounds.size.width - 24, 520);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(12, 145, width, MIN(w.bounds.size.height - 170, 420))];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.92];
    panel.layer.cornerRadius = 12;
    panel.hidden = YES;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, width - 70, 28)];
    title.text = @"TikTokPlus Audio Diagnostics";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:14];
    [panel addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(width - 48, 5, 40, 34);
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [close addTarget:gAudioTarget action:@selector(tapCloseDebug:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, width - 16, panel.bounds.size.height - 50)];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.35];
    tv.textColor = UIColor.greenColor;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.editable = NO;
    tv.selectable = YES;
    tv.text = @"Waiting for audio events...";
    [panel addSubview:tv];
    [w addSubview:panel];
    gDebugPanel = panel;
    gDebugView = tv;
    DebugLog(@"DEBUG OVERLAY READY");
}

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AudioTopWindow();
        if (!w) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];
        if (!gMuteButton) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(w.bounds.size.width - 102, 60, 88, 38);
            b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.68];
            b.layer.cornerRadius = 10;
            [b setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            b.accessibilityIdentifier = @"TikTokPlusMuteButton";
            [b addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            [w addSubview:b];
            gMuteButton = b;
            DebugLog(@"UI MUTE BUTTON READY");
        }
        InstallDebugOverlay(w);
    });
}

%hook AVPlayer
- (instancetype)init { AVPlayer *p=%orig; if(IsTikTokAudio()) TrackPlayer(p); return p; }
- (instancetype)initWithURL:(NSURL *)u { DebugLog(@"CALL AVPlayer -initWithURL"); AVPlayer *p=%orig; if(IsTikTokAudio()) TrackPlayer(p); return p; }
- (instancetype)initWithPlayerItem:(AVPlayerItem *)i { DebugLog(@"CALL AVPlayer -initWithPlayerItem"); AVPlayer *p=%orig; if(IsTikTokAudio()) TrackPlayer(p); return p; }
- (void)setVolume:(float)v { if(IsTikTokAudio()) { DebugLog(@"CALL AVPlayer setVolume %.3f muted=%d",v,gTikTokMuted); TrackPlayer(self); if(gTikTokMuted)v=0; } %orig(v); }
- (void)setMuted:(BOOL)m { if(IsTikTokAudio()) { DebugLog(@"CALL AVPlayer setMuted %d global=%d",m,gTikTokMuted); TrackPlayer(self); if(gTikTokMuted)m=YES; } %orig(m); }
- (void)play { if(IsTikTokAudio()) DebugLog(@"CALL AVPlayer play muted=%d",gTikTokMuted); if(gTikTokMuted){self.muted=YES;self.volume=0;} %orig; if(gTikTokMuted){self.muted=YES;self.volume=0;} }
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)i { if(IsTikTokAudio())DebugLog(@"CALL AVPlayer replaceCurrentItem"); %orig(i); if(IsTikTokAudio())TrackPlayer(self); if(gTikTokMuted){self.muted=YES;self.volume=0;} }
%end

%hook AVQueuePlayer
+ (instancetype)queuePlayerWithItems:(NSArray *)items { DebugLog(@"CALL AVQueuePlayer +queuePlayerWithItems count=%lu",(unsigned long)items.count); AVQueuePlayer *p=%orig(items); if(IsTikTokAudio())TrackPlayer(p); return p; }
- (instancetype)initWithItems:(NSArray *)items { DebugLog(@"CALL AVQueuePlayer -initWithItems count=%lu",(unsigned long)items.count); AVQueuePlayer *p=%orig(items); if(IsTikTokAudio())TrackPlayer(p); return p; }
- (void)advanceToNextItem { if(IsTikTokAudio())DebugLog(@"CALL AVQueuePlayer advanceToNextItem"); %orig; if(gTikTokMuted){self.muted=YES;self.volume=0;} }
%end

%hook AVPlayerItem
- (instancetype)initWithURL:(NSURL *)u { DebugLog(@"CALL AVPlayerItem -initWithURL %@",u); AVPlayerItem *i=%orig(u); if(IsTikTokAudio())DebugLog(@"PATH AVPlayerItem"); return i; }
- (instancetype)initWithAsset:(AVAsset *)a { DebugLog(@"CALL AVPlayerItem -initWithAsset"); AVPlayerItem *i=%orig(a); if(IsTikTokAudio())DebugLog(@"PATH AVPlayerItem asset"); return i; }
- (void)setAudioMix:(AVAudioMix *)m { if(IsTikTokAudio())DebugLog(@"CALL AVPlayerItem setAudioMix"); %orig(m); }
%end

%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)u error:(NSError **)e { DebugLog(@"CALL AVAudioPlayer initWithContentsOfURL"); AVAudioPlayer *p=%orig(u,e); if(IsTikTokAudio())TrackAudioPlayer(p); return p; }
- (instancetype)initWithData:(NSData *)d error:(NSError **)e { DebugLog(@"CALL AVAudioPlayer initWithData"); AVAudioPlayer *p=%orig(d,e); if(IsTikTokAudio())TrackAudioPlayer(p); return p; }
- (void)setVolume:(float)v { if(IsTikTokAudio()){DebugLog(@"CALL AVAudioPlayer setVolume %.3f",v);TrackAudioPlayer(self);if(gTikTokMuted)v=0;} %orig(v); }
- (BOOL)play { if(IsTikTokAudio())DebugLog(@"CALL AVAudioPlayer play"); if(gTikTokMuted)self.volume=0; BOOL r=%orig; if(gTikTokMuted)self.volume=0; return r; }
%end

%hook AVAudioEngine
- (instancetype)init { DebugLog(@"CALL AVAudioEngine init"); AVAudioEngine *e=%orig; if(IsTikTokAudio())TrackEngine(e); return e; }
- (BOOL)startAndReturnError:(NSError **)e { if(IsTikTokAudio())DebugLog(@"CALL AVAudioEngine start"); BOOL r=%orig(e); if(gTikTokMuted)self.mainMixerNode.outputVolume=0; return r; }
%end

%hook AVAudioPlayerNode
- (instancetype)init { DebugLog(@"CALL AVAudioPlayerNode init"); AVAudioPlayerNode *n=%orig; if(IsTikTokAudio())TrackPlayerNode(n); return n; }
- (void)setVolume:(float)v { if(IsTikTokAudio()){DebugLog(@"CALL AVAudioPlayerNode setVolume %.3f",v);TrackPlayerNode(self);if(gTikTokMuted)v=0;} %orig(v); }
- (void)play { if(gTikTokMuted)self.volume=0; %orig; if(gTikTokMuted)self.volume=0; }
%end

%hook AVAudioMixerNode
- (instancetype)init { DebugLog(@"CALL AVAudioMixerNode init"); AVAudioMixerNode *n=%orig; if(IsTikTokAudio())TrackMixerNode(n); return n; }
- (void)setOutputVolume:(float)v { if(IsTikTokAudio()){DebugLog(@"CALL AVAudioMixerNode setOutputVolume %.3f",v);TrackMixerNode(self);if(gTikTokMuted)v=0;} %orig(v); }
%end

%hook AVAudioEnvironmentNode
- (instancetype)init { DebugLog(@"CALL AVAudioEnvironmentNode init"); AVAudioEnvironmentNode *n=%orig; if(IsTikTokAudio())TrackEnvironmentNode(n); return n; }
- (void)setOutputVolume:(float)v { if(IsTikTokAudio()){DebugLog(@"CALL AVAudioEnvironmentNode setOutputVolume %.3f",v);TrackEnvironmentNode(self);if(gTikTokMuted)v=0;} %orig(v); }
%end

%hook AVSampleBufferAudioRenderer
- (instancetype)init { DebugLog(@"CALL AVSampleBufferAudioRenderer init"); AVSampleBufferAudioRenderer *r=%orig; if(IsTikTokAudio())TrackSampleRenderer(r); return r; }
- (void)setMuted:(BOOL)m { if(IsTikTokAudio()){DebugLog(@"CALL AVSampleBufferAudioRenderer setMuted %d",m);TrackSampleRenderer(self);if(gTikTokMuted)m=YES;} %orig(m); }
- (void)setVolume:(float)v { if(IsTikTokAudio()){DebugLog(@"CALL AVSampleBufferAudioRenderer setVolume %.3f",v);TrackSampleRenderer(self);if(gTikTokMuted)v=0;} %orig(v); }
%end

%ctor {
    if (!IsTikTokAudio()) return;
    gTrackedPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedAudioPlayers = [NSHashTable weakObjectsHashTable];
    gTrackedEngines = [NSHashTable weakObjectsHashTable];
    gTrackedPlayerNodes = [NSHashTable weakObjectsHashTable];
    gTrackedMixerNodes = [NSHashTable weakObjectsHashTable];
    gTrackedEnvironmentNodes = [NSHashTable weakObjectsHashTable];
    gTrackedSampleRenderers = [NSHashTable weakObjectsHashTable];
    gDebugLines = [NSMutableArray array];
    DebugLog(@"TTKPLUS AUDIO DIAGNOSTICS INITIALIZED");
    dispatch_async(dispatch_get_main_queue(), ^{ InstallMuteButton(); });
    gMuteTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gMuteTimer, dispatch_time(DISPATCH_TIME_NOW, 750000000), 750000000, 100000000);
    dispatch_source_set_event_handler(gMuteTimer, ^{ if(gTikTokMuted) ApplyMuteState(); });
    dispatch_resume(gMuteTimer);
}
