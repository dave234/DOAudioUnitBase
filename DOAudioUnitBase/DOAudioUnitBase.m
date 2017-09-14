//
//  DOAudioUnitBase.m
//  DOAudioUnitBase
//
//  Created by dave on 9/13/17.
//  Copyright © 2017 oneill. All rights reserved.
//

#import "DOAudioUnitBase.h"
#import <Accelerate/Accelerate.h>



@interface DOBus: AUAudioUnitBus
@property AVAudioPCMBuffer *buffer;
@end

@implementation DOBus
@end

typedef struct {
    AudioStreamBasicDescription *format;
    AudioBufferList *buffer;
    int hasData;
} ChannelBuffer;

typedef struct {
    ChannelBuffer *buffers;
    int count;
} ChannelBufferArray;

typedef struct {
    AudioStreamBasicDescription format;
    const AudioBufferList *backingBuffer;
    AudioBufferList *clientBuffer;
    int enabled;
} RenderBuffer;

void RenderBufferPrepare(RenderBuffer *inputBuffer, int frames) {
    inputBuffer->clientBuffer->mNumberBuffers = inputBuffer->backingBuffer->mNumberBuffers;
    int bytesPerFrame = inputBuffer->format.mBytesPerFrame;
    for (int i = 0; i < inputBuffer->clientBuffer->mNumberBuffers; i++) {
        inputBuffer->clientBuffer->mBuffers[i].mNumberChannels = inputBuffer->backingBuffer->mBuffers[i].mNumberChannels;
        inputBuffer->clientBuffer->mBuffers[i].mData = inputBuffer->backingBuffer->mBuffers[i].mData;
        inputBuffer->clientBuffer->mBuffers[i].mDataByteSize = frames * bytesPerFrame;
    }
}


typedef struct {
    int count;
    RenderBuffer buffers[1];
} InputBufferArray;


void InputBuffersPrepare(InputBufferArray *inputBuffers, int frameCount) {
    for (int i = 0; i < inputBuffers->count; i++) {
        RenderBuffer *inputBuffer = &inputBuffers->buffers[i];
        if (inputBuffers->buffers[i].enabled) {
            RenderBufferPrepare(inputBuffer, frameCount);
        }
    }
}


@implementation DOAudioUnitBase {
    AUAudioUnitBusArray *_inputBusses;
    AUAudioUnitBusArray *_outputBusses;
    InputBufferArray *_inputBuffers;
    DOBus *_outputBus;
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
    AUAudioUnitBus *inputBus = [[DOBus alloc]initWithFormat:format error:&error];
    _outputBus = [[DOBus alloc]initWithFormat:format error:&error];
    
    if (error) NSLog(@"error %@",error);
    
    _inputBusses  = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeInput
                                                            busses: @[inputBus]];
    
    _outputBusses = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                           busType:AUAudioUnitBusTypeOutput
                                                            busses: @[_outputBus]];
    
    return self;
}

// Allocate resources required to render.
// Hosts must call this to initialize the AU before beginning to render.
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    if (!_outputBus.buffer || ![_outputBus.buffer.format isEqual:_outputBus.format]) {
        _outputBus.buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:_outputBus.format frameCapacity:self.maximumFramesToRender];
    }
    for (DOBus *inputBus in _inputBusses) {
        if (!inputBus.buffer || [inputBus.buffer.format isEqual:inputBus.format]) {
            inputBus.buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:inputBus.format frameCapacity:self.maximumFramesToRender];
        }
    }
    [self setRenderBuffers];
    return YES;
}

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
-(MultiChannelProccessBlock)multiChannelProccessBlock {
    
    
    // Processing as stereo floats for example, but any format could be proccessed/converted here.
    // Both input and output channels have formats.
    // (format->mFormatFlags & kLinearPCMFormatFlagIsFloat) means they're floats else ints
    // format->mBytesPerFrame is sample size
    
    
    return ^(ChannelBufferArray    *inputChannels,
             ChannelBuffer         *outputChannel,
             const AudioTimeStamp  *timestamp,
             int                   frameCount,
             const AURenderEvent   *realtimeEventListHead) {
      
    
        
        AudioBufferList *output = outputChannel->buffer;
        for (int bus = 0; bus < inputChannels->count; bus++) {
            AudioBufferList *inputBuffer = inputChannels->buffers[bus].buffer;
            for (int i = 0; i < inputBuffer->mNumberBuffers; i++) {
                vDSP_vadd(inputBuffer->mBuffers[i].mData, 1, output->mBuffers[i].mData, i, output->mBuffers[i].mData, 1, frameCount);
            }
        }
    };
}

