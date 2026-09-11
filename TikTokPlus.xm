#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static NSMutableOrderedSet<NSURL *> *gVideoURLs;
static UIButton *gDownloadButton;
static UIButton *gAdButton;
static BOOL gAdBlockEnabled = YES;

static void EnsureState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gVideoURLs = [NSMutableOrderedSet orderedSetWithCapacity:16];
    });
}

static BOOL LooksLikeVideoURL(NSURL *url) {
    if (!url) return NO;
    NSString *s = url.absoluteString.lowercaseString;
    if (s.length < 10 || [s hasPrefix:@"blob:"]) return NO;
    if ([s containsString:@".mp4"] || [s containsString:@"video"] ||
        [s containsString:@"aweme"] || [s containsString:@"muscdn"] ||
        [s containsString:@"bytecdn"] || [s containsString:@"tiktokcdn"]) return YES;
    return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"];
}

static void TrackVideoURL(NSURL *url) {
    EnsureState();
    if (!LooksLikeVideoURL(url)) return;
    @synchronized (gVideoURLs) {
        [gVideoURLs removeObject:url];
        [gVideoURLs insertObject:url atIndex:0];
        while (gVideoURLs.count > 16) [gVideoURLs removeLastObject];
    }
}

static NSURL *CurrentVideoURL(void) {
    EnsureState();
    @synchronized (gVideoURLs) {
        return gVideoURLs.firstObject;
    }
}

static UIWindow *TopWindow(void) {
    UIWindow *best = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.hidden || w.alpha < 0.01 || w.windowLevel != UIWindowLevelNormal) continue;
                if (!w.rootViewController) continue;
                best = w;
                if (w.isKeyWindow) return w;
            }
        }
    }
    return best ?: UIApplication.sharedApplication.keyWindow;
}

static UIViewController *TopController(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:UINavigationController.class]) return TopController(((UINavigationController *)vc).visibleViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return TopController(((UITabBarController *)vc).selectedViewController);
    if (vc.presentedViewController) return TopController(vc.presentedViewController);
    return vc;
}

static void PresentMessage(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopController(TopWindow().rootViewController);
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static void ShareFile(NSURL *fileURL) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = TopController(TopWindow().rootViewController);
        if (!vc) return;
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        if (share.popoverPresentationController) {
            share.popoverPresentationController.sourceView = gDownloadButton;
            share.popoverPresentationController.sourceRect = gDownloadButton.bounds;
        }
        [vc presentViewController:share animated:YES completion:nil];
    });
}

static void DownloadCurrentVideo(void) {
    NSURL *url = CurrentVideoURL();
    if (!url) {
        PresentMessage(@"TikTok Plus", @"No direct video URL has been captured yet. Play the video for a moment, then try again.");
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 30.0;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"TikTok/46.8.0 iPhone" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            PresentMessage(@"Download failed", error.localizedDescription ?: @"TikTok did not return a downloadable video.");
            return;
        }
        NSString *name = [NSString stringWithFormat:@"TikTok_%lld.mp4", (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
        NSURL *dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        NSError *moveError = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dest error:&moveError];
        if (moveError) {
            PresentMessage(@"Download failed", moveError.localizedDescription);
            return;
        }
        ShareFile(dest);
    }];
    [task resume];
}

@interface TTKPlusButtonTarget : NSObject
@end

@implementation TTKPlusButtonTarget
- (void)downloadTap:(UIButton *)sender { DownloadCurrentVideo(); }
- (void)adTap:(UIButton *)sender {
    gAdBlockEnabled = !gAdBlockEnabled;
    [sender setTitle:(gAdBlockEnabled ? @"ADBLOCK" : @"ADS") forState:UIControlStateNormal];
}
@end

static TTKPlusButtonTarget *gButtonTarget;

