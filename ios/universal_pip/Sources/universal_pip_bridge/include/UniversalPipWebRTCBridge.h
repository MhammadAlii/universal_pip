#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UniversalPipWebRTCBridge : NSObject

+ (NSString *)debugNotificationName;

+ (BOOL)enableMultitaskingCameraAccessIfSupported;
+ (nullable UIView *)videoViewForTrackId:(nullable NSString *)trackId;
+ (void)detachVideoView:(UIView *)videoView;

@end

NS_ASSUME_NONNULL_END
