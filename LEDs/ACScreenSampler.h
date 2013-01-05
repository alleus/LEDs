//
//  ACScreenSampler.h
//  LEDs
//
//  Created by Martin Alleus on 2013-01-03.
//  Copyright (c) 2013 Martin Alleus. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@protocol ACScreenSamplerDelegate;


@interface ACScreenSampler : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic) NSUInteger captureRate;
@property (nonatomic) BOOL enablePreviewLayer;
@property (nonatomic) NSUInteger displayIndex;
@property (nonatomic) CGFloat captureWidth;
@property (nonatomic) NSEdgeInsets letterboxInsets;
@property (nonatomic, strong) NSArray *capturePoints;
@property (nonatomic, readonly) NSArray *letterboxCompensatedCapturePoints;

@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, weak) id <ACScreenSamplerDelegate> delegate;

- (void)stop;
- (void)setup;

@end


@protocol ACScreenSamplerDelegate <NSObject>

- (void)screenSampler:(ACScreenSampler *)screenSampler didSampleColors:(NSArray *)colors;

@end