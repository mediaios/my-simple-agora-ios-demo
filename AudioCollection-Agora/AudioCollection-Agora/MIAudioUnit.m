//
//  MIAudioUnit.m
//  MILive
//
//  Created by mediaios on 2019/5/16.
//  Copyright © 2019 iosmediadev@gmail.com. All rights reserved.
//

#import "MIAudioUnit.h"
#import "MIConst.h"

// Audio Unit Set Property
#define INPUT_BUS  1      ///< A I/O unit's bus 1 connects to input hardware (microphone).
#define OUTPUT_BUS 0      ///< A I/O unit's bus 0 connects to output hardware (speaker)


static OSStatus RecordCallBack (void *                            inRefCon,
                                AudioUnitRenderActionFlags *    ioActionFlags,
                                const AudioTimeStamp *            inTimeStamp,
                                UInt32                            inBusNumber,
                                UInt32                            inNumberFrames,
                                AudioBufferList * __nullable    ioData)
{
    MIAudioUnit *recorder = (__bridge MIAudioUnit *)inRefCon;
    AudioUnit captureUnit = recorder->m_audioUnit;
    if (!inRefCon) return 0;
    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:0];//获取当前时间0秒后的时间
    NSTimeInterval time=[date timeIntervalSince1970];
    
    
 
    AudioBuffer buffer;
    buffer.mData = recorder->m_audioBufferList->mBuffers[0].mData;
    buffer.mDataByteSize = recorder->m_audioBufferList->mBuffers[0].mDataByteSize;
    buffer.mNumberChannels = recorder->dataFormat.mChannelsPerFrame;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;

    OSStatus status = AudioUnitRender(captureUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      inBusNumber,
                                      inNumberFrames,
                                      &bufferList);
    
    if (!status) {
        NSLog(@"%s----line---%d----size:%d----",__func__,__LINE__,bufferList.mBuffers[0].mDataByteSize);
        if (!recorder.agoraEngine) {
            return 0;
        }
        [recorder.agoraEngine pushExternalAudioFrameRawData:(unsigned char *)bufferList.mBuffers[0].mData
                                                    samples:bufferList.mBuffers[0].mDataByteSize/2 timestamp:time];
    }else{
        NSLog(@"%s----line---%d----error:%d----",__func__,__LINE__,status);
    }
    
    return 0;
}



@implementation MIAudioUnit

static MIAudioUnit  *global_audioUnit = nil;
+ (instancetype)shareInstance
{
    if (!global_audioUnit) {
        global_audioUnit = [[MIAudioUnit alloc] init];
    }
    return global_audioUnit;
}

- (void)setUpAudioQueueWithFormatID:(UInt32)formatID
{
    dataFormat.mSampleRate = kAudioQueueRecorderSampleRate;
    dataFormat.mFormatID = formatID;
    dataFormat.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked);
    dataFormat.mChannelsPerFrame = 1;
    dataFormat.mFramesPerPacket = 1; // AudioQueue collection pcm data , need to set as this
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mBytesPerFrame = (dataFormat.mBitsPerChannel / 8) * dataFormat.mChannelsPerFrame;
    dataFormat.mBytesPerPacket = dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
}

- (NSString *)freeAudioUnit
{
    if (!m_audioUnit) {
        return @"AudioUnit is  NULL , don,t need to free";
    }
    [self stopAudioUnitRecorder];
    OSStatus status = AudioUnitUninitialize(m_audioUnit);
    if (status != noErr) {
        return [NSString stringWithFormat:@"AudioUnitUninitialize failed:%d",status];
    }
    OSStatus result =  AudioComponentInstanceDispose(m_audioUnit);
    if (result != noErr) {
        return [NSString stringWithFormat:@"AudioComponentInstanceDispose failed. status : %d \n",result];
    }else{
        
    }
    m_audioUnit = NULL;
    return @"AudioUnit object free";
}

- (void)startAudioUnitRecorder
{
    OSStatus status;
    if (self.m_isRunning) {
        return;
    }
    
    if (!m_audioUnit) {
        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        NSUInteger sessionOption = AVAudioSessionCategoryOptionMixWithOthers;
        sessionOption |= AVAudioSessionCategoryOptionAllowBluetooth;
        
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:sessionOption error:nil];
        [audioSession setMode:AVAudioSessionModeDefault error:nil];
        [audioSession setPreferredIOBufferDuration:0.02 error:nil];
        NSError *error;
        BOOL success = [audioSession setActive:YES error:&error];
        if (!success) {
            NSLog(@"<Error> audioSession setActive:YES error:nil");
        }
        if (error) {
            NSLog(@"<Error> setUpAudioSessionWithSampleRate : %@", error.localizedDescription);
        }
        
        
        
        [self initAudioComponent];
        [self initBuffer];
        [self setingAudioUnitPropertyAndFormat];
        [self initRecordeCallback];
//        [self setupRender];
        
        status = AudioUnitInitialize(m_audioUnit);
        if (status != noErr) {
            NSLog(@"AudioUnit, couldn't initialize AURemoteIO instance, status : %d ",status);
        }
    }
    
    
    status  = AudioOutputUnitStart(m_audioUnit);
    if (status == noErr) {
        self.m_isRunning = YES;
    }else{
        self.m_isRunning = NO;
        NSString *errorInfo = [self freeAudioUnit];
        NSLog(@"AudioUnit: %@",errorInfo);
    }
}

