//
//  AKBase.m
//  DOAudioUnitBase
//
//  Created by dave on 9/13/17.
//  Copyright © 2017 oneill. All rights reserved.
//

#import "AKBase.h"


@implementation AKBase {
    AVAudioPCMBuffer *buffer;
    AUAudioUnitBus *_inputBus;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_inputBusses;
    AUAudioUnitBusArray *_outputBusses;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }
    
    // Initialize a default format for the busses.
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    
    NSError *error = nil;
    
    // Create the input and output bus arrays.
    _inputBus = [[AUAudioUnitBus alloc]initWithFormat:format error:&error];
    _outputBus = [[AUAudioUnitBus alloc]initWithFormat:format error:&error];
    
    if (error) NSLog(@"error %@",error);
    
    _inputBusses  = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeInput
                                                            busses: @[_inputBus]];
    
    _outputBusses = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeOutput
                                                            busses: @[_outputBus]];
    
    buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:format frameCapacity:self.maximumFramesToRender];
    return self;
}

// Allocate resources required to render.
// Hosts must call this to initialize the AU before beginning to render.
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    if (_outputBus.format.channelCount != _inputBus.format.channelCount) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FailedInitialization userInfo:nil];
        }
        // Notify superclass that initialization was not successful
        self.renderResourcesAllocated = NO;
        return NO;
    }
    if (![buffer.format isEqual:_outputBus.format]) {
        buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:_outputBus.format frameCapacity:self.maximumFramesToRender];
    }
    
    return YES;
}

typedef void(^ProcessEventsBlock)(AudioBufferList       *inBuffer,
                                  AudioBufferList       *outBuffer,
                                  const AudioTimeStamp  *timestamp,
                                  int                   frameCount,
                                  const AURenderEvent   *realtimeEventListHead);



-(ProcessEventsBlock)processEventsBlock {
    
    // Default implemenation is a pass through.
    return ^(AudioBufferList       *inBuffer,
             AudioBufferList       *outBuffer,
             const AudioTimeStamp  *timestamp,
             int                   frameCount,
             const AURenderEvent   *realtimeEventListHead) {
        
        for (int i = 0; i < inBuffer->mNumberBuffers; i++) {
            memcpy(outBuffer->mBuffers[i].mData, inBuffer->mBuffers[i].mData, inBuffer->mBuffers[i].mDataByteSize);
        }
    };
}
// Subclassers must provide a AUInternalRenderBlock (via a getter) to implement rendering.
- (AUInternalRenderBlock)internalRenderBlock {
    
    const AudioBufferList *originalBuffer = buffer.audioBufferList;
    AudioBufferList *mutableBuffer = buffer.mutableAudioBufferList;
    
    int bytesPerFrame = buffer.format.streamDescription->mBytesPerFrame;
    int channels = buffer.format.channelCount;
    
    void(^prepareBuffer)(int) = ^(int frames) {
        mutableBuffer->mNumberBuffers = originalBuffer->mNumberBuffers;
        for (int i = 0; i < channels; i++) {
            mutableBuffer->mBuffers[i].mNumberChannels = originalBuffer->mBuffers[i].mNumberChannels;
            mutableBuffer->mBuffers[i].mData = originalBuffer->mBuffers[i].mData;
            mutableBuffer->mBuffers[i].mDataByteSize = frames * bytesPerFrame;
        }
    };
    
    ProcessEventsBlock processEvents = [self processEventsBlock];
    
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        
        prepareBuffer(frameCount);
        AudioUnitRenderActionFlags flags = 0;
        AUAudioUnitStatus status = pullInputBlock(&flags, timestamp, frameCount, 0, mutableBuffer);
        if (status) return status;
        
        
        AudioBufferList *outAudioBufferList = outputData;
        if (outAudioBufferList->mBuffers[0].mData == NULL) {
            for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = mutableBuffer->mBuffers[i].mData;
            }
        }
        
        processEvents(mutableBuffer,outAudioBufferList,timestamp,frameCount,realtimeEventListHead);
        return noErr;
    };
}
-(AUAudioUnitBusArray *)inputBusses {
    return _inputBusses;
}
-(AUAudioUnitBusArray *)outputBusses {
    return _outputBusses;
}
@end
