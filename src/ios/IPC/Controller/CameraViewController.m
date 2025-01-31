//
//  CameraViewController.m
//  TuyaSmartIPCDemo
//
//  Copyright (c) 2014-2021 Tuya Inc. (https://developer.tuya.com/)

#import "CameraViewController.h"
#import "CameraControlView.h"
#import "CameraPlaybackViewController.h"
#import "CameraSettingViewController.h"
#import "CameraCloudViewController.h"
#import "CameraMessageViewController.h"
#import "CameraPermissionUtil.h"
#import <TuyaSmartCameraM/TuyaSmartCameraM.h>
#import <AVFoundation/AVFoundation.h>
#import "CameraVideoView.h"

#define VideoViewWidth [UIScreen mainScreen].bounds.size.width
#define VideoViewHeight ([UIScreen mainScreen].bounds.size.width / 16 * 9)

#define kControlTalk        @"talk"
#define kControlRecord      @"record"
#define kControlPhoto       @"photo"
#define kControlPlayback    @"playback"
#define kControlCloud       @"Cloud"
#define kControlMessage     @"message"

@interface CameraViewController ()<TuyaSmartCameraDelegate, CameraControlViewDelegate, TuyaSmartCameraDPObserver>

@property (nonatomic, strong) NSString *devId;

@property (nonatomic, strong) UIView *videoContainer;

@property (nonatomic, strong) CameraControlView *controlView;

@property (nonatomic, strong) UIButton *soundButton;

@property (nonatomic, strong) UIButton *hdButton;

@property (nonatomic, strong) UIActivityIndicatorView *indicatorView;

@property (nonatomic, strong) UILabel *stateLabel;

@property (nonatomic, strong) UIButton *retryButton;

@property (nonatomic, strong) TuyaSmartDevice *device;

@property (nonatomic, strong) TuyaSmartCameraDPManager *dpManager;
/// Camera control class
@property (nonatomic, strong) id<TuyaSmartCameraType> cameraType;

@property (nonatomic, strong) CameraVideoView *videoView;
/// Record last mute status
@property (nonatomic, assign) BOOL lastMuted;
/// camera status
@property (nonatomic, assign, getter=isConnecting)      BOOL connecting;

@property (nonatomic, assign, getter=isConnected)       BOOL connected;

@property (nonatomic, assign, getter=isPreviewing)      BOOL previewing;

@property (nonatomic, assign, getter=isMuted)           BOOL muted;

@property (nonatomic, assign, getter=isTalking)         BOOL talking;

@property (nonatomic, assign, getter=isRecording)       BOOL recording;

@property (nonatomic, assign, getter=isHD)              BOOL HD;

@end

@implementation CameraViewController

- (void)dealloc {
    [self disConnect];
    [self.cameraType destory];
}

- (instancetype)initWithDeviceId:(NSString *)devId {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _devId = devId;
        _device = [TuyaSmartDevice deviceWithDeviceId:devId];
        _dpManager = [[TuyaSmartCameraDPManager alloc] initWithDeviceId:devId];
        _cameraType = [TuyaSmartCameraFactory cameraWithP2PType:@(_device.deviceModel.p2pType) deviceId:_device.deviceModel.devId delegate:self];
        _muted = YES;
        _lastMuted = _muted;
        _videoView = [[CameraVideoView alloc] initWithFrame:CGRectZero];
        _videoView.renderView = _cameraType.videoView;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleInterruption:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:[AVAudioSession sharedInstance]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIButton *rightBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [rightBtn setImage:[UIImage imageNamed:@"tp_top_bar_more"] forState:UIControlStateNormal];
    [rightBtn addTarget:self action:@selector(settingAction) forControlEvents:UIControlEventTouchUpInside];
    rightBtn.frame = CGRectMake(0, 0, 44, 44);
    [rightBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentRight];
    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithCustomView:rightBtn];
    self.navigationItem.rightBarButtonItems = @[rightItem];
    
    self.title = self.device.deviceModel.name;
    self.view.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.videoContainer];
    [self.view addSubview:self.indicatorView];
    [self.view addSubview:self.stateLabel];
    [self.view addSubview:self.retryButton];
    [self.view addSubview:self.controlView];
    [self.view addSubview:self.soundButton];
    [self.view addSubview:self.hdButton];
    
    // Tips: Speak、Record、Take Photo、Sound、HD, these buttons can be available after received video data.
    // Playback、Cloud Storage、Message, these buttons can be available after camera is connected.
    [self.retryButton addTarget:self action:@selector(retryAction) forControlEvents:UIControlEventTouchUpInside];
    [self.soundButton addTarget:self action:@selector(soundAction) forControlEvents:UIControlEventTouchUpInside];
    [self.hdButton addTarget:self action:@selector(hdAction) forControlEvents:UIControlEventTouchUpInside];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self retryAction];
    if (@available(iOS 11.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = NO;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self disConnect];
    if (@available(iOS 11.0, *)) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
    }
}

