import { NativeModules, NativeEventEmitter } from 'react-native';

const { SpeechRecognition } = NativeModules;

const emitter = new NativeEventEmitter(SpeechRecognition);

export function startListening(): Promise<string> {
  return SpeechRecognition.startListening();
}

export function stopListening(): Promise<string> {
  return SpeechRecognition.stopListening();
}

export function destroy(): Promise<string> {
  return SpeechRecognition.destroy();
}

export function getRecognitionLanguage(): Promise<string> {
  return SpeechRecognition.getRecognitionLanguage();
}

export function setRecognitionLanguage(languageTag: string): Promise<boolean> {
  return SpeechRecognition.setRecognitionLanguage(languageTag);
}

export function isRecognitionAvailable(): Promise<boolean> {
  return SpeechRecognition.isRecognitionAvailable();
}

export function getSupportedLanguages(): Promise<string[]> {
  return SpeechRecognition.getSupportedLanguages();
}

export function addEventListener(
  eventName: string,
  handler: (event: any) => void
) {
  return emitter.addListener(eventName, handler);
}

export function removeAllListeners(eventName: string) {
  emitter.removeAllListeners(eventName);
}

export const speechRecogntionEvents = {
  START: 'onSpeechStart',
  BEGIN: 'onSpeechBegin',
  END: 'onSpeechEnd',
  ERROR: 'onSpeechError',
  RESULTS: 'onSpeechResults',
  PARTIAL_RESULTS: 'onSpeechPartialResults',
  VOLUME_CHANGED: 'onSpeechVolumeChanged',
  AUDIO_BUFFER: 'onSpeechAudioBuffer',
  EVENT: 'onSpeechEvent',
};
