#import <UIKit/UIKit.h>
#import <objc/runtime.h>

void TikTokPlusSetMuted(BOOL muted);

static BOOL TTHIsTikTok(void){
    NSString *b=NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    return [b containsString:@"musically"] || [b containsString:@"tiktok"];
}

@interface TTHoldTarget:NSObject
@end
@implementation TTHoldTarget
- (void)homeHeld:(UILongPressGestureRecognizer *)g {
    if(g.state==UIGestureRecognizerStateBegan) TikTokPlusSetMuted(NO);
}
@end

static TTHoldTarget *gHoldTarget;
static char kTTHoldInstalled;

static BOOL TTHLooksLikeHome(UIView *v){
    NSString *a=v.accessibilityLabel.lowercaseString ?: @"";
    NSString *i=v.accessibilityIdentifier.lowercaseString ?: @"";
    NSString *c=NSStringFromClass(v.class).lowercaseString ?: @"";
    if([v isKindOfClass:UIButton.class]){
        NSString *t=[(UIButton *)v titleForState:UIControlStateNormal].lowercaseString ?: @"";
        if([t isEqualToString:@"home"] || [a isEqualToString:@"home"]) return YES;
    }
    if([a isEqualToString:@"home"] || [i containsString:@"home"] || [c containsString:@"homebutton"]) return YES;
    return NO;
}

static void TTHInstallOnView(UIView *v){
    if(!v || objc_getAssociatedObject(v,&kTTHoldInstalled)) return;
    if(!TTHLooksLikeHome(v)) return;
    if(!gHoldTarget) gHoldTarget=[TTHoldTarget new];
    UILongPressGestureRecognizer *g=[[UILongPressGestureRecognizer alloc] initWithTarget:gHoldTarget action:@selector(homeHeld:)];
    g.minimumPressDuration=5.0;
    g.allowableMovement=25.0;
    [v addGestureRecognizer:g];
    objc_setAssociatedObject(v,&kTTHoldInstalled,g,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void TTHScan(UIView *root){
    if(!root) return;
    NSMutableArray *stack=[NSMutableArray arrayWithObject:root];
    while(stack.count){
        UIView *v=stack.lastObject; [stack removeLastObject];
        TTHInstallOnView(v);
        for(UIView *s in v.subviews) [stack addObject:s];
    }
}

static void TTHRemoveOldButtons(UIView *root){
    if(!root)return;
    NSMutableArray *stack=[NSMutableArray arrayWithObject:root];
    while(stack.count){
        UIView *v=stack.lastObject; [stack removeLastObject];
        if(v.tag==190611 || ([v isKindOfClass:UIButton.class] && [[(UIButton *)v titleForState:UIControlStateNormal].lowercaseString isEqualToString:@"mute"]) || ([v isKindOfClass:UIButton.class] && [[(UIButton *)v titleForState:UIControlStateNormal].lowercaseString isEqualToString:@"unmute"]))){
            v.hidden=YES; v.userInteractionEnabled=NO;
        }
        if([v isKindOfClass:UIButton.class] && [[(UIButton *)v titleForState:UIControlStateNormal].lowercaseString isEqualToString:@"hd save"]){
            v.hidden=YES; v.userInteractionEnabled=NO;
        }
        for(UIView *s in v.subviews) [stack addObject:s];
    }
}

static UIWindow *TTHWindow(void){
    for(UIWindow *w in UIApplication.sharedApplication.windows){
        if(!w.hidden && w.alpha>.01 && w.windowLevel==UIWindowLevelNormal && w.rootViewController) return w;
    }
    return nil;
}

static void TTHInstall(void){
    if(!TTHIsTikTok())return;
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow *w=TTHWindow();
        if(!w)return;
        TTHScan(w);
        TTHRemoveOldButtons(w);
    });
}

%ctor{
    if(!TTHIsTikTok())return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{TTHInstall();});
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{TTHInstall();});
    dispatch_resume(timer);
}
