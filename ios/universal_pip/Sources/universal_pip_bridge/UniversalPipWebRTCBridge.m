#import "UniversalPipWebRTCBridge.h"

#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const UniversalPipWebRTCDebugNotification = @"UniversalPipWebRTCDebugNotification";

static void UniversalPipWebRTCDebug(NSString *message) {
  [[NSNotificationCenter defaultCenter]
    postNotificationName:UniversalPipWebRTCDebugNotification
    object:message];
}

@interface UniversalPipSampleBufferView : UIView
@property(nonatomic, readonly) AVSampleBufferDisplayLayer *sampleBufferDisplayLayer;
@end

@implementation UniversalPipSampleBufferView

+ (Class)layerClass {
  return [AVSampleBufferDisplayLayer class];
}

- (AVSampleBufferDisplayLayer *)sampleBufferDisplayLayer {
  return (AVSampleBufferDisplayLayer *)self.layer;
}

@end

@interface UniversalPipSampleBufferRenderer : NSObject <RTCVideoRenderer>
- (instancetype)initWithDisplayLayer:(AVSampleBufferDisplayLayer *)displayLayer
                              trackId:(NSString *)trackId;
@end

@implementation UniversalPipSampleBufferRenderer {
  AVSampleBufferDisplayLayer *_displayLayer;
  dispatch_queue_t _renderQueue;
  CMTime _lastPresentationTime;
  NSUInteger _frameCount;
  NSString *_trackId;
}

- (instancetype)initWithDisplayLayer:(AVSampleBufferDisplayLayer *)displayLayer
                              trackId:(NSString *)trackId {
  self = [super init];
  if (self) {
    _displayLayer = displayLayer;
    _displayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _renderQueue = dispatch_queue_create("com.mo_dev.universal_pip.webrtc_frames", DISPATCH_QUEUE_SERIAL);
    _lastPresentationTime = kCMTimeInvalid;
    _trackId = [trackId copy];
  }
  return self;
}

- (void)setSize:(CGSize)size {}

- (void)renderFrame:(RTCVideoFrame *)frame {
  if (frame == nil) {
    return;
  }

  CVPixelBufferRef pixelBuffer = [self copyPixelBufferFromFrame:frame];
  if (pixelBuffer == NULL) {
    if (_frameCount == 0) {
      UniversalPipWebRTCDebug([NSString stringWithFormat:
        @"could not convert frame buffer %@",
        NSStringFromClass(frame.buffer.class)
      ]);
    }
    return;
  }

  dispatch_async(_renderQueue, ^{
    CMTime presentationTime = CMTIME_IS_VALID(_lastPresentationTime)
      ? CMTimeAdd(_lastPresentationTime, CMTimeMake(1, 30))
      : kCMTimeZero;
    _lastPresentationTime = presentationTime;

    CMVideoFormatDescriptionRef formatDescription = NULL;
    OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      kCFAllocatorDefault,
      pixelBuffer,
      &formatDescription
    );
    if (formatStatus != noErr || formatDescription == NULL) {
      UniversalPipWebRTCDebug([NSString stringWithFormat:
        @"could not create frame format status=%d",
        (int)formatStatus
      ]);
      CFRelease(pixelBuffer);
      return;
    }

    CMSampleTimingInfo timing = {
      .duration = kCMTimeInvalid,
      .presentationTimeStamp = presentationTime,
      .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
      kCFAllocatorDefault,
      pixelBuffer,
      formatDescription,
      &timing,
      &sampleBuffer
    );
    CFRelease(formatDescription);
    CFRelease(pixelBuffer);
    if (sampleStatus != noErr || sampleBuffer == NULL) {
      UniversalPipWebRTCDebug([NSString stringWithFormat:
        @"could not create sample buffer status=%d",
        (int)sampleStatus
      ]);
      return;
    }

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    if (attachments != NULL && CFArrayGetCount(attachments) > 0) {
      CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
      CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }

    if (_displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
      UniversalPipWebRTCDebug(@"display layer failed; flushing");
      [_displayLayer flushAndRemoveImage];
      _lastPresentationTime = kCMTimeInvalid;
    }
    if (!_displayLayer.readyForMoreMediaData) {
      CFRelease(sampleBuffer);
      return;
    }
    [_displayLayer enqueueSampleBuffer:sampleBuffer];
    _frameCount += 1;
    if (_frameCount == 1 || _frameCount % 120 == 0) {
      UniversalPipWebRTCDebug([NSString stringWithFormat:
        @"track=%@ delivered frame count=%lu layerStatus=%ld",
        _trackId,
        (unsigned long)_frameCount,
        (long)_displayLayer.status
      ]);
    }
    CFRelease(sampleBuffer);
  });
}

