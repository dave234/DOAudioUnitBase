//
//  DOAudioUnitBase.h
//  DOAudioUnitBase
//
//  Created by dave on 9/13/17.
//  Copyright © 2017 oneill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


typedef struct {
    AudioStreamBasicDescription *format;
    AudioBufferList *buffer;
    int hasData;
} ChannelBuffer;

typedef struct {
    ChannelBuffer *buffers;
    int count;
} ChannelBufferArray;


typedef void(^ProcessEventsBlock)(AudioBufferList       *inBuffer,
                                  AudioBufferList       *outBuffer,
                                  const AudioTimeStamp  *timestamp,
                                  int                   frameCount,
                                  const AURenderEvent   *realtimeEventListHead);







typedef void (^MultiChannelProccessBlock)(ChannelBufferArray    *inputChannels,
                                          ChannelBuffer         *outputChannel,
                                          const AudioTimeStamp  *timestamp,
                                          int                   frameCount,
                                          const AURenderEvent   *realtimeEventListHead);



@interface DOAudioUnitBase : AUAudioUnit
@property (readonly, weak) AVAudioNode *node;

+(__kindof AVAudioUnit *)AVAudioUnitWithName:(NSString *)name;


@end