- (void)stopAudioUnitRecorder
{
    if (self.m_isRunning == NO) {
        return;
    }
    self.m_isRunning = NO;
    if (m_audioUnit != NULL) {
        OSStatus status = AudioOutputUnitStop(m_audioUnit);
        if (status) {
            NSLog(@"AudioUnit, stop AudioUnit failed.\n");
        }else{
            NSLog(@"AudioUnit, stop AudioUnit success.\n");
        }
    }
    
}

- (void)initAudioComponent
{
    OSStatus status;
    AudioComponentDescription audioDesc;
    audioDesc.componentType         = kAudioUnitType_Output;
    audioDesc.componentSubType      = kAudioUnitSubType_VoiceProcessingIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags        = 0;
    audioDesc.componentFlagsMask    = 0;
    
    AudioComponent inputComponent   = AudioComponentFindNext(NULL, &audioDesc);
    status = AudioComponentInstanceNew(inputComponent, &m_audioUnit);
    if (status != noErr) {
        m_audioUnit = NULL;
        NSLog(@"AudioUnit, couldn't create AudioUnit instance ");
    }
}

- (void)initBuffer {
    // Disable AU buffer allocation for the recorder, we allocate our own.
    UInt32 flag     = 0;
    OSStatus status = AudioUnitSetProperty(m_audioUnit,
                                           kAudioUnitProperty_ShouldAllocateBuffer,
                                           kAudioUnitScope_Output,
                                           INPUT_BUS,
                                           &flag,
                                           sizeof(flag));
    if (status != noErr) {
        NSLog(@"AudioUnit,couldn't AllocateBuffer of AudioUnitCallBack, status : %d",status);
    }
    m_audioBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList));
    m_audioBufferList->mNumberBuffers               = 1;
    m_audioBufferList->mBuffers[0].mNumberChannels  = dataFormat.mChannelsPerFrame;
    m_audioBufferList->mBuffers[0].mDataByteSize    = kAudioRecoderPCMMaxBuffSize * sizeof(short);
    m_audioBufferList->mBuffers[0].mData            = (short *)malloc(sizeof(short) * kAudioRecoderPCMMaxBuffSize);

}

- (void)setingAudioUnitPropertyAndFormat
{
    OSStatus status;
    [self setUpAudioQueueWithFormatID:kAudioFormatLinearPCM];
    
    status = AudioUnitSetProperty(m_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, 
                                  INPUT_BUS,
                                  &dataFormat,
                                  sizeof(dataFormat));
    if (status != noErr) {
        NSLog(@"AudioUnit,couldn't set the input client format on AURemoteIO, status : %d ",status);
    }
    
    UInt32 flag = 1;
    status = AudioUnitSetProperty(m_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  INPUT_BUS,
                                  &flag,
                                  sizeof(flag));
    if (status != noErr) {
        NSLog(@"AudioUnit,could not enable input on AURemoteIO, status : %d ",status);
    }
    
    flag = 0;
    status = AudioUnitSetProperty(m_audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  OUTPUT_BUS,
                                  &flag,
                                  sizeof(flag));
    if (status != noErr) {
        NSLog(@"AudioUnit,could not enable output on AURemoteIO, status : %d  ",status);
    }
    
    status = AudioUnitSetProperty(m_audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  OUTPUT_BUS,
                                  &dataFormat,
                                  sizeof(dataFormat));
    if (status != noErr) {
        NSLog(@"AudioUnit,kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input %d  ",status);
    }
    
}

- (void)initRecordeCallback {
    AURenderCallbackStruct recordCallback;
    recordCallback.inputProc        = RecordCallBack;
    recordCallback.inputProcRefCon  = (__bridge void *)self;
    OSStatus status                 = AudioUnitSetProperty(m_audioUnit,
                                                           kAudioOutputUnitProperty_SetInputCallback,
                                                           kAudioUnitScope_Global,
                                                           INPUT_BUS,
                                                           &recordCallback,
                                                           sizeof(recordCallback));
    
    if (status != noErr) {
        NSLog(@"AudioUnit, Audio Unit set record Callback failed, status : %d ",status);
    }
}

@end