- (void)willEnterForeground {
    [self retryAction];
}

- (void)didEnterBackground {
    [self stopPreview];
    [self disConnect];
}

#pragma mark - Action

- (void)settingAction {
    CameraSettingViewController *settingVC = [CameraSettingViewController new];
    settingVC.devId = self.devId;
    settingVC.dpManager = self.dpManager;
    [self.navigationController pushViewController:settingVC animated:YES];
}

- (void)retryAction {
    if (!self.device.deviceModel.isOnline) {
        self.stateLabel.hidden = NO;
        self.stateLabel.text = NSLocalizedStringFromTable(@"title_device_offline", @"IPCLocalizable", @"");
        return;
    }
    if ([self isDoorbell]) {
        [self.device awakeDeviceWithSuccess:nil failure:nil];
    }
    [self connectCamera];
    [self showLoadingWithTitle:NSLocalizedStringFromTable(@"loading", @"IPCLocalizable", @"")];
    self.retryButton.hidden = YES;
}

- (void)soundAction {
    [self enableMute:!self.isMuted];
}

- (void)hdAction {
    TuyaSmartCameraDefinition definition = !self.isHD ? TuyaSmartCameraDefinitionHigh : TuyaSmartCameraDefinitionStandard;
    [self.cameraType setDefinition:definition];
}

- (void)talkAction {
    if ([CameraPermissionUtil microNotDetermined]) {
        [CameraPermissionUtil requestAccessForMicro:^(BOOL result) {
            if (result) {
                [self _talkAction];
            }
        }];
    }else if ([CameraPermissionUtil microDenied]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"" message:NSLocalizedStringFromTable(@"Micro permission denied", @"IPCLocalizable", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"ipc_settings_ok", @"IPCLocalizable", @"") style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:action];
        [self presentViewController:alert animated:YES completion:nil];
    }else {
        [self _talkAction];
    }
}

- (void)_talkAction {
    if (self.isTalking) {
        [self stopTalk];
        [self.controlView deselectedControl:kControlTalk];
    }else {
        [self.cameraType startTalk];
        _talking = YES;
    }
}

- (void)stopTalk {
    if (self.isTalking) {
        [self.cameraType stopTalk];
        _talking = NO;
    }
}

- (void)recordAction {
    [self checkPhotoPermision:^(BOOL result) {
        if (result) {
            if (self.isRecording) {
                [self stopRecord];
            }else {
                [self startRecord];
            }
        }
    }];
}

- (void)photoAction {
    [self checkPhotoPermision:^(BOOL result) {
        if (result) {
            [self.cameraType snapShoot];
        }
    }];
}

- (void)checkPhotoPermision:(void(^)(BOOL result))complete {
    if ([CameraPermissionUtil isPhotoLibraryNotDetermined]) {
        [CameraPermissionUtil requestPhotoPermission:complete];
    }else if ([CameraPermissionUtil isPhotoLibraryDenied]) {
        [self showAlertWithMessage:NSLocalizedStringFromTable(@"Photo library permission denied", @"IPCLocalizable", @"") complete:nil];
        !complete?:complete(NO);
    }else {
        !complete?:complete(YES);
    }
}

#pragma mark - Operation

- (BOOL)isDoorbell {
    return self.device.deviceModel.isLowPowerDevice;
}

- (void)connectCamera {
    if (self.isConnected || self.isConnecting) {
        return;
    }
    _connecting = YES;
    [self.controlView disableAllControl];
    [self.cameraType connectWithMode:TuyaSmartCameraConnectAuto];
}

- (void)startPreview {
    [self.videoContainer addSubview:self.videoView];
    self.videoView.frame = self.videoContainer.bounds;
    
    [self stopPlayback];
    [self.cameraType startPreview];
    _previewing = YES;
    [self enableMute:self.isMuted];
}

- (void)stopPreview {
    [self stopRecord];
    [self stopTalk];
    [self.cameraType stopPreview];
}

- (void)startRecord {
    if (self.isRecording) {
        return;
    }
    if (self.previewing) {
        [self.cameraType startRecord];
        _recording = YES;
    }
}

- (void)stopRecord {
    if (self.isRecording) {
        [self.cameraType stopRecord];
    }
}

