//
//  ViewController.m
//  AudioCollection-Agora
//
//  Created by ZQ on 2020/12/29.
//

#import "ViewController.h"
#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#import "MIConst.h"
#import "MIAudioUnit.h"


@interface ViewController ()<AgoraRtcEngineDelegate>
@property (nonatomic,strong) AgoraRtcEngineKit *agoraKit;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    _agoraKit = [AgoraRtcEngineKit sharedEngineWithAppId:MIAgoraAppID delegate:self];
    
    [[MIAudioUnit shareInstance] startAudioUnitRecorder];  // 启动AudioUnit录制
}

- (IBAction)onpressedBtnJoinChannel:(id)sender {
    NSString *ver = [AgoraRtcEngineKit getSdkVersion];
    NSLog(@"QiDebug, ver:%@",ver);
    
    [self.agoraKit setChannelProfile:AgoraChannelProfileLiveBroadcasting];
    [self.agoraKit setClientRole:AgoraClientRoleBroadcaster];
    [self.agoraKit disableVideo];
    [self.agoraKit enableExternalAudioSourceWithSampleRate:48000 channelsPerFrame:1];
    [self.agoraKit setDefaultAudioRouteToSpeakerphone:YES];
    
    int joinRes = [self.agoraKit joinChannelByToken:nil channelId:@"22222" info:nil uid:0 joinSuccess:nil];
    NSLog(@"QiDebug, join channel res: %d",joinRes);
    
    [MIAudioUnit shareInstance].agoraEngine = self.agoraKit;
}


- (void)rtcEngine:(AgoraRtcEngineKit *_Nonnull)engine didJoinChannel:(NSString *_Nonnull)channel withUid:(NSUInteger)uid elapsed:(NSInteger)elapsed
{

    NSLog(@"QiDebug, join channel success, uid:%lu\n",uid);
}

@end
