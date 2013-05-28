//
//  ArduinoDioderCommunicationController.m
//  Dioder Screen Colors
//
//  Created by Daniel Kennett on 15/09/2011.
//  Copyright 2011 Daniel Kennett. All rights reserved.
//

#import "ArduinoDioderCommunicationController.h"

#define kHeaderByte1 0xBA
#define kHeaderByte2 0xBE

struct ArduinoDioderControlMessage {
    unsigned char header[2];
    unsigned char colors[48];
    unsigned char checksum;
};

@interface ArduinoDioderCommunicationController ()

@property (readwrite) BOOL canSendData;

@property (readwrite, retain) NSArray *pendingColors;
@property (readwrite, retain) NSArray *currentColors;

-(void)sendColorsWithDuration:(NSTimeInterval)duration;
-(void)writeColorsToChannels:(NSArray *)channels;

-(NSColor *)colorByApplyingProgress:(double)progress ofTransitionFromColor:(NSColor *)start toColor:(NSColor *)finish;

@end

@implementation ArduinoDioderCommunicationController

-(id)init {
    self = [super init];
    if (self) {
        // Initialization code here.
        [self addObserver:self forKeyPath:@"port" options:NSKeyValueObservingOptionOld context:nil];
        [self addObserver:self forKeyPath:@"canSendData" options:0 context:nil];
        [self addObserver:self forKeyPath:@"lightsEnabled" options:0 context:nil];
        self.canSendData = NO;
		self.lightsEnabled = YES;
	}
    return self;
}

-(void)dealloc {
    
    [self removeObserver:self forKeyPath:@"port"];
    [self removeObserver:self forKeyPath:@"canSendData"];
    [self removeObserver:self forKeyPath:@"lightsEnabled"];
    
    self.pendingColors = nil;
    self.currentColors = nil;
    
    self.canSendData = NO;
    [self.port close];
    self.port = nil;
}


@synthesize port;
@synthesize canSendData;
@synthesize lightsEnabled;
@synthesize pendingColors;
@synthesize currentColors;

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"port"]) {
        
        self.canSendData = NO;
        
        id oldPort = [change valueForKey:NSKeyValueChangeOldKey];
        if (oldPort != [NSNull null])
            [oldPort close];
        
        NSError *err = nil;
        [self.port openWithBaudRate:57600
                              error:&err];
        
        if (err)
            NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), err);
        
        [self performSelector:@selector(enableWrite)
                   withObject:nil
                   afterDelay:2.0];
        
    } else if ([keyPath isEqualToString:@"canSendData"]) {
        if (self.canSendData && self.pendingColors) {
            [self sendColorsWithDuration:0.0];
            NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"forcing");
        }
		
	} else if ([keyPath isEqualToString:@"lightsEnabled"]) {
		
		[self pushColorsToChannels:self.currentColors
					  withDuration:0.0];
		
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark -
#pragma mark Setup

-(void)enableWrite {
    self.canSendData = YES;
}

-(void)pushColorsToChannel1:(NSColor *)channel1 
                   channel2:(NSColor *)channel2
                   channel3:(NSColor *)channel3
                   channel4:(NSColor *)channel4
               withDuration:(NSTimeInterval)duration {
    
    self.pendingColors = @[channel1, channel2, channel3, channel4];
    
    if (self.canSendData)
        [self sendColorsWithDuration:duration];
}

-(void)pushColorsToChannels:(NSArray *)channels
               withDuration:(NSTimeInterval)duration {
	self.pendingColors = channels;
	
	if (self.canSendData)
		[self sendColorsWithDuration:duration];
}

-(void)sendColorsWithDuration:(NSTimeInterval)duration {
    
    if (!self.canSendData && ![self.port isOpen])
        return;
    
    self.canSendData = NO;
    [self performSelectorInBackground:@selector(sendPendingColorsInBackground:) withObject:[NSNumber numberWithDouble:duration]];
}

#pragma mark -
#pragma mark Sending (in background)

-(void)sendPendingColorsInBackground:(NSNumber *)animationDuration {
    
    @autoreleasepool {
		
		NSTimeInterval duration = [animationDuration doubleValue];
		NSDate *operationStartDate = [NSDate date];
		NSTimeInterval timeSinceStartDate = 0.0;
		double animationSpeed = 1.0 / duration;
		
		while (timeSinceStartDate < duration) {
			NSMutableArray *colors = [NSMutableArray arrayWithCapacity:[self.pendingColors count]];
			NSUInteger i, count = [self.pendingColors count];
			for (i = 0; i < count; i++) {
				[colors addObject:[self colorByApplyingProgress:timeSinceStartDate * animationSpeed ofTransitionFromColor:self.currentColors[i] toColor:self.pendingColors[i]]];
			}
			[self writeColorsToChannels:colors];
			
			timeSinceStartDate = [[NSDate date] timeIntervalSinceDate:operationStartDate];
		}
		
		[self writeColorsToChannels:self.pendingColors];
		
		[self performSelectorOnMainThread:@selector(completeSend) 
							   withObject:nil
							waitUntilDone:YES];
		
	}
}

-(void)writeColorsToChannels:(NSArray *)channels {
	@autoreleasepool {
		struct ArduinoDioderControlMessage message;
		memset(&message, 0, sizeof(struct ArduinoDioderControlMessage));
		
		message.header[0] = kHeaderByte1;
		message.header[1] = kHeaderByte2;
		
		if (self.lightsEnabled) {
			NSUInteger i, count = [channels count];
			for (i = 0; i < count; i++) {
				NSColor *rgbChannel = [channels[i] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
				
				message.colors[(i*3)] = (unsigned char)([rgbChannel greenComponent] * 255);
				message.colors[(i*3) + 1] = (unsigned char)([rgbChannel redComponent] * 255);
				message.colors[(i*3) + 2] = (unsigned char)([rgbChannel blueComponent] * 255);
			}
		}
		
		unsigned char checksum = 0;
		for (int i = 0; i < sizeof(message.colors); i++)
			checksum ^= message.colors[i];
		
		message.checksum = checksum;
		
		NSData *data = [NSData dataWithBytes:&message length:sizeof(struct ArduinoDioderControlMessage)];
		NSError *error = nil;
		NSString *reply = nil;
		
		[self.port writeData:data error:&error];
		
		if (!error)
			reply = [self.port readLineWithError:&error];
		
		if (error)
			NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
		else if (reply && ![reply isEqualToString:@"OK"])
			NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), reply);
		
	}
}

-(void)completeSend {
	self.currentColors = self.pendingColors;
	
	self.pendingColors = nil;
    
    self.canSendData = YES;
}

#pragma mark -
#pragma mark Helpers

-(NSColor *)colorByApplyingProgress:(double)progress ofTransitionFromColor:(NSColor *)start toColor:(NSColor *)finish {
    
    if ([start isEqualTo:finish])
        return finish;
    
    // If you choose a greyscale color, it won't have red, green or blue components so we defensively convert.
    start = [start colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    finish = [finish colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    
    CGFloat fromRed = [start redComponent];
    CGFloat fromGreen = [start greenComponent];
    CGFloat fromBlue = [start blueComponent];
    
    CGFloat toRed = [finish redComponent];
    CGFloat toGreen = [finish greenComponent];
    CGFloat toBlue = [finish blueComponent];
    
    return [NSColor colorWithDeviceRed:fromRed + ((toRed - fromRed) * progress)
                                 green:fromGreen + ((toGreen - fromGreen) * progress)
                                  blue:fromBlue + ((toBlue - fromBlue) * progress)
                                 alpha:1.0];
}

@end