- (void)enableMute:(BOOL)isMute {
    [self.cameraType enableMute:isMute forPlayMode:TuyaSmartCameraPlayModePreview];
}

- (void)stopPlayback {
    if (self.isRecording) {
        [self.cameraType stopRecord];
    }
    [self.cameraType stopPlayback];
}

- (void)disConnect {
    [self stopPreview];
    [self stopPlayback];
    [self.cameraType disConnect];
    self.connected = NO;
    self.connecting = NO;
}

#pragma mark - Loading && Alert

- (void)showLoadingWithTitle:(NSString *)title {
    self.indicatorView.hidden = NO;
    [self.indicatorView startAnimating];
    self.stateLabel.hidden = NO;
    self.stateLabel.text = title;
}

- (void)stopLoading {
    [self.indicatorView stopAnimating];
    self.indicatorView.hidden = YES;
    self.stateLabel.hidden = YES;
}

- (void)showAlertWithMessage:(NSString *)message {
    UIAlertController *alertVc = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertVc addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"ty_alert_confirm", @"IPCLocalizable", @"") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertVc animated:YES completion:nil];
}

- (void)showAlertWithMessage:(NSString *)msg complete:(void(^)(void))complete {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"ipc_settings_ok", @"IPCLocalizable", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        !complete?:complete();
    }];
    [alert addAction:action];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - CameraControlViewDelegate

- (void)controlView:(CameraControlView *)controlView didSelectedControl:(NSString *)identifier {
    if ([identifier isEqualToString:kControlTalk]) {
        [self talkAction];
        return;
    }
    if ([identifier isEqualToString:kControlPlayback]) {
        CameraPlaybackViewController *vc = [[CameraPlaybackViewController alloc] initWithDeviceId:self.devId];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if ([identifier isEqualToString:kControlCloud]) {
        CameraCloudViewController *vc = [CameraCloudViewController new];
        vc.devId = self.devId;
        [self.navigationController pushViewController:vc animated:YES];
    }
    if ([identifier isEqualToString:kControlMessage]) {
        CameraMessageViewController *vc = [CameraMessageViewController new];
        vc.devId = self.devId;
        [self.navigationController pushViewController:vc animated:YES];
    }
    BOOL needPhotoPermission = [identifier isEqualToString:kControlPhoto] || [identifier isEqualToString:kControlRecord];
    if (needPhotoPermission) {
        if ([CameraPermissionUtil isPhotoLibraryNotDetermined]) {
            [CameraPermissionUtil requestPhotoPermission:^(BOOL result) {
                if (result) {
                    if ([identifier isEqualToString:kControlRecord]) {
                        [self recordAction];
                    } else if ([identifier isEqualToString:kControlPhoto]) {
                        [self photoAction];
                    }
                }
            }];
        }else if ([CameraPermissionUtil isPhotoLibraryDenied]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"" message:NSLocalizedStringFromTable(@"Photo library permission denied", @"IPCLocalizable", @"") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"ipc_settings_ok", @"IPCLocalizable", @"") style:UIAlertActionStyleCancel handler:nil];
            [alert addAction:action];
            [self presentViewController:alert animated:YES completion:nil];
        }else {
            if ([identifier isEqualToString:kControlRecord]) {
                [self recordAction];
            } else if ([identifier isEqualToString:kControlPhoto]) {
                [self photoAction];
            }
        }
    }
}

#pragma mark - TuyaSmartCameraDelegate

- (void)cameraDidConnected:(id<TuyaSmartCameraType>)camera {
    [self.cameraType enterPlayback];
    _connecting = NO;
    _connected = YES;
    NSDictionary *config = [TuyaSmartP2pConfigService getCachedConfigWithDeviceModel:self.device.deviceModel];
    [self audioAttributesMap:[config objectForKey:@"audioAttributes"]];
    [self startPreview];
}

- (void)cameraDisconnected:(id<TuyaSmartCameraType>)camera {
    _connecting = NO;
    _connected = NO;
    [self.controlView disableAllControl];
    self.retryButton.hidden = NO;
}

- (void)cameraDidBeginPreview:(id<TuyaSmartCameraType>)camera {
    [self.cameraType getHD];
    [self.controlView enableAllControl];
    [self stopLoading];
}

- (void)cameraDidStopPreview:(id<TuyaSmartCameraType>)camera {
    _previewing = NO;
}

- (void)cameraDidBeginTalk:(id<TuyaSmartCameraType>)camera {
    [self.controlView selectedControl:kControlTalk];
}