- (CVPixelBufferRef)copyPixelBufferFromFrame:(RTCVideoFrame *)frame CF_RETURNS_RETAINED {
  if ([frame.buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
    CVPixelBufferRef pixelBuffer = ((RTCCVPixelBuffer *)frame.buffer).pixelBuffer;
    return (CVPixelBufferRef)CFRetain(pixelBuffer);
  }

  id<RTCI420Buffer> i420Buffer = [frame.buffer toI420];
  if (i420Buffer == nil) {
    return NULL;
  }

  CVPixelBufferRef pixelBuffer = NULL;
  NSDictionary *pixelBufferAttributes = @{
    (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    (NSString *)kCVPixelBufferPixelFormatTypeKey:
      @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
    (NSString *)kCVPixelBufferWidthKey: @(i420Buffer.width),
    (NSString *)kCVPixelBufferHeightKey: @(i420Buffer.height),
  };
  CVReturn createStatus = CVPixelBufferCreate(
    kCFAllocatorDefault,
    i420Buffer.width,
    i420Buffer.height,
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    (__bridge CFDictionaryRef)pixelBufferAttributes,
    &pixelBuffer
  );
  if (createStatus != kCVReturnSuccess || pixelBuffer == NULL) {
    UniversalPipWebRTCDebug([NSString stringWithFormat:
      @"could not allocate I420 pixel buffer status=%d",
      (int)createStatus
    ]);
    return NULL;
  }

  CVPixelBufferLockBaseAddress(pixelBuffer, 0);
  uint8_t *destinationY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
  uint8_t *destinationUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
  const size_t destinationYStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
  const size_t destinationUVStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);

  for (int row = 0; row < i420Buffer.height; row++) {
    memcpy(
      destinationY + row * destinationYStride,
      i420Buffer.dataY + row * i420Buffer.strideY,
      i420Buffer.width
    );
  }
  for (int row = 0; row < i420Buffer.chromaHeight; row++) {
    uint8_t *destinationRow = destinationUV + row * destinationUVStride;
    const uint8_t *sourceU = i420Buffer.dataU + row * i420Buffer.strideU;
    const uint8_t *sourceV = i420Buffer.dataV + row * i420Buffer.strideV;
    for (int column = 0; column < i420Buffer.chromaWidth; column++) {
      destinationRow[column * 2] = sourceU[column];
      destinationRow[column * 2 + 1] = sourceV[column];
    }
  }
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
  return pixelBuffer;
}

@end

@implementation UniversalPipWebRTCBridge

+ (NSString *)debugNotificationName {
  return UniversalPipWebRTCDebugNotification;
}

+ (BOOL)enableMultitaskingCameraAccessIfSupported {
  if (@available(iOS 16.0, *)) {
    Class pluginClass = NSClassFromString(@"FlutterWebRTCPlugin");
    SEL sharedSelector = NSSelectorFromString(@"sharedSingleton");
    if (pluginClass == Nil || ![pluginClass respondsToSelector:sharedSelector]) {
      UniversalPipWebRTCDebug(@"cannot enable multitasking camera access: FlutterWebRTCPlugin is unavailable");
      return NO;
    }

    id plugin = ((id (*)(id, SEL))objc_msgSend)(pluginClass, sharedSelector);
    AVCaptureSession *captureSession = [plugin valueForKeyPath:@"videoCapturer.captureSession"];
    if (captureSession == nil) {
      UniversalPipWebRTCDebug(@"cannot enable multitasking camera access: no active capture session");
      return NO;
    }
    if (!captureSession.isMultitaskingCameraAccessSupported) {
      UniversalPipWebRTCDebug(@"multitasking camera access is not supported on this device");
      return NO;
    }

    captureSession.multitaskingCameraAccessEnabled = YES;
    UniversalPipWebRTCDebug(@"enabled multitasking camera access");
    return YES;
  }

  UniversalPipWebRTCDebug(@"multitasking camera access requires iOS 16 or newer");
  return NO;
}

+ (UIView *)videoViewForTrackId:(NSString *)trackId {
  if (trackId.length == 0) {
    UniversalPipWebRTCDebug(@"no native video track id was provided");
    return nil;
  }

  RTCVideoTrack *track = [self videoTrackForId:trackId];
  if (track == nil) {
    UniversalPipWebRTCDebug([NSString stringWithFormat:
      @"could not resolve track id %@",
      trackId
    ]);
    return nil;
  }

  UniversalPipSampleBufferView *videoView = [[UniversalPipSampleBufferView alloc] initWithFrame:CGRectZero];
  UniversalPipSampleBufferRenderer *renderer = [
    [UniversalPipSampleBufferRenderer alloc]
      initWithDisplayLayer:videoView.sampleBufferDisplayLayer
      trackId:trackId
  ];
  [track addRenderer:renderer];

  UniversalPipWebRTCDebug([NSString stringWithFormat:
    @"attached sample-buffer renderer to track %@",
    trackId
  ]);
  objc_setAssociatedObject(videoView, @selector(detachVideoView:), track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  objc_setAssociatedObject(videoView, @selector(videoViewForTrackId:), renderer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return videoView;
}

+ (void)detachVideoView:(UIView *)videoView {
  RTCVideoTrack *track = objc_getAssociatedObject(videoView, @selector(detachVideoView:));
  UniversalPipSampleBufferRenderer *renderer = objc_getAssociatedObject(videoView, @selector(videoViewForTrackId:));
  if (track != nil && renderer != nil) {
    [track removeRenderer:renderer];
  }
  objc_setAssociatedObject(videoView, @selector(detachVideoView:), nil, OBJC_ASSOCIATION_ASSIGN);
  objc_setAssociatedObject(videoView, @selector(videoViewForTrackId:), nil, OBJC_ASSOCIATION_ASSIGN);
}

+ (RTCVideoTrack *)videoTrackForId:(NSString *)trackId {
  Class pluginClass = NSClassFromString(@"FlutterWebRTCPlugin");
  SEL sharedSelector = NSSelectorFromString(@"sharedSingleton");
  if (pluginClass == Nil || ![pluginClass respondsToSelector:sharedSelector]) {
    UniversalPipWebRTCDebug(@"FlutterWebRTCPlugin singleton is unavailable");
    return nil;
  }

  id plugin = ((id (*)(id, SEL))objc_msgSend)(pluginClass, sharedSelector);
  if (plugin == nil) {
    UniversalPipWebRTCDebug(@"FlutterWebRTCPlugin has not been initialized");
    return nil;
  }

  SEL trackSelector = NSSelectorFromString(@"trackForId:peerConnectionId:");
  if ([plugin respondsToSelector:trackSelector]) {
    id track = ((id (*)(id, SEL, id, id))objc_msgSend)(
      plugin,
      trackSelector,
      trackId,
      nil
    );
    if ([track isKindOfClass:[RTCVideoTrack class]]) {
      UniversalPipWebRTCDebug([NSString stringWithFormat:
        @"resolved track %@ through FlutterWebRTCPlugin",
        trackId
      ]);
      return (RTCVideoTrack *)track;
    }
  }

  NSDictionary<NSString *, RTCMediaStream *> *localStreams = [plugin valueForKey:@"localStreams"];
  for (RTCMediaStream *stream in localStreams.allValues) {
    for (RTCVideoTrack *track in stream.videoTracks) {
      if ([track.trackId isEqualToString:trackId]) {
        return track;
      }
    }
  }

  NSDictionary<NSString *, RTCPeerConnection *> *peerConnections = [plugin valueForKey:@"peerConnections"];
  for (RTCPeerConnection *connection in peerConnections.allValues) {
    for (RTCRtpReceiver *receiver in connection.receivers) {
      RTCMediaStreamTrack *track = receiver.track;
      if ([track isKindOfClass:[RTCVideoTrack class]] && [track.trackId isEqualToString:trackId]) {
        return (RTCVideoTrack *)track;
      }
    }
  }

  return nil;
}

@end