static void InstallButtons(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = TopWindow();
        if (!w) return;
        if (!gButtonTarget) gButtonTarget = [TTKPlusButtonTarget new];
        if (!gDownloadButton) {
            gDownloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
            gDownloadButton.frame = CGRectMake(20, 165, 112, 36);
            gDownloadButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
            gDownloadButton.layer.cornerRadius = 18;
            gDownloadButton.clipsToBounds = YES;
            [gDownloadButton setTitle:@"HD SAVE" forState:UIControlStateNormal];
            [gDownloadButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            gDownloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [gDownloadButton addTarget:gButtonTarget action:@selector(downloadTap:) forControlEvents:UIControlEventTouchUpInside];
            [w addSubview:gDownloadButton];
        }
        if (!gAdButton) {
            gAdButton = [UIButton buttonWithType:UIButtonTypeSystem];
            gAdButton.frame = CGRectMake(140, 165, 100, 36);
            gAdButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
            gAdButton.layer.cornerRadius = 18;
            gAdButton.clipsToBounds = YES;
            [gAdButton setTitle:@"ADBLOCK" forState:UIControlStateNormal];
            [gAdButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            gAdButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [gAdButton addTarget:gButtonTarget action:@selector(adTap:) forControlEvents:UIControlEventTouchUpInside];
            [w addSubview:gAdButton];
        }
    });
}

static BOOL TextLooksLikeAd(NSString *text) {
    if (!text.length) return NO;
    NSString *s = text.lowercaseString;
    NSArray *words = @[@"sponsored", @"promoted", @"advertisement", @"advertising", @"paid partnership"];
    for (NSString *w in words) if ([s containsString:w]) return YES;
    return NO;
}

static BOOL ClassLooksLikeAd(UIView *v) {
    NSString *n = NSStringFromClass(v.class).lowercaseString;
    NSArray *tokens = @[@"sponsored", @"advertisement", @"promoted", @"adcell", @"adview", @"adcontainer", @"awead", @"ttkad"];
    for (NSString *t in tokens) if ([n containsString:t]) return YES;
    return NO;
}

static BOOL ViewTreeLooksLikeAd(UIView *v, NSInteger depth) {
    if (depth > 4) return NO;
    if (ClassLooksLikeAd(v)) return YES;
    if ([v isKindOfClass:UILabel.class] && TextLooksLikeAd(((UILabel *)v).text)) return YES;
    if ([v isKindOfClass:UIButton.class] && TextLooksLikeAd([((UIButton *)v) titleForState:UIControlStateNormal])) return YES;
    if (TextLooksLikeAd(v.accessibilityLabel)) return YES;
    for (UIView *sub in v.subviews) if (ViewTreeLooksLikeAd(sub, depth + 1)) return YES;
    return NO;
}

static void ScanForAds(UIView *root) {
    if (!gAdBlockEnabled || !root.window) return;
    for (UIView *sub in root.subviews) {
        if (sub == gDownloadButton || sub == gAdButton) continue;
        if (ViewTreeLooksLikeAd(sub, 0)) {
            sub.hidden = YES;
        } else {
            ScanForAds(sub);
        }
    }
}

%hook AVURLAsset
- (instancetype)initWithURL:(NSURL *)URL options:(NSDictionary *)options {
    TrackVideoURL(URL);
    return %orig;
}
- (NSURL *)URL {
    NSURL *u = %orig;
    TrackVideoURL(u);
    return u;
}
%end

%hook AVPlayerItem
+ (instancetype)playerItemWithURL:(NSURL *)URL {
    TrackVideoURL(URL);
    return %orig;
}
- (instancetype)initWithURL:(NSURL *)URL {
    TrackVideoURL(URL);
    return %orig;
}
- (instancetype)initWithAsset:(AVAsset *)asset automaticallyLoadedAssetKeys:(NSArray<NSString *> *)keys {
    if ([asset isKindOfClass:AVURLAsset.class]) TrackVideoURL(((AVURLAsset *)asset).URL);
    return %orig;
}
%end

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    AVAsset *asset = item.asset;
    if ([asset isKindOfClass:AVURLAsset.class]) TrackVideoURL(((AVURLAsset *)asset).URL);
    %orig;
}
- (void)setCurrentItem:(AVPlayerItem *)item {
    AVAsset *asset = item.asset;
    if ([asset isKindOfClass:AVURLAsset.class]) TrackVideoURL(((AVURLAsset *)asset).URL);
    %orig;
}
%end

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gAdBlockEnabled && self.window) ScanForAds(self.window.rootViewController.view);
    });
}
%end

%ctor {
    EnsureState();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallButtons();
    });
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, 500 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        InstallButtons();
        if (gAdBlockEnabled) {
            UIWindow *w = TopWindow();
            if (w) ScanForAds(w.rootViewController.view);
        }
    });
    dispatch_resume(timer);
}
