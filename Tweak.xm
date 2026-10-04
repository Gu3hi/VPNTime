#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static char kTapKey;
static __weak UIView *gTimeView = nil;
static BOOL gIsShowing = NO;

static void FLog(NSString *fmt, ...) {
    // 日志已禁用
}

// VPN 探测：用 dlopen 运行时加载 NetworkExtension
static NSString *DetectVPNName(void) {
    static void *neHandle = NULL;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        neHandle = dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
        FLog(@"[detect] dlopen NE = %@", neHandle ? @"OK" : @"FAIL");
    });
    if (!neHandle) return nil;
    Class mgrCls = NSClassFromString(@"NETunnelProviderManager");
    if (!mgrCls) { FLog(@"[detect] NETunnelProviderManager not found"); return nil; }
    // 同步等待 loadAllFromPreferences
    __block NSArray *managers = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [mgrCls performSelector:@selector(loadAllFromPreferencesWithCompletionHandler:) withObject:^(NSArray *ms, NSError *err) {
        managers = ms;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    for (id m in managers) {
        @try {
            id conn = [m valueForKey:@"connection"];
            NSInteger status = [[conn valueForKey:@"status"] integerValue];
            if (status == 3) { // NEVPNStatusConnected
                NSString *name = [m valueForKey:@"localizedDescription"];
                FLog(@"[detect] connected: %@", name);
                return name ?: @"VPN";
            }
        } @catch (NSException *e) {}
    }
    return nil;
}

@interface STUIStatusBarStringView : UIView
- (void)fresh_addTap;
- (void)fresh_onTap;
@end

%hook STUIStatusBarStringView
- (void)didMoveToWindow {
    %orig;
    [self fresh_addTap];
}
%new
- (void)fresh_addTap {
    if (objc_getAssociatedObject(self, &kTapKey)) return;
    NSString *text = nil;
    @try { text = [self valueForKey:@"text"]; } @catch (NSException *e) {}
    if (![text isKindOfClass:[NSString class]]) return;
    static NSRegularExpression *re = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}:\\d{2}$" options:0 error:NULL]; });
    if ([re numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] == 0) return;
    objc_setAssociatedObject(self, &kTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gTimeView = self;
    FLog(@"[hook] 时间已加点击: %@", text);
    // 打开 userInteractionEnabled（沿 superview 链）
    UIView *v = self;
    while (v) {
        v.userInteractionEnabled = YES;
        v = v.superview;
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(fresh_onTap)];
    [self addGestureRecognizer:tap];
}
// 在状态栏时间位置显示文字
static void ShowTextInStatusBar(NSString *text, NSTimeInterval showTime, void (^completion)(void)) {
    UIView *timeView = gTimeView;
    if (!timeView) { if (completion) completion(); return; }
    UIWindow *win = timeView.window;
    if (!win) { if (completion) completion(); return; }
    CGRect frameInWin = [timeView convertRect:timeView.bounds toView:win];
    CGPoint center = CGPointMake(CGRectGetMidX(frameInWin), CGRectGetMidY(frameInWin));
    timeView.alpha = 0;
    UIFont *font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    // 与状态栏时间颜色保持一致：取被点时间视图的真实文字色（legibility 已按壁纸解析）
    UIColor *timeColor = nil;
    @try { timeColor = [timeView valueForKey:@"textColor"]; } @catch (NSException *e) {}
    if (![timeColor isKindOfClass:[UIColor class]]) timeColor = [UIColor labelColor];
    label.textColor = timeColor;
    label.textAlignment = NSTextAlignmentCenter;
    [label sizeToFit];
    CGFloat w = MAX(frameInWin.size.width + 20, label.frame.size.width + 20);
    label.frame = CGRectMake(center.x - w/2, center.y - 10, w, 20);
    label.alpha = 0;
    [win addSubview:label];
    [UIView animateWithDuration:0.25 animations:^{ label.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(showTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.4 animations:^{
            label.alpha = 0;
        } completion:^(BOOL f) {
            [label removeFromSuperview];
            if (completion) completion();
        }];
    });
}

%new
- (void)fresh_onTap {
    if (gIsShowing) return;
    gIsShowing = YES;
    UIView *timeView = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *name = DetectVPNName();
        NSString *show = name ? name : @"未连接 VPN";
        dispatch_async(dispatch_get_main_queue(), ^{
            ShowTextInStatusBar(show, 2.5, ^{
                [UIView animateWithDuration:0.3 animations:^{
                    timeView.alpha = 1;
                } completion:^(BOOL f) {
                    gIsShowing = NO;
                }];
            });
        });
    });
}
%end

%ctor {
}