-(void)setRenderBuffers {
    InputBufferArray *oldBuffers = _inputBuffers;
    int bufferCount = (int)_inputBusses.count;
    InputBufferArray *newBuffers = malloc(sizeof(InputBufferArray) + ((bufferCount - 1) * ( sizeof(RenderBuffer))));
    for (int i = 0; i < bufferCount; i++) {
        DOBus *bus = (DOBus *)_inputBusses[i];
        RenderBuffer *inputBuffer = &newBuffers->buffers[i];
        inputBuffer->backingBuffer = bus.buffer.audioBufferList;
        inputBuffer->clientBuffer = bus.buffer.mutableAudioBufferList;
        inputBuffer->format = *bus.buffer.format.streamDescription;
    }
    newBuffers->count = bufferCount;
    _inputBuffers = newBuffers;
    if (oldBuffers) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                           
                           free(oldBuffers);
        });
    }
    
}

// Subclassers must provide a AUInternalRenderBlock (via a getter) to implement rendering.
- (AUInternalRenderBlock)internalRenderBlock {
    
    InputBufferArray *renderBuffers = _inputBuffers;
    __block RenderBuffer outputBuffer = {
        .format = *_outputBus.format.streamDescription,
        .backingBuffer = _outputBus.buffer.audioBufferList,
        .clientBuffer = _outputBus.buffer.mutableAudioBufferList,
        .enabled = true
    };
    ProcessEventsBlock processEvents = [self processEventsBlock];
    
    MultiChannelProccessBlock multiChannelProcess = [self multiChannelProccessBlock];
    
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        
        InputBufferArray *inputBuffers = renderBuffers; // <-- Here's the atomic swap;  Goal is to be able to increase _inputBusses count.
        
        InputBuffersPrepare(inputBuffers, frameCount);
        RenderBufferPrepare(&outputBuffer, frameCount);
        ChannelBuffer clientBuffers[inputBuffers->count];
        
        
        AudioUnitRenderActionFlags flags = 0;
        AUAudioUnitStatus status = 0;
        for (int i = 0; i < inputBuffers->count; i ++) {
            RenderBuffer *inputBuffer = &inputBuffers->buffers[i];
            ChannelBuffer *clientBuffer = &clientBuffers[i];
            clientBuffer->hasData = false;
            clientBuffer->buffer = inputBuffer->clientBuffer;
            clientBuffer->format = &inputBuffer->format;
            if (!inputBuffer->enabled) {
                continue;
            }
            status = pullInputBlock(&flags, timestamp, frameCount, i, inputBuffer->clientBuffer);
            if (status == 0) {
                clientBuffer->hasData = true;
            }
            else {
                if (status != kAudioUnitErr_NoConnection) {
                    return status;
                }
                status = 0;
            }
            
        }
        
        AudioBufferList *outAudioBufferList = outputData;
        if (outAudioBufferList->mBuffers[0].mData == NULL) {
            for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = outputBuffer.clientBuffer->mBuffers[i].mData;
                memset(outAudioBufferList->mBuffers[i].mData, 0, outAudioBufferList->mBuffers[i].mDataByteSize);
            }
        }
        ChannelBufferArray channelBuffers;
        channelBuffers.count = inputBuffers->count;
        channelBuffers.buffers = clientBuffers;
        
        ChannelBuffer outputChannel;
        outputChannel.buffer = outAudioBufferList;
        outputChannel.format = &outputBuffer.format;
        
        if (multiChannelProcess) {
            multiChannelProcess(&channelBuffers, &outputChannel, timestamp, frameCount, realtimeEventListHead);
        }
        else if (processEvents) {
            processEvents(channelBuffers.buffers[0].buffer,outAudioBufferList,timestamp,frameCount,realtimeEventListHead);
        }
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
