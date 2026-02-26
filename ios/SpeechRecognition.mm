#import "SpeechRecognition.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <React/RCTLog.h>

@implementation SpeechRecognition {
    bool hasListeners;

    AVAudioEngine *_audioEngine;
    SFSpeechAudioBufferRecognitionRequest *_recognitionRequest;
    SFSpeechRecognitionTask *_recognitionTask;
    SFSpeechRecognizer *_speechRecognizer;
    AVAudioInputNode *_inputNode;

    NSString *_finalTranscript;
    bool _isStopped;
    bool _hasSpeechBegun;
    NSTimer *_silenceTimer;
}

RCT_EXPORT_MODULE(SpeechRecognition)

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self requestPermissionsAndSetupAudio];
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"onSpeechStart",
        @"onSpeechBegin",
        @"onSpeechEnd",
        @"onSpeechError",
        @"onSpeechResults",
        @"onSpeechPartialResults",
        @"onSpeechVolumeChanged",
        @"onSpeechAudioBuffer",
        @"onSpeechEvent",
        @"onTestEvent"
    ];
}

- (void)startObserving {
    hasListeners = YES;
    NSLog(@"✅ startObserving called");
}

- (void)stopObserving {
    hasListeners = NO;
    NSLog(@"❌ stopObserving called");
}

- (void)sendEventWithName:(NSString *)name body:(id)body {
    if (hasListeners) {
        [super sendEventWithName:name body:body];
    } else {
        NSLog(@"❌ No listeners for event %@", name);
    }
}

- (void)requestPermissionsAndSetupAudio {
    AVAudioSession *session = [AVAudioSession sharedInstance];

    [session requestRecordPermission:^(BOOL granted) {
        if (!granted) {
            [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Microphone permission denied", @"code": @(-10)}];
            return;
        }

        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                switch (status) {
                    case SFSpeechRecognizerAuthorizationStatusAuthorized:
                        RCTLogInfo(@"Permissions granted");
                        [self setupAudioSession];
                        break;
                    case SFSpeechRecognizerAuthorizationStatusDenied:
                        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Speech permission denied", @"code": @(-11)}];
                        break;
                    case SFSpeechRecognizerAuthorizationStatusRestricted:
                        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Speech recognition restricted", @"code": @(-12)}];
                        break;
                    case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Speech permission not determined", @"code": @(-13)}];
                        break;
                }
            });
        }];
    }];
}

- (void)setupAudioSession {
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    [audioSession setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": error.localizedDescription, @"code": @(-100)}];
        return;
    }

    [audioSession setMode:AVAudioSessionModeMeasurement error:&error];
    if (error) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": error.localizedDescription, @"code": @(-101)}];
        return;
    }

    [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": error.localizedDescription, @"code": @(-102)}];
        return;
    }
    NSLog(@"✅ Audio session setup complete");
    RCTLogInfo(@"Audio session setup complete");
}

- (void)resetSilenceTimer {
    if (_isStopped) return;
    [_silenceTimer invalidate];
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                     target:self
                                                   selector:@selector(handleSilenceTimeout)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)handleSilenceTimeout {
    NSLog(@"🤫 Silence timeout reached");
    [self stopRecognitionSession];
}

// Calculate RMS (Root Mean Square) for volume level
- (float)calculateRMSFromBuffer:(AVAudioPCMBuffer *)buffer {
    if (buffer.floatChannelData == nil) return 0.0;
    
    float *samples = buffer.floatChannelData[0];
    AVAudioFrameCount frameLength = buffer.frameLength;
    
    if (frameLength == 0) return 0.0;
    
    float sumSquares = 0.0;
    for (AVAudioFrameCount i = 0; i < frameLength; i++) {
        sumSquares += samples[i] * samples[i];
    }
    
    float rms = sqrtf(sumSquares / frameLength);
    // Convert to dB-like scale (similar to Android's rmsdB)
    float dB = 20.0 * log10f(rms + 0.0001); // Add small value to avoid log(0)
    
    return dB;
}

