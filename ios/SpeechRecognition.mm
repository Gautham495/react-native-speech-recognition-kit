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
    @"onSpeechResults",
    @"onSpeechPartialResults",
    @"onSpeechEnd",
    @"onSpeechError",
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

RCT_EXPORT_METHOD(startListening:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  _isStopped = NO;
  _finalTranscript = @"";
  
  AVAudioSessionRecordPermission micPermission = [[AVAudioSession sharedInstance] recordPermission];
  if (micPermission != AVAudioSessionRecordPermissionGranted) {
    [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Microphone permission not granted"}];
    reject(@"PERMISSION_DENIED", @"Microphone permission denied", nil);
    return;
  }
  
  [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Speech permission denied"}];
        reject(@"PERMISSION_DENIED", @"Speech permission denied", nil);
        return;
      }
      
      [self setupAudioSession];
      
      NSLocale *locale = self.recognitionLanguage.length > 0
      ? [[NSLocale alloc] initWithLocaleIdentifier:[self.recognitionLanguage stringByReplacingOccurrencesOfString:@"-" withString:@"_"]]
      : [NSLocale currentLocale];
      
      _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
      
      if (!_speechRecognizer.isAvailable) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": @"Recognizer not available"}];
        reject(@"NOT_AVAILABLE", @"Recognizer not available", nil);
        return;
      }
      
      _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
      _recognitionRequest.shouldReportPartialResults = YES;
      
      _audioEngine = [[AVAudioEngine alloc] init];
      _inputNode = _audioEngine.inputNode;
      
      AVAudioFormat *format = [_inputNode outputFormatForBus:0];
      [_inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [_recognitionRequest appendAudioPCMBuffer:buffer];
      }];
      
      NSError *startError = nil;
      [_audioEngine prepare];
      [_audioEngine startAndReturnError:&startError];
      if (startError) {
        [self sendEventWithName:@"onSpeechError" body:@{@"message": startError.localizedDescription}];
        reject(@"ENGINE_ERROR", startError.localizedDescription, startError);
        return;
      }
      
      [self sendEventWithName:@"onSpeechStart" body:nil];
      
      _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:_recognitionRequest
                                                         resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        if (result) {
          NSString *transcript = result.bestTranscription.formattedString;
          // _finalTranscript = transcript; //let's store that in variable
          _finalTranscript = (transcript.length == 0 && _finalTranscript.length > 0) ? _finalTranscript : transcript;
          NSLog(@"✅ Continue Result: %@", _finalTranscript);
          
          NSLog(@"isRecognitionStopped? ", _isStopped ? @"YES" : @"NO");
          
          if (result.isFinal) {
            [self sendEventWithName:@"onSpeechResults" body:@{@"value": _finalTranscript ?: @""}];
            // [self stopRecognitionSession];
            NSLog(@"[BEFORE HITTING FINAL] isRecognitionStopped? ", _isStopped ? @"YES" : @"NO");
            NSLog(@"✅ Final Result: %@", transcript);
            // Delay stopping to allow result to propagate
            [self resetSilenceTimer];
            [self stopRecognitionSession];
          } else {
            NSLog(@"[BEFORE HITTING PARTIAL] isRecognitionStopped? %@", _isStopped ? @"YES" : @"NO");
            [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value": transcript}];
            [self resetSilenceTimer];
          }
        }
        
        if (error) {
          [self sendEventWithName:@"onSpeechError" body:@{@"message": error.localizedDescription}];
          [self stopRecognitionSession];
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

RCT_EXPORT_METHOD(fireTestEvent) {
  NSLog(@"🔥 fireTestEvent called");
  if (hasListeners) {
    [self sendEventWithName:@"onTestEvent" body:@{@"message": @"Hello from native!"}];
  } else {
    NSLog(@"❌ No listeners active. Skipping event.");
  }
}

RCT_EXPORT_METHOD(setRecognitionLanguage:(NSString *)languageTag
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  if (languageTag == nil || languageTag.length == 0) {
    reject(@"INVALID_LANGUAGE", @"languageTag is empty", nil);
    return;
  }
  
  BOOL supported = NO;
  for (NSLocale *loc in [SFSpeechRecognizer supportedLocales]) {
    NSString *tag = [[loc localeIdentifier] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([tag isEqualToString:languageTag]) {
      supported = YES;
      break;
    }
  }
  
  if (!supported) {
    reject(@"LANG_NOT_SUPPORTED",
           [NSString stringWithFormat:@"Language not supported: %@", languageTag],
           nil);
    return;
  }
  
  self.recognitionLanguage = languageTag;
  resolve(@(YES));
}

RCT_EXPORT_METHOD(getRecognitionLanguage:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  if (self.recognitionLanguage.length > 0) {
    resolve(self.recognitionLanguage);
    return;
  }
  
  NSString *current = [[[NSLocale currentLocale] localeIdentifier]
                       stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
  resolve(current);
}

RCT_EXPORT_METHOD(getSupportedLanguages:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  NSMutableArray *languages = [NSMutableArray array];
  
  for (NSLocale *locale in [SFSpeechRecognizer supportedLocales]) {
    NSString *identifier = [locale localeIdentifier];
    
    NSString *normalized =
    [identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    
    [languages addObject:normalized];
  }
  
  resolve(languages);
}
@end
