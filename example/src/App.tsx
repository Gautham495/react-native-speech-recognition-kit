import {
  Platform,
  StyleSheet,
  ActivityIndicator,
  Image,
  Text,
  View,
  TextInput,
  Dimensions,
  TouchableOpacity,
} from 'react-native';

import { useEffect, useState } from 'react';

import {
  addEventListener,
  startListening,
  stopListening,
  destroy,
  speechRecogntionEvents,
} from 'react-native-speech-recognition-kit';

const App = () => {
  const [text, setText] = useState<string>('');

  const [recognizing, setRecognizing] = useState<boolean>(false);

  const [speechRecogntionLoader, setSpeechRecognitionLoader] =
    useState<boolean>(false);

  const onTextChange = (v: string) => {
    setText(v);
  };

  useEffect(() => {
    const resultsListener = addEventListener(
      speechRecogntionEvents.RESULTS,
      (event) => {
        setText(event.value);
      }
    );

    const speechPartialResultsSubscription = addEventListener(
      speechRecogntionEvents.PARTIAL_RESULTS,
      (event) => {
        setText(event.value || '');
      }
    );

    const startListener = addEventListener(speechRecogntionEvents.START, () =>
      setRecognizing(true)
    );

    const endListener = addEventListener(speechRecogntionEvents.END, () =>
      setRecognizing(false)
    );

    return () => {
      destroy();
      startListener.remove();
      resultsListener.remove();
      speechPartialResultsSubscription.remove();
      endListener.remove();
    };
  }, []);

  const handleSpeechStart = async () => {
    try {
      if (recognizing) {
        await stopListening();
      } else {
        setSpeechRecognitionLoader(true);
        await startListening();
        setSpeechRecognitionLoader(false);
      }
    } catch (error) {
      setSpeechRecognitionLoader(false);
    }
  };

  return (
    <View style={styles.mainContainer}>
      <View style={styles.inputContainer}>
        <TextInput
          multiline
          value={text}
          onChangeText={onTextChange}
          style={styles.textInput}
          placeholder={'Message...'}
        />

        <View>
          {speechRecogntionLoader ? (
            <ActivityIndicator
              size={'small'}
              color={'black'}
              style={styles.speechRecognitionContainer}
            />
          ) : (
            <TouchableOpacity
              onPress={handleSpeechStart}
              style={styles.speechRecognitionContainer}
            >
              <View
                style={{
                  justifyContent: 'center',
                  alignItems: 'center',
                  flexDirection: 'row',
                }}
              >
                {recognizing ? (
                  <Image
                    source={require('../../icons/stop.png')}
                    style={styles.speechRecognitionIcon}
                  />
                ) : (
                  <Image
                    source={require('../../icons/wave-form.png')}
                    style={styles.speechRecognitionIcon}
                  />
                )}
                <Text>{recognizing ? 'Stop' : 'Speak'}</Text>
              </View>
            </TouchableOpacity>
          )}
        </View>
      </View>
    </View>
  );
};

export default App;

const styles = StyleSheet.create({
  mainContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    height: Dimensions.get('screen').height,
    width: Dimensions.get('screen').width,
  },

  inputContainer: {
    justifyContent: 'center',
    flexDirection: 'row',
    alignItems: 'flex-end',
  },

  textInput: {
    borderWidth: 0.5,
    padding: 12,
    width: Dimensions.get('screen').width * 0.92,
    borderRadius: 30,
    borderColor: 'black',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 16,
    maxHeight: 120,
    backgroundColor: 'white',
    color: 'black',
    paddingRight: 65,
  },

  speechRecognitionContainer: {
    width: 45,
    height: 45,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: -65,
    marginBottom: Platform.OS === 'ios' ? 0 : 2,
  },

  speechRecognitionIcon: {
    width: 18,
    height: 18,
    marginTop: Platform.OS === 'android' ? 0 : 0,
    marginRight: 5,
  },
});
