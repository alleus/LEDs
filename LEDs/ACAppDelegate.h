//
//  ACAppDelegate.h
//  LEDs
//
//  Created by Martin Alleus on 2013-01-03.
//  Copyright (c) 2013 Martin Alleus. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ACScreenSampler.h"

@interface ACAppDelegate : NSObject <NSApplicationDelegate, ACScreenSamplerDelegate>

@property (nonatomic, strong) ACScreenSampler *screenSampler;

@property (assign) IBOutlet NSWindow *window;

@property (assign) IBOutlet NSView *channel1Preview;
@property (assign) IBOutlet NSView *channel2Preview;
@property (assign) IBOutlet NSView *channel3Preview;
@property (assign) IBOutlet NSView *channel4Preview;
@property (assign) IBOutlet NSView *channel5Preview;
@property (assign) IBOutlet NSView *channel6Preview;
@property (assign) IBOutlet NSView *channel7Preview;
@property (assign) IBOutlet NSView *channel8Preview;
@property (assign) IBOutlet NSView *channel9Preview;
@property (assign) IBOutlet NSView *channel10Preview;
@property (assign) IBOutlet NSView *channel11Preview;
@property (assign) IBOutlet NSView *channel12Preview;
@property (assign) IBOutlet NSView *channel13Preview;
@property (assign) IBOutlet NSView *channel14Preview;
@property (assign) IBOutlet NSView *channel15Preview;
@property (assign) IBOutlet NSView *channel16Preview;

@property (assign) IBOutlet NSView *inputPreview;

- (IBAction)setupScreenSampler:(id)sender;

@end