- (void)cameraDidStopTalk:(id<TuyaSmartCameraType>)camera {
    _talking = NO;
}

- (void)cameraSnapShootSuccess:(id<TuyaSmartCameraType>)camera {
    [self showAlertWithMessage:NSLocalizedStringFromTable(@"ipc_multi_view_photo_saved", @"IPCLocalizable", @"") complete:nil];
}

- (void)cameraDidStartRecord:(id<TuyaSmartCameraType>)camera {
    [self.controlView selectedControl:kControlRecord];
}

- (void)cameraDidStopRecord:(id<TuyaSmartCameraType>)camera {
    _recording = NO;
    [self.controlView deselectedControl:kControlRecord];
    [self showAlertWithMessage:NSLocalizedStringFromTable(@"ipc_multi_view_video_saved", @"IPCLocalizable", @"")];
}

- (void)camera:(id<TuyaSmartCameraType>)camera definitionChanged:(TuyaSmartCameraDefinition)definition{
    _HD = definition >= TuyaSmartCameraDefinitionHigh;
    NSString *imageName = @"ty_camera_control_sd_normal";
    if (_HD) {
        imageName = @"ty_camera_control_hd_normal";
    }
    [self.hdButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
}

- (void)camera:(id<TuyaSmartCameraType>)camera didReceiveMuteState:(BOOL)isMute playMode:(TuyaSmartCameraPlayMode)playMode {
    if (playMode == TuyaSmartCameraPlayModePreview) {
        _muted = isMute;
    }
    
    NSString *imageName = @"ty_camera_soundOn_icon";
    if (isMute) {
        imageName = @"ty_camera_soundOff_icon";
    }
    [self.soundButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
}

- (void)camera:(id<TuyaSmartCameraType>)camera resolutionDidChangeWidth:(NSInteger)width height:(NSInteger)height {
    [self.cameraType getDefinition];
}

- (void)camera:(id<TuyaSmartCameraType>)camera didOccurredErrorAtStep:(TYCameraErrorCode)errStepCode specificErrorCode:(NSInteger)errorCode {
    if (errStepCode == TY_ERROR_CONNECT_FAILED || errStepCode == TY_ERROR_CONNECT_DISCONNECT) {
        _connecting = NO;
        _connected = NO;
        [self stopLoading];
        self.retryButton.hidden = NO;
        [self.controlView disableAllControl];
    }
    else if (errStepCode == TY_ERROR_START_PREVIEW_FAILED) {
        _previewing = NO;
        [self stopLoading];
        self.retryButton.hidden = NO;
    }
    else if (errStepCode == TY_ERROR_START_TALK_FAILED) {
        _talking = NO;
        [self showAlertWithMessage:NSLocalizedStringFromTable(@"ipc_errmsg_mic_failed", @"IPCLocalizable", @"")];
    }
    else if (errStepCode == TY_ERROR_SNAPSHOOT_FAILED) {
        [self showAlertWithMessage:NSLocalizedStringFromTable(@"fail", @"IPCLocalizable", @"") complete:nil];
    }
    else if (errStepCode == TY_ERROR_RECORD_FAILED) {
        _recording = NO;
        [self showAlertWithMessage:NSLocalizedStringFromTable(@"record failed", @"IPCLocalizable", @"")];
    }
}

#pragma mark - Private

- (void)audioAttributesMap:(NSDictionary *)attributes {
    __block BOOL supportSound = NO;
    __block BOOL supportTalk = NO;
    BOOL couldChangeAudioMode = NO;
    if (!attributes) { return; }
    NSArray *hardwareCapability = [attributes objectForKey:@"hardwareCapability"];
    NSArray *callMode = [attributes objectForKey:@"callMode"];
    if (!hardwareCapability || hardwareCapability.count == 0) {
        return;
    }
    [hardwareCapability enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj integerValue] == 1) {
            supportSound = YES;
        }
        if ([obj integerValue] == 2) {
            supportTalk = YES;
        }
    }];
    
    if (!callMode || callMode.count == 0) {
        return;
    }
    
    if (callMode.count >= 2) {
        couldChangeAudioMode = YES;
    }else {
        couldChangeAudioMode = NO;
    }
    
    NSLog(@"isSupportInstantTalkback:%@", @(couldChangeAudioMode));
    NSLog(@"isSupportTalk:%@", @(supportTalk));
    NSLog(@"isSupportSound:%@", @(supportSound));
}

