//
//  ACScreenSampler.m
//  LEDs
//
//  Created by Martin Alleus on 2013-01-03.
//  Copyright (c) 2013 Martin Alleus. All rights reserved.
//

#import "ACScreenSampler.h"
#import <AVFoundation/AVFoundation.h>

#define LETTERBOX_ANIMATION_STEP 0.05

@interface ACScreenSampler ()

@property (nonatomic, strong, readwrite) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic) CGSize captureSize;
@property (nonatomic) BOOL letterboxChanged;
@property (strong) NSArray *cachedLetterboxCompensatedCapturePoints;

@end

@implementation ACScreenSampler

- (id)init
{
    self = [super init];
    if (self) {
        /*_captureRate = 25;
		_enablePreviewLayer = YES;
		_displayIndex = 1;
		_captureWidth = 200.0; // Lower values
		_capturePoints = @[
		// Top
			[NSValue valueWithPoint:CGPointMake(0.1, 0.05)],
			[NSValue valueWithPoint:CGPointMake(0.3, 0.05)],
			[NSValue valueWithPoint:CGPointMake(0.5, 0.05)],
			[NSValue valueWithPoint:CGPointMake(0.7, 0.05)],
			[NSValue valueWithPoint:CGPointMake(0.9, 0.05)],
		// Right
			[NSValue valueWithPoint:CGPointMake(0.97, 0.15)],
			[NSValue valueWithPoint:CGPointMake(0.97, 0.38)],
			[NSValue valueWithPoint:CGPointMake(0.97, 0.62)],
			[NSValue valueWithPoint:CGPointMake(0.97, 0.85)],
		// Bottom
			[NSValue valueWithPoint:CGPointMake(0.8, 0.95)],
			[NSValue valueWithPoint:CGPointMake(0.5, 0.95)],
			[NSValue valueWithPoint:CGPointMake(0.2, 0.95)],
		// Left
			[NSValue valueWithPoint:CGPointMake(0.03, 0.85)],
			[NSValue valueWithPoint:CGPointMake(0.03, 0.62)],
			[NSValue valueWithPoint:CGPointMake(0.03, 0.38)],
			[NSValue valueWithPoint:CGPointMake(0.03, 0.15)]
		];
		
		_letterboxChanged = YES;*/
    }
    return self;
}

- (void)dealloc
{
	[self stop];
}

- (void)stop {
	if ([self.captureSession isRunning])
		[self.captureSession stopRunning];
}

- (void)setup {
	// Create session
	self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession beginConfiguration];
    [self.captureSession setSessionPreset:AVCaptureSessionPreset320x240];
	
	// Use requested display
	unsigned int displayCount;
    CGDirectDisplayID displays[10];
    CGGetActiveDisplayList(10, displays, &displayCount);
	
	if (self.displayIndex >= displayCount)
		return;
	
    CGDirectDisplayID displayId = displays[self.displayIndex];
	
	// Create the screen video capture input
	AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:displayId];
	
	if (!input)
        return;
	
	// Configure and add the input
	CMTime minimumFrameDuration = CMTimeMake(1, (int32_t)self.captureRate);
	[input setMinFrameDuration:minimumFrameDuration];
	
    if ([self.captureSession canAddInput:input])
        [self.captureSession addInput:input];
	
	// Create the data buffer output
	AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
	
	// Configure and add the ouput
	CGSize displaySize = CGDisplayScreenSize(displayId);
    CGFloat screenScale = self.captureWidth / displaySize.width;
	self.captureSize = CGSizeMake(displaySize.width * screenScale, displaySize.height * screenScale);
	
    [output setAlwaysDiscardsLateVideoFrames:YES];
	[output setVideoSettings:@{
		(id)kCVPixelBufferWidthKey: @((int)self.captureSize.width),
		(id)kCVPixelBufferHeightKey: @((int)self.captureSize.height),
		(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) // Using the full range Y'CbCr format, really increasing performance compared to the RGB modes
	}];
	
	dispatch_queue_t outputQueue = dispatch_queue_create("outputQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:outputQueue];
	
	if ([self.captureSession canAddOutput:output])
		[self.captureSession addOutput:output];
	
	// Create preview layer if requested
	if (self.enablePreviewLayer) {
		self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
		[self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	}
	
	// Finish configuration and initiate the session
	[self.captureSession commitConfiguration];
    if (![self.captureSession isRunning])
        [self.captureSession startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
	// Set up image buffer
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	
	// Lock address and fetch base color components
	CVPixelBufferLockBaseAddress(imageBuffer, 0);
	
	uint8_t *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    CVPlanarPixelBufferInfo_YCbCrBiPlanar *bufferInfo = (CVPlanarPixelBufferInfo_YCbCrBiPlanar *)baseAddress;
	
	NSUInteger yOffset = EndianU32_BtoN(bufferInfo->componentInfoY.offset);
	NSUInteger yPitch = EndianU32_BtoN(bufferInfo->componentInfoY.rowBytes);
	NSUInteger cbCrOffset = EndianU32_BtoN(bufferInfo->componentInfoCbCr.offset);
	NSUInteger cbCrPitch = EndianU32_BtoN(bufferInfo->componentInfoCbCr.rowBytes);
	
	// Detect letterbox
	NSEdgeInsets analyzedLetterboxInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
	
	// Loop trough all four edges
	for (NSUInteger direction = 0; direction < 4; direction++) {
		// Measure four points per edge
		CGFloat inset = 1.0;
		for (NSUInteger i = 0; i < 4; i++) {
			BOOL nonBlack = NO;
			CGFloat step = 0.2 * (i+1);
			CGFloat edgeInset = 0.01;
			
			// Find non black pixel by measuring the luma component, stepping 0.1% per loop
			while (!nonBlack && edgeInset < 0.5 && edgeInset < inset) { // No need to go further than 50%, nor further than last measured 
				CGPoint measurePoint = CGPointZero;
				
				switch (direction) {
					case 0:
						// Top
						measurePoint = CGPointMake(step, edgeInset);
						break;
					case 1:
						// Right
						measurePoint = CGPointMake(1.0 - edgeInset, step);
						break;
					case 2:
						// Bottom
						measurePoint = CGPointMake(step, 1.0 - edgeInset);
						break;
					case 3:
						// Left
						measurePoint = CGPointMake(edgeInset, step);
						break;
				}
				
				CGPoint translatedMeasurePoint = CGPointMake(measurePoint.x * self.captureSize.width, measurePoint.y * self.captureSize.height);
				
				uint8_t *y = baseAddress + yOffset + (int)translatedMeasurePoint.y * yPitch + (int)translatedMeasurePoint.x;
				
				if (*y > 0) {
					nonBlack = YES;
				} else {
					edgeInset += 0.001;
				}
			}
			
			// The inset is determined as the lowest common value
			inset = MIN(edgeInset, inset);
		}
		
		switch (direction) {
			case 0:
				// Top
				analyzedLetterboxInsets.top = inset;
				break;
			case 1:
				// Right
				analyzedLetterboxInsets.right = inset;
				break;
			case 2:
				// Bottom
				analyzedLetterboxInsets.bottom = inset;
				break;
			case 3:
				// Left
				analyzedLetterboxInsets.left = inset;
				break;
		}
	}
	
	// Check for modified letterbox analysis
	if (_letterboxInsets.top != analyzedLetterboxInsets.top || _letterboxInsets.right != analyzedLetterboxInsets.right || _letterboxInsets.bottom != analyzedLetterboxInsets.bottom || _letterboxInsets.left != analyzedLetterboxInsets.left) {
		//
		// Currently unused letterbox transition animation
		//
		/*NSEdgeInsets newLetterboxInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
		
		for (NSUInteger direction = 0; direction < 4; direction++) {
			CGFloat currentInset, targetInset, newInset;
			switch (direction) {
				case 0:
					// Top
					currentInset = _letterboxInsets.top;
					targetInset = analyzedLetterboxInsets.top;
					break;
				case 1:
					// Right
					currentInset = _letterboxInsets.right;
					targetInset = analyzedLetterboxInsets.right;
					break;
				case 2:
					// Bottom
					currentInset = _letterboxInsets.bottom;
					targetInset = analyzedLetterboxInsets.bottom;
					break;
				case 3:
					// Left
					currentInset = _letterboxInsets.left;
					targetInset = analyzedLetterboxInsets.left;
					break;
			}
			
			if (currentInset > targetInset) {
				newInset = MAX(targetInset, currentInset - LETTERBOX_ANIMATION_STEP);
			} else if (currentInset < targetInset) {
				newInset = MIN(targetInset, currentInset + LETTERBOX_ANIMATION_STEP);
			} else {
				newInset = currentInset;
			}
			
			switch (direction) {
				case 0:
					// Top
					newLetterboxInsets.top = newInset;
					break;
				case 1:
					// Right
					newLetterboxInsets.right = newInset;
					break;
				case 2:
					// Bottom
					newLetterboxInsets.bottom = newInset;
					break;
				case 3:
					// Left
					newLetterboxInsets.left = newInset;
					break;
			}
		}
		
		self.letterboxInsets = newLetterboxInsets;*/
		self.letterboxInsets = analyzedLetterboxInsets;
		self.letterboxChanged = YES;
	} else {
		self.letterboxChanged = NO;
	}
	
	// Sample colors
	NSMutableArray *colors = [NSMutableArray arrayWithCapacity:[self.capturePoints count]];
	
	for (NSValue *value in self.letterboxCompensatedCapturePoints) {
		CGPoint point = [value pointValue];
		CGPoint translatedPoint = CGPointMake(point.x * self.captureSize.width, point.y * self.captureSize.height);
		
		// Find all components
		uint8_t *y = baseAddress + yOffset + ((int)translatedPoint.y * yPitch) + (int)translatedPoint.x;
        uint8_t *cb = baseAddress + cbCrOffset + (((int)translatedPoint.y >> 1) * cbCrPitch) + ((int)translatedPoint.x & ~1);
        uint8_t *cr = baseAddress + cbCrOffset + (((int)translatedPoint.y >> 1) * cbCrPitch) + ((int)translatedPoint.x | 1);
		
		// Convert to RGB
		float red = MAX(0.0, MIN(255.0, *y + 1.40200 * (*cr - 0x80)));
		float green = MAX(0.0, MIN(255.0, *y - 0.34414 * (*cb - 0x80) - 0.71414 * (*cr - 0x80)));
		float blue = MAX(0.0, MIN(255.0, *y + 1.77200 * (*cb - 0x80)));
		
		// Add finished color to sample array
		[colors addObject:[NSColor colorWithDeviceRed:red/255.0 green:green/255.0 blue:blue/255.0 alpha:1.0]];
    }
	
	CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
	
	// Notify delegate on main thread
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.delegate screenSampler:self didSampleColors:[colors copy]];
	});
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
	NSLog(@"Dropped frame!");
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput {
	return NO;
}

- (NSArray *)letterboxCompensatedCapturePoints {
	// Don't recreate if letterbox analysis is unchanged and we have cached array
	if (!self.letterboxChanged && self.cachedLetterboxCompensatedCapturePoints) {
		return self.cachedLetterboxCompensatedCapturePoints;
	}
	
	NSMutableArray *newCapturePoints = [NSMutableArray arrayWithCapacity:[self.capturePoints count]];
	
	for (NSValue *value in self.capturePoints) {
		CGPoint point = [value pointValue];
		CGPoint compensatedPoint = CGPointMake(self.letterboxInsets.left + point.x * (1.0 - self.letterboxInsets.left - self.letterboxInsets.right), self.letterboxInsets.top + point.y * (1.0 - self.letterboxInsets.top - self.letterboxInsets.bottom));
		
		[newCapturePoints addObject:[NSValue valueWithPoint:compensatedPoint]];
	}
	
	self.cachedLetterboxCompensatedCapturePoints = [newCapturePoints copy];
	return self.cachedLetterboxCompensatedCapturePoints;
}

@end