// Convert audio buffer to base64 string
- (NSString *)bufferToBase64:(AVAudioPCMBuffer *)buffer {
    if (buffer.floatChannelData == nil) return @"";
    
    float *samples = buffer.floatChannelData[0];
    AVAudioFrameCount frameLength = buffer.frameLength;
    
    NSData *data = [NSData dataWithBytes:samples length:frameLength * sizeof(float)];
    return [data base64EncodedStringWithOptions:0];
}

RCT_EXPORT_METHOD(startListening:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    _isStopped = NO;
    _hasSpeechBegun = NO;
    _finalTranscript = @"";

    AVAudioSessionRecordPermission micPermission = [[AVAudioSession sharedInstance] recordPermission];
    if (micPermission != AVAudioSessionRecordPermissionGranted) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Microphone permission not granted", @"code": @(-10)}];
        reject(@"PERMISSION_DENIED", @"Microphone permission denied", nil);
        return;
    }

    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Speech permission denied", @"code": @(-11)}];
                reject(@"PERMISSION_DENIED", @"Speech permission denied", nil);
                return;
            }

            [self setupAudioSession];

            _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale currentLocale]];
            if (!_speechRecognizer.isAvailable) {
                [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Recognizer not available", @"code": @(-20)}];
                reject(@"NOT_AVAILABLE", @"Recognizer not available", nil);
                return;
            }

            _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
            _recognitionRequest.shouldReportPartialResults = YES;

            _audioEngine = [[AVAudioEngine alloc] init];
            _inputNode = _audioEngine.inputNode;

            AVAudioFormat *format = [_inputNode outputFormatForBus:0];
            
            __weak typeof(self) weakSelf = self;
            [_inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || strongSelf->_isStopped) return;
                
                // Append buffer to recognition request
                [strongSelf->_recognitionRequest appendAudioPCMBuffer:buffer];
                
                // Calculate and send volume level
                float rmsDb = [strongSelf calculateRMSFromBuffer:buffer];
                [strongSelf sendEventWithName:@"onSpeechVolumeChanged" body:@{@"value": @(rmsDb)}];
                
                // Send audio buffer as base64 (optional - can be heavy)
                // Uncomment if needed:
                // NSString *base64Buffer = [strongSelf bufferToBase64:buffer];
                // [strongSelf sendEventWithName:@"onSpeechAudioBuffer" body:@{@"buffer": base64Buffer}];
            }];

            NSError *startError = nil;
            [_audioEngine prepare];
            [_audioEngine startAndReturnError:&startError];
            if (startError) {
                [self sendEventWithName:@"onSpeechError" body:@{@"message": startError.localizedDescription, @"code": @(-30)}];
                reject(@"ENGINE_ERROR", startError.localizedDescription, startError);
                return;
            }

            // Send onSpeechStart - recognition is ready
            [self sendEventWithName:@"onSpeechStart" body:@{@"message": @"Ready for speech"}];

            _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:_recognitionRequest
                                                            resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                
                if (result) {
                    NSString *transcript = result.bestTranscription.formattedString;
                    
                    // Send onSpeechBegin on first speech detected
                    if (!strongSelf->_hasSpeechBegun && transcript.length > 0) {
                        strongSelf->_hasSpeechBegun = YES;
                        [strongSelf sendEventWithName:@"onSpeechBegin" body:@{@"message": @"Speech detected"}];
                    }
                    
                    strongSelf->_finalTranscript = (transcript.length == 0 && strongSelf->_finalTranscript.length > 0) 
                        ? strongSelf->_finalTranscript 
                        : transcript;
                    
                    NSLog(@"✅ Transcript: %@", strongSelf->_finalTranscript);

                    if (result.isFinal) {
                        NSLog(@"✅ Final Result: %@", transcript);
                        [strongSelf sendEventWithName:@"onSpeechResults" body:@{
                            @"value": strongSelf->_finalTranscript ?: @"",
                            @"results": @{
                                @"transcriptions": @[@{
                                    @"text": strongSelf->_finalTranscript ?: @"",
                                    @"confidence": @(result.bestTranscription.segments.count > 0 
                                        ? result.bestTranscription.segments[0].confidence 
                                        : 0.0)
                                }]
                            }
                        }];
                        [strongSelf resetSilenceTimer];
                        [strongSelf stopRecognitionSession];
                    } else {
                        [strongSelf sendEventWithName:@"onSpeechPartialResults" body:@{
                            @"value": transcript,
                            @"results": @{
                                @"transcriptions": @[@{
                                    @"text": transcript,
                                    @"confidence": @(0.0)
                                }]
                            }
                        }];
                        [strongSelf resetSilenceTimer];
                    }
                }

                if (error) {
                    NSLog(@"❌ Recognition error: %@", error.localizedDescription);
                    [strongSelf sendEventWithName:@"onSpeechError" body:@{
                        @"message": error.localizedDescription,
                        @"code": @(error.code)
                    }];
                    [strongSelf stopRecognitionSession];
                }
            }];

            resolve(@"Listening started");
        });
    }];
}

