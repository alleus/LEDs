//
//  ACAppDelegate.m
//  LEDs
//
//  Created by Martin Alleus on 2013-01-03.
//  Copyright (c) 2013 Martin Alleus. All rights reserved.
//

#import "ACAppDelegate.h"

@interface ACAppDelegate ()

@property (nonatomic) BOOL enableOutputPreview;

@end

@implementation ACAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(portsChanged:)
                                                 name:DKSerialPortsDidChangeNotification
                                               object:nil];
    
    [self portsChanged:nil];
	
	self.commsController = [[ArduinoDioderCommunicationController alloc] init];
	
	self.screenSampler = [[ACScreenSampler alloc] init];
	self.screenSampler.delegate = self;
	
	[self prepareUserDefaults];
	
	[self setupScreenSampler:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:DKSerialPortsDidChangeNotification
                                                  object:nil];
    self.commsController = nil;
	self.ports = nil;
	self.screenSampler = nil;
}

-(void)portsChanged:(NSNotification *)aNotification {
    self.ports = [[DKSerialPort availableSerialPorts] sortedArrayUsingComparator:^(id a, id b) {
        return [[a name] caseInsensitiveCompare:[b name]];
    }];
}

- (void)setupScreenSampler:(id)sender {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	self.enableOutputPreview = [userDefaults boolForKey:@"enableOutputPreview"];
	
	[self configureOuputPreviews];
	
	[self.screenSampler stop];
	
	self.screenSampler.captureRate = [userDefaults integerForKey:@"captureRate"];
	self.screenSampler.enablePreviewLayer = [userDefaults boolForKey:@"enablePreviewLayer"];
	self.screenSampler.displayIndex = [userDefaults integerForKey:@"displayIndex"];
	self.screenSampler.captureWidth = [userDefaults doubleForKey:@"captureWidth"];
	self.screenSampler.capturePoints = [NSUnarchiver unarchiveObjectWithData:[userDefaults objectForKey:@"capturePoints"]];
	self.screenSampler.averageSamples = [userDefaults integerForKey:@"averageSamples"];
	self.screenSampler.averageSampleSize = [userDefaults doubleForKey:@"averageSampleSize"];
	
	[self.screenSampler setup];
	
	[self configureInputPreview];
}

- (void)prepareUserDefaults {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	if (![userDefaults objectForKey:@"captureRate"]) {
		[userDefaults setBool:YES forKey:@"enableOutputPreview"];
		[userDefaults setInteger:25 forKey:@"captureRate"];
		[userDefaults setBool:YES forKey:@"enablePreviewLayer"];
		[userDefaults setInteger:0 forKey:@"displayIndex"];
		[userDefaults setDouble:200.0 forKey:@"captureWidth"];
		[userDefaults setInteger:0 forKey:@"averageSamples"];
		[userDefaults setDouble:0.01 forKey:@"averageSampleSize"];
		
		NSArray *capturePoints = capturePoints = @[
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
		[userDefaults setObject:[NSArchiver archivedDataWithRootObject:capturePoints] forKey:@"capturePoints"];
		
		[userDefaults synchronize];
	}
}

- (void)configureOuputPreviews {
	for (NSUInteger i = 0; i < 16; i++) {
		NSView *preview = [self valueForKey:[NSString stringWithFormat:@"channel%ldPreview", i+1]];
		
		preview.wantsLayer = YES;
		preview.layer.borderWidth = 1.0;
		preview.layer.borderColor = CGColorCreateGenericGray(0.4, 1.0);
		preview.layer.cornerRadius = 5.0;
		preview.layer.backgroundColor = CGColorCreateGenericGray(1.0, 1.0);
	}
}

- (void)configureInputPreview {
	[[self.inputPreview subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	self.inputPreview.wantsLayer = YES;
	
	if (self.screenSampler.enablePreviewLayer) {
		self.inputPreview.layer = self.screenSampler.previewLayer;
		
		for (NSValue *value in self.screenSampler.capturePoints) {
			CGPoint point = [value pointValue];
			CGPoint translatedPoint = CGPointMake(point.x * self.inputPreview.frame.size.width, self.inputPreview.frame.size.height - (point.y * self.inputPreview.frame.size.height));
			NSImageView *imageView = [[NSImageView alloc] initWithFrame:CGRectIntegral(CGRectMake(translatedPoint.x - 4.0, translatedPoint.y - 4.0, 9.0, 9.0))];
			imageView.image = [NSImage imageNamed:@"point.png"];
			[self.inputPreview addSubview:imageView];
		}
	}
}

- (void)screenSampler:(ACScreenSampler *)screenSampler didSampleColors:(NSArray *)colors {
	[self.commsController pushColorsToChannels:colors withDuration:0.0];
	
	if (self.enableOutputPreview) {
		NSUInteger i, count = [colors count];
		for (i = 0; i < count; i++) {
			NSColor *color = [colors objectAtIndex:i];
			NSView *preview = [self valueForKey:[NSString stringWithFormat:@"channel%ldPreview", i+1]];
			preview.layer.backgroundColor = [color CGColor];
		}
	}
	
	if (self.screenSampler.enablePreviewLayer) {
		NSUInteger i, count = [self.screenSampler.letterboxCompensatedCapturePoints count];
		for (i = 0; i < count; i++) {
			NSValue *value = [self.screenSampler.letterboxCompensatedCapturePoints objectAtIndex:i];
			CGPoint point = [value pointValue];
			CGPoint translatedPoint = CGPointMake(point.x * self.inputPreview.frame.size.width, self.inputPreview.frame.size.height - (point.y * self.inputPreview.frame.size.height));
			NSImageView *imageView = [[self.inputPreview subviews] objectAtIndex:i];
			
			imageView.frame = CGRectIntegral(CGRectMake(translatedPoint.x - 4.0, translatedPoint.y - 4.0, 9.0, 9.0));
		}
	}
}

@end
