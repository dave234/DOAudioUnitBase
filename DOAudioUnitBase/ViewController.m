//
//  ViewController.m
//  DOAudioUnitBase
//
//  Created by dave on 9/13/17.
//  Copyright © 2017 oneill. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "DOAudioUnitBase.h"


@implementation ViewController {
    AVAudioEngine *engine;
    AVAudioUnitSampler *sampler1;
    AVAudioUnitSampler *sampler2;
    AVAudioUnit *customMixer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
   
    engine = [[AVAudioEngine alloc]init];
    sampler1 = [[AVAudioUnitSampler alloc]init];
    sampler2 = [[AVAudioUnitSampler alloc]init];
    customMixer = [DOAudioUnitBase AVAudioUnitWithName:@"Derpa"];

    [engine attachNode:sampler1];
    [engine attachNode:sampler2];
    [engine attachNode:customMixer];

    AVAudioFormat *format = [[AVAudioFormat alloc]initStandardFormatWithSampleRate:44100 channels:2];

    [engine connect:sampler1 to:customMixer fromBus:0 toBus:0 format:format];
    [engine connect:sampler2 to:customMixer fromBus:0 toBus:1 format:format];
    
    [engine connect:customMixer to:engine.mainMixerNode format:format];
    
    [engine startAndReturnError:NULL];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sampler1 startNote:72 withVelocity:127 onChannel:0];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sampler2 startNote:76 withVelocity:127 onChannel:0];
    });
  
}

@end




