- (void)stopRecognitionSession {
    if (_isStopped) return;
    _isStopped = YES;

    if (_silenceTimer) {
        [_silenceTimer invalidate];
        _silenceTimer = nil;
    }

    if (_audioEngine && _audioEngine.isRunning) {
        [_audioEngine stop];
        [_inputNode removeTapOnBus:0];
        [_recognitionRequest endAudio];
    }

    if (_recognitionTask) {
        [_recognitionTask cancel];
        _recognitionTask = nil;
    }

    _recognitionRequest = nil;
    _speechRecognizer = nil;
    _audioEngine = nil;
    _inputNode = nil;

    NSError *err = nil;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&err];
    if (err) {
        NSLog(@"❌ Error deactivating AVAudioSession: %@", err.localizedDescription);
    }

    [self sendEventWithName:@"onSpeechEnd" body:@{@"message": @"Recognition stopped"}];
}

RCT_EXPORT_METHOD(destroy)
{
    NSLog(@"🗑 destroy called – cleaning up audio and recognition sessions");

    _isStopped = YES;
    _hasSpeechBegun = NO;

    if (_silenceTimer) {
        [_silenceTimer invalidate];
        _silenceTimer = nil;
    }

    if (_audioEngine) {
        if (_audioEngine.isRunning) {
            [_audioEngine stop];
        }

        if (_inputNode) {
            @try {
                [_inputNode removeTapOnBus:0];
            } @catch (NSException *exception) {
                NSLog(@"⚠️ Tried removing inputNode tap but it wasn't installed: %@", exception.reason);
            }
        }

        _audioEngine = nil;
    }

    if (_recognitionRequest) {
        [_recognitionRequest endAudio];
        _recognitionRequest = nil;
    }

    if (_recognitionTask) {
        [_recognitionTask cancel];
        _recognitionTask = nil;
    }

    _speechRecognizer = nil;
    _inputNode = nil;

    NSError *err = nil;
    [[AVAudioSession sharedInstance]
       setActive:NO
       withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
       error:&err];

    if (err) {
        NSLog(@"❌ Error deactivating AVAudioSession in destroy: %@", err.localizedDescription);
    }

    [self sendEventWithName:@"onSpeechEnd" body:@{@"message": @"Destroyed"}];
}

RCT_EXPORT_METHOD(stopListening)
{
    [self stopRecognitionSession];
}

// Send generic event (for custom events from native side)
- (void)sendSpeechEvent:(NSString *)eventType withParams:(NSDictionary *)params {
    NSMutableDictionary *eventData = [NSMutableDictionary dictionaryWithDictionary:params ?: @{}];
    eventData[@"eventType"] = eventType;
    [self sendEventWithName:@"onSpeechEvent" body:eventData];
}

RCT_EXPORT_METHOD(fireTestEvent) {
    NSLog(@"🔥 fireTestEvent called");
    if (hasListeners) {
        [self sendEventWithName:@"onTestEvent" body:@{@"message": @"Hello from native!"}];
    } else {
        NSLog(@"❌ No listeners active. Skipping event.");
    }
}

@end