#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void TikTokPlusInstallMuteButton(void);

static UIButton *gSaveButton = nil;
static NSURL *gCurrentVideoURL = nil;
static BOOL gAdBlockEnabled = YES;

static BOOL IsTikTok(void) {
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.zhiliaoapp.musically"];
}

static UIWindow *TopWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!w.hidden && w.alpha > 0.01 && w.windowLevel == UIWindowLevelNormal) return w;
        }
    }
    return nil;
}

static UIViewController *TopController(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:UINavigationController.class]) return TopController(((UINavigationController *)vc).visibleViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return TopController(((UITabBarController *)vc).selectedViewController);
    if (vc.presentedViewController) return TopController(vc.presentedViewController);
    return vc;
}

static void ShowMessage(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = TopWindow();
        UIViewController *vc = TopController(w.rootViewController);
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"TikTokPlus" message:text preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static void SaveCurrentVideo(void) {
    NSURL *url = gCurrentVideoURL;
    if (!url) { ShowMessage(@"No video URL captured yet. Play the video for a moment, then tap HD SAVE."); return; }
    NSString *lower = url.absoluteString.lowercaseString;
    if ([lower containsString:@".m3u8"]) { ShowMessage(@"This clip uses an HLS playlist. The direct-file saver cannot export that stream."); return; }
    if (![url.scheme.lowercaseString isEqualToString:@"http"] && ![url.scheme.lowercaseString isEqualToString:@"https"]) { ShowMessage(@"The captured video URL is not a downloadable HTTP(S) file."); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 60.0;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    req.HTTPShouldHandleCookies = YES;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"TikTok/46.8.0 iPhone" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) { ShowMessage(@"Download failed. TikTok may require a different stream or authorization."); return; }
        NSString *name = [NSString stringWithFormat:@"TikTok_%lld.mp4", (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
        NSURL *dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        NSError *moveError = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:&moveError];
        if (moveError) { ShowMessage(@"Could not save the downloaded file."); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *w = TopWindow();
            UIViewController *vc = TopController(w.rootViewController);
            if (!vc) return;
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[dest] applicationActivities:nil];
            if (share.popoverPresentationController) {
                share.popoverPresentationController.sourceView = gSaveButton;
                share.popoverPresentationController.sourceRect = gSaveButton.bounds;
            }
            [vc presentViewController:share animated:YES completion:nil];
        });
    }];
    [task resume];
}

@interface TTKPlusSaveTarget : NSObject
@end
@implementation TTKPlusSaveTarget
- (void)tapSave:(id)sender { SaveCurrentVideo(); }
@end
static TTKPlusSaveTarget *gSaveTarget = nil;

static void InstallSaveButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = TopWindow(); if (!w) return;
        if (gSaveButton && gSaveButton.superview) return;
        if (!gSaveTarget) gSaveTarget = [TTKPlusSaveTarget new];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(w.bounds.size.width - 102, 104, 88, 38);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
        b.layer.cornerRadius = 10;
        b.layer.masksToBounds = YES;
        [b setTitle:@"HD SAVE" forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        b.accessibilityIdentifier = @"TikTokPlusSaveButton";
        [b addTarget:gSaveTarget action:@selector(tapSave:) forControlEvents:UIControlEventTouchUpInside];
        [w addSubview:b]; gSaveButton = b;
    });
}

static BOOL TextLooksLikeAd(NSString *text) {
    if (!text.length) return NO;
    NSString *s = text.lowercaseString;
    NSArray *markers = @[@"sponsored", @"promoted", @"advertisement", @"paid partnership", @"ad ·", @"ad •"];
    for (NSString *m in markers) if ([s containsString:m]) return YES;
    return NO;
}

static BOOL ClassLooksLikeAd(UIView *v) {
    NSString *n = NSStringFromClass(v.class).lowercaseString;
    NSArray *tokens = @[@"sponsored", @"advertisement", @"promoted", @"adcell", @"adview", @"adcontainer", @"awead", @"ttkad"];
    for (NSString *t in tokens) if ([n containsString:t]) return YES;
    return NO;
}

static BOOL ViewLooksLikeAd(UIView *v) {
    if (ClassLooksLikeAd(v)) return YES;
    if ([v isKindOfClass:UILabel.class] && TextLooksLikeAd(((UILabel *)v).text)) return YES;
    if ([v isKindOfClass:UIButton.class] && TextLooksLikeAd([((UIButton *)v) titleForState:UIControlStateNormal])) return YES;
    return TextLooksLikeAd(v.accessibilityLabel);
}

static void ScanForAds(UIView *root) {
    if (!gAdBlockEnabled || !root.window) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v != gSaveButton && ViewLooksLikeAd(v)) v.hidden = YES;
        for (UIView *sub in v.subviews) if (sub != gSaveButton) [stack addObject:sub];
    }
}

%hook AVURLAsset
- (instancetype)initWithURL:(NSURL *)URL options:(NSDictionary *)options {
    if (IsTikTok() && URL) gCurrentVideoURL = URL;
    return %orig;
}
- (NSURL *)URL {
    NSURL *u = %orig;
    if (IsTikTok() && u) gCurrentVideoURL = u;
    return u;
}
%end

%hook AVPlayerItem
+ (instancetype)playerItemWithURL:(NSURL *)URL {
    if (IsTikTok() && URL) gCurrentVideoURL = URL;
    return %orig;
}
- (instancetype)initWithURL:(NSURL *)URL {
    if (IsTikTok() && URL) gCurrentVideoURL = URL;
    return %orig;
}
- (instancetype)initWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)keys {
    if (IsTikTok() && [asset isKindOfClass:AVURLAsset.class]) gCurrentVideoURL = ((AVURLAsset *)asset).URL;
    return %orig;
}
%end

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    if (IsTikTok() && [item.asset isKindOfClass:AVURLAsset.class]) gCurrentVideoURL = ((AVURLAsset *)item.asset).URL;
    %orig(item);
}
%end

%ctor {
    if (!IsTikTok()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallSaveButton();
        TikTokPlusInstallMuteButton();
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 250 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        InstallSaveButton();
        TikTokPlusInstallMuteButton();
        if (gAdBlockEnabled) { UIWindow *w = TopWindow(); if (w && w.rootViewController.view) ScanForAds(w.rootViewController.view); }
    });
    dispatch_resume(timer);
}
