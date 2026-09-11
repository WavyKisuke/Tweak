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

static BOOL IsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *TopWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    if (window.isKeyWindow || !gMuteButton || !gMuteButton.superview) return window;
                }
            }
        }
    }
    return nil;
}

static void DebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], message];
    if (!gDebugLines) gDebugLines = [NSMutableArray array];
    @synchronized (gDebugLines) {
        [gDebugLines addObject:line];
        if (gDebugLines.count > 500) {
            [gDebugLines removeObjectsInRange:NSMakeRange(0, gDebugLines.count - 500)];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDebugView) return;
        NSArray *lines;
        @synchronized (gDebugLines) { lines = [gDebugLines copy]; }
        gDebugView.text = [lines componentsJoinedByString:@"\n"];
        if (gDebugView.text.length) {
            [gDebugView scrollRangeToVisible:NSMakeRange(gDebugView.text.length - 1, 1)];
        }
    });
}

static void TrackPlayer(AVPlayer *player) {
    if (!player || !gPlayers) return;
    @synchronized (gPlayers) { [gPlayers addObject:player]; }
    DebugLog(@"PATH AVPlayer tracked");
}

static void TrackAudioPlayer(AVAudioPlayer *player) {
    if (!player || !gAudioPlayers) return;
    @synchronized (gAudioPlayers) { [gAudioPlayers addObject:player]; }
    DebugLog(@"PATH AVAudioPlayer tracked");
}

static void TrackEngine(AVAudioEngine *engine) {
    if (!engine || !gEngines) return;
    @synchronized (gEngines) { [gEngines addObject:engine]; }
    DebugLog(@"PATH AVAudioEngine tracked");
}

static void TrackPlayerNode(AVAudioPlayerNode *node) {
    if (!node || !gPlayerNodes) return;
    @synchronized (gPlayerNodes) { [gPlayerNodes addObject:node]; }
    DebugLog(@"PATH AVAudioPlayerNode tracked");
}

static void TrackMixerNode(AVAudioMixerNode *node) {
    if (!node || !gMixerNodes) return;
    @synchronized (gMixerNodes) { [gMixerNodes addObject:node]; }
    DebugLog(@"PATH AVAudioMixerNode tracked");
}

static void TrackEnvironmentNode(AVAudioEnvironmentNode *node) {
    if (!node || !gEnvironmentNodes) return;
    @synchronized (gEnvironmentNodes) { [gEnvironmentNodes addObject:node]; }
    DebugLog(@"PATH AVAudioEnvironmentNode tracked");
}

static void TrackSampleRenderer(AVSampleBufferAudioRenderer *renderer) {
    if (!renderer || !gSampleRenderers) return;
    @synchronized (gSampleRenderers) { [gSampleRenderers addObject:renderer]; }
    DebugLog(@"PATH AVSampleBufferAudioRenderer tracked");
}

static void ApplyMuteState(void) {
    DebugLog(@"MUTE %@ | players=%lu audio=%lu engines=%lu nodes=%lu mixers=%lu env=%lu sample=%lu",
             gTikTokMuted ? @"ON" : @"OFF",
             (unsigned long)gPlayers.count,
             (unsigned long)gAudioPlayers.count,
             (unsigned long)gEngines.count,
             (unsigned long)gPlayerNodes.count,
             (unsigned long)gMixerNodes.count,
             (unsigned long)gEnvironmentNodes.count,
             (unsigned long)gSampleRenderers.count);

    for (AVPlayer *player in gPlayers.allObjects) {
        player.muted = gTikTokMuted;
        if (gTikTokMuted) player.volume = 0.0;
    }
    for (AVAudioPlayer *player in gAudioPlayers.allObjects) {
        if (gTikTokMuted) player.volume = 0.0;
    }
    for (AVAudioEngine *engine in gEngines.allObjects) {
        engine.mainMixerNode.outputVolume = gTikTokMuted ? 0.0 : 1.0;
    }
    for (AVAudioPlayerNode *node in gPlayerNodes.allObjects) {
        node.volume = gTikTokMuted ? 0.0 : 1.0;
    }
    for (AVAudioMixerNode *node in gMixerNodes.allObjects) {
        node.outputVolume = gTikTokMuted ? 0.0 : 1.0;
    }
    for (AVAudioEnvironmentNode *node in gEnvironmentNodes.allObjects) {
        node.outputVolume = gTikTokMuted ? 0.0 : 1.0;
    }
    for (AVSampleBufferAudioRenderer *renderer in gSampleRenderers.allObjects) {
        renderer.muted = gTikTokMuted;
        if (gTikTokMuted) renderer.volume = 0.0;
    }
}

@interface TTKPlusAudioTarget : NSObject
@end

@implementation TTKPlusAudioTarget
- (void)tapMute:(id)sender {
    gTikTokMuted = !gTikTokMuted;
    DebugLog(@"UI MUTE -> %@", gTikTokMuted ? @"ON" : @"OFF");
    [gMuteButton setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
    ApplyMuteState();
}

- (void)tapDebug:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        gDebugPanel.hidden = !gDebugPanel.hidden;
        if (!gDebugPanel.hidden && gDebugView.text.length) {
            [gDebugView scrollRangeToVisible:NSMakeRange(gDebugView.text.length - 1, 1)];
        }
    });
}

