#import <Foundation/Foundation.h>
#import <Speech/Speech.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>

@interface SpeechRecognition : RCTEventEmitter <RCTBridgeModule>

@property (nonatomic, strong) SFSpeechRecognizer *speechRecognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (nonatomic, strong) SFSpeechRecognitionTask *recognitionTask;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic) BOOL isListening;
@property (nonatomic, copy) NSString *recognitionLanguage;

@end