#pragma mark - AudioSession implementations
// Incoming call sound recovery
- (void)handleInterruption:(NSNotification *)notification {
    NSInteger type = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        // record last mute status
        _lastMuted = self.isMuted;
        // The call was not muted before, so it should be muted temporarily
        if (!self.isMuted) {
            [self enableMute:YES];
        }
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        // The call was not muted before, and the sound needs to be restored at this time
        if (!_lastMuted) {
            [self enableMute:NO];
            _lastMuted = YES;
        }
    }
}

#pragma mark - Accessor

- (UIView *)videoContainer {
    if (!_videoContainer) {
        _videoContainer = [[UIView alloc] initWithFrame:CGRectMake(0, APP_TOP_BAR_HEIGHT, VideoViewWidth, VideoViewHeight)];
        _videoContainer.backgroundColor = [UIColor blackColor];
    }
    return _videoContainer;
}

- (NSArray *)controlDatas {
    return @[@{
                 @"image": @"ty_camera_mic_icon",
                 @"title": NSLocalizedStringFromTable(@"ipc_panel_button_speak", @"IPCLocalizable", @""),
                 @"identifier": kControlTalk
                 },
             @{
                 @"image": @"ty_camera_rec_icon",
                 @"title": NSLocalizedStringFromTable(@"ipc_panel_button_record", @"IPCLocalizable", @""),
                 @"identifier": kControlRecord
                 },
             @{
                 @"image": @"ty_camera_photo_icon",
                 @"title": NSLocalizedStringFromTable(@"ipc_panel_button_screenshot", @"IPCLocalizable", @""),
                 @"identifier": kControlPhoto
                 },
             @{
                 @"image": @"ty_camera_playback_icon",
                 @"title": NSLocalizedStringFromTable(@"pps_flashback", @"IPCLocalizable", @""),
                 @"identifier": kControlPlayback
                 },
             @{
                 @"image": @"ty_camera_cloud_icon",
                 @"title": NSLocalizedStringFromTable(@"ipc_panel_button_cstorage", @"IPCLocalizable", @""),
                 @"identifier": kControlCloud
                 },
             @{
                 @"image": @"ty_camera_message",
                 @"title": NSLocalizedStringFromTable(@"ipc_panel_button_message", @"IPCLocalizable", @""),
                 @"identifier": kControlMessage
                 }
             ];
}

- (CameraControlView *)controlView {
    if (!_controlView) {
        CGFloat top = VideoViewHeight + APP_TOP_BAR_HEIGHT;
        CGFloat width = self.view.frame.size.width;
        CGFloat height = self.view.frame.size.height - top;
        _controlView = [[CameraControlView alloc] initWithFrame:CGRectMake(0, top, width, height)];
        _controlView.sourceData = [self controlDatas];
        _controlView.delegate = self;
    }
    return _controlView;
}

- (UIButton *)soundButton {
    if (!_soundButton) {
        _soundButton = [[UIButton alloc] initWithFrame:CGRectMake(8, APP_TOP_BAR_HEIGHT + VideoViewHeight - 50, 44, 44)];
        [_soundButton setImage:[UIImage imageNamed:@"ty_camera_soundOff_icon"] forState:UIControlStateNormal];
    }
    return _soundButton;
}

- (UIButton *)hdButton {
    if (!_hdButton) {
        _hdButton = [[UIButton alloc] initWithFrame:CGRectMake(60, APP_TOP_BAR_HEIGHT + VideoViewHeight - 50, 44, 44)];
        [_hdButton setImage:[UIImage imageNamed:@"ty_camera_control_sd_normal"] forState:UIControlStateNormal];
    }
    return _hdButton;
}

- (UIActivityIndicatorView *)indicatorView {
    if (!_indicatorView) {
        _indicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        CGPoint center = self.videoContainer.center;
        center.y -= 20;
        _indicatorView.center = center;
        _indicatorView.hidden = YES;
    }
    return _indicatorView;
}

- (UILabel *)stateLabel {
    if (!_stateLabel) {
        _stateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(self.indicatorView.frame) + 8, VideoViewWidth, 20)];
        _stateLabel.textAlignment = NSTextAlignmentCenter;
        _stateLabel.textColor = [UIColor whiteColor];
        _stateLabel.hidden = YES;
    }
    return _stateLabel;
}

- (UIButton *)retryButton {
    if (!_retryButton) {
        _retryButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, VideoViewWidth, 40)];
        _retryButton.center = self.videoContainer.center;
        [_retryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_retryButton setTitle:NSLocalizedStringFromTable(@"connect failed, click retry", @"IPCLocalizable", @"") forState:UIControlStateNormal];
        _retryButton.hidden = YES;
    }
    return _retryButton;
}

@end