- (void)tapCloseDebug:(id)sender {
    gDebugPanel.hidden = YES;
}
@end

static TTKPlusAudioTarget *gAudioTarget = nil;

static void InstallDebugOverlay(UIWindow *window) {
    if (!window || gDebugButton) return;

    UIButton *debugButton = [UIButton buttonWithType:UIButtonTypeSystem];
    debugButton.frame = CGRectMake(window.bounds.size.width - 102, 104, 88, 34);
    debugButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    debugButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
    debugButton.layer.cornerRadius = 9;
    [debugButton setTitle:@"DEBUG" forState:UIControlStateNormal];
    [debugButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    debugButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [debugButton addTarget:gAudioTarget action:@selector(tapDebug:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:debugButton];
    gDebugButton = debugButton;

    CGFloat width = MIN(window.bounds.size.width - 24, 520);
    CGFloat height = MIN(window.bounds.size.height - 170, 420);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(12, 145, width, height)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
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

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, width - 16, height - 50)];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    textView.textColor = UIColor.greenColor;
    textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    textView.editable = NO;
    textView.selectable = YES;
    textView.text = @"Waiting for audio events...";
    [panel addSubview:textView];

    [window addSubview:panel];
    gDebugPanel = panel;
    gDebugView = textView;
    DebugLog(@"DEBUG OVERLAY READY");
}

static void InstallMuteButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = TopWindow();
        if (!window) return;
        if (!gAudioTarget) gAudioTarget = [TTKPlusAudioTarget new];

        if (!gMuteButton) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.frame = CGRectMake(window.bounds.size.width - 102, 60, 88, 38);
            button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
            button.layer.cornerRadius = 10;
            [button setTitle:gTikTokMuted ? @"UNMUTE" : @"MUTE" forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
            [button addTarget:gAudioTarget action:@selector(tapMute:) forControlEvents:UIControlEventTouchUpInside];
            [window addSubview:button];
            gMuteButton = button;
            DebugLog(@"UI MUTE BUTTON READY");
        }
        InstallDebugOverlay(window);
    });
}

%hook AVPlayer
- (instancetype)init {
    AVPlayer *player = %orig;
    if (IsTikTok()) TrackPlayer(player);
    return player;
}

- (instancetype)initWithURL:(NSURL *)URL {
    if (IsTikTok()) DebugLog(@"CALL AVPlayer initWithURL");
    AVPlayer *player = %orig;
    if (IsTikTok()) TrackPlayer(player);
    return player;
}

- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    if (IsTikTok()) DebugLog(@"CALL AVPlayer initWithPlayerItem");
    AVPlayer *player = %orig;
    if (IsTikTok()) TrackPlayer(player);
    return player;
}

- (void)setVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVPlayer setVolume %.3f muted=%d", volume, gTikTokMuted);
        TrackPlayer(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}

- (void)setMuted:(BOOL)muted {
    if (IsTikTok()) {
        DebugLog(@"AVPlayer setMuted %d global=%d", muted, gTikTokMuted);
        TrackPlayer(self);
        if (gTikTokMuted) muted = YES;
    }
    %orig;
}

- (void)play {
    if (IsTikTok()) DebugLog(@"AVPlayer play muted=%d", gTikTokMuted);
    if (gTikTokMuted) { self.muted = YES; self.volume = 0.0; }
    %orig;
    if (gTikTokMuted) { self.muted = YES; self.volume = 0.0; }
}

- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    if (IsTikTok()) DebugLog(@"AVPlayer replaceCurrentItem");
    %orig;
    if (IsTikTok()) TrackPlayer(self);
    if (gTikTokMuted) { self.muted = YES; self.volume = 0.0; }
}
%end

%hook AVQueuePlayer
- (instancetype)initWithItems:(NSArray *)items {
    if (IsTikTok()) DebugLog(@"AVQueuePlayer initWithItems count=%lu", (unsigned long)items.count);
    AVQueuePlayer *player = %orig;
    if (IsTikTok()) TrackPlayer(player);
    return player;
}

- (void)advanceToNextItem {
    if (IsTikTok()) DebugLog(@"AVQueuePlayer advanceToNextItem");
    %orig;
    if (gTikTokMuted) { self.muted = YES; self.volume = 0.0; }
}
%end

%hook AVPlayerItem
- (instancetype)initWithURL:(NSURL *)URL {
    if (IsTikTok()) DebugLog(@"AVPlayerItem initWithURL");
    AVPlayerItem *item = %orig;
    if (IsTikTok()) DebugLog(@"PATH AVPlayerItem");
    return item;
}

- (instancetype)initWithAsset:(AVAsset *)asset {
    if (IsTikTok()) DebugLog(@"AVPlayerItem initWithAsset");
    AVPlayerItem *item = %orig;
    if (IsTikTok()) DebugLog(@"PATH AVPlayerItem asset");
    return item;
}

- (void)setAudioMix:(AVAudioMix *)audioMix {
    if (IsTikTok()) DebugLog(@"AVPlayerItem setAudioMix");
    %orig;
}
%end

%hook AVAudioPlayer
- (instancetype)initWithContentsOfURL:(NSURL *)URL error:(NSError **)error {
    if (IsTikTok()) DebugLog(@"AVAudioPlayer initWithContentsOfURL");
    AVAudioPlayer *player = %orig;
    if (IsTikTok()) TrackAudioPlayer(player);
    return player;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (IsTikTok()) DebugLog(@"AVAudioPlayer initWithData");
    AVAudioPlayer *player = %orig;
    if (IsTikTok()) TrackAudioPlayer(player);
    return player;
}

- (void)setVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVAudioPlayer setVolume %.3f", volume);
        TrackAudioPlayer(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}

- (BOOL)play {
    if (IsTikTok()) DebugLog(@"AVAudioPlayer play");
    if (gTikTokMuted) self.volume = 0.0;
    BOOL result = %orig;
    if (gTikTokMuted) self.volume = 0.0;
    return result;
}
%end

%hook AVAudioEngine
- (instancetype)init {
    if (IsTikTok()) DebugLog(@"AVAudioEngine init");
    AVAudioEngine *engine = %orig;
    if (IsTikTok()) TrackEngine(engine);
    return engine;
}

- (BOOL)startAndReturnError:(NSError **)error {
    if (IsTikTok()) DebugLog(@"AVAudioEngine start");
    BOOL result = %orig;
    if (gTikTokMuted) self.mainMixerNode.outputVolume = 0.0;
    return result;
}
%end

%hook AVAudioPlayerNode
- (instancetype)init {
    if (IsTikTok()) DebugLog(@"AVAudioPlayerNode init");
    AVAudioPlayerNode *node = %orig;
    if (IsTikTok()) TrackPlayerNode(node);
    return node;
}

- (void)setVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVAudioPlayerNode setVolume %.3f", volume);
        TrackPlayerNode(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}

- (void)play {
    if (gTikTokMuted) self.volume = 0.0;
    %orig;
    if (gTikTokMuted) self.volume = 0.0;
}
%end

%hook AVAudioMixerNode
- (instancetype)init {
    if (IsTikTok()) DebugLog(@"AVAudioMixerNode init");
    AVAudioMixerNode *node = %orig;
    if (IsTikTok()) TrackMixerNode(node);
    return node;
}

- (void)setOutputVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVAudioMixerNode setOutputVolume %.3f", volume);
        TrackMixerNode(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}
%end

%hook AVAudioEnvironmentNode
- (instancetype)init {
    if (IsTikTok()) DebugLog(@"AVAudioEnvironmentNode init");
    AVAudioEnvironmentNode *node = %orig;
    if (IsTikTok()) TrackEnvironmentNode(node);
    return node;
}

- (void)setOutputVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVAudioEnvironmentNode setOutputVolume %.3f", volume);
        TrackEnvironmentNode(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}
%end

%hook AVSampleBufferAudioRenderer
- (instancetype)init {
    if (IsTikTok()) DebugLog(@"AVSampleBufferAudioRenderer init");
    AVSampleBufferAudioRenderer *renderer = %orig;
    if (IsTikTok()) TrackSampleRenderer(renderer);
    return renderer;
}

- (void)setMuted:(BOOL)muted {
    if (IsTikTok()) {
        DebugLog(@"AVSampleBufferAudioRenderer setMuted %d", muted);
        TrackSampleRenderer(self);
        if (gTikTokMuted) muted = YES;
    }
    %orig;
}

- (void)setVolume:(float)volume {
    if (IsTikTok()) {
        DebugLog(@"AVSampleBufferAudioRenderer setVolume %.3f", volume);
        TrackSampleRenderer(self);
        if (gTikTokMuted) volume = 0.0;
    }
    %orig;
}
%end

%ctor {
    if (!IsTikTok()) return;

    gPlayers = [NSHashTable weakObjectsHashTable];
    gAudioPlayers = [NSHashTable weakObjectsHashTable];
    gEngines = [NSHashTable weakObjectsHashTable];
    gPlayerNodes = [NSHashTable weakObjectsHashTable];
    gMixerNodes = [NSHashTable weakObjectsHashTable];
    gEnvironmentNodes = [NSHashTable weakObjectsHashTable];
    gSampleRenderers = [NSHashTable weakObjectsHashTable];
    gDebugLines = [NSMutableArray array];

    DebugLog(@"TTKPLUS AUDIO DIAGNOSTICS INITIALIZED");
    dispatch_async(dispatch_get_main_queue(), ^{ InstallMuteButton(); });

    gMuteTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gMuteTimer, dispatch_time(DISPATCH_TIME_NOW, 750000000), 750000000, 100000000);
    dispatch_source_set_event_handler(gMuteTimer, ^{
        if (gTikTokMuted) ApplyMuteState();
    });
    dispatch_resume(gMuteTimer);
}
