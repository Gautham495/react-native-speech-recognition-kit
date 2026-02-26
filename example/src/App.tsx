import {
  StyleSheet,
  ActivityIndicator,
  Text,
  View,
  TouchableOpacity,
  ScrollView,
} from 'react-native';

import { useEffect, useState, useRef } from 'react';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  useDerivedValue,
  interpolate,
  Easing,
  SharedValue,
} from 'react-native-reanimated';

import {
  addEventListener,
  startListening,
  stopListening,
  destroy,
  speechRecogntionEvents,
  getRecognitionLanguage,
  getSupportedLanguages,
  setRecognitionLanguage,
  isRecognitionAvailable,
} from 'react-native-speech-recognition-kit';

const WAVE_COUNT = 7;
const WAVE_COLORS = [
  '#FF6B6B',
  '#4ECDC4',
  '#45B7D1',
  '#96CEB4',
  '#FFEAA7',
  '#FF6B6B',
  '#4ECDC4',
];

// Animated wave bar component - reacts directly to voice level
const WaveBar = ({
  index,
  isActive,
  voiceLevelShared,
}: {
  index: number;
  isActive: boolean;
  voiceLevelShared: SharedValue<number>;
}) => {
  const isActiveShared = useSharedValue(0);

  // Random offset for each bar to create variation
  const randomOffset = useRef(Math.random() * 0.4 + 0.6).current; // 0.6 to 1.0

  useEffect(() => {
    isActiveShared.value = withTiming(isActive ? 1 : 0, { duration: 200 });
  }, [isActive]);

  // Derive height from voice level
  const animatedHeight = useDerivedValue(() => {
    const minHeight = 15;
    const maxHeight = 70;

    // Voice level comes in as -60 to -30 (or higher when loud)
    // Normalize to 0-1 range: -60 = 0, -20 = 1
    const normalizedLevel = interpolate(
      voiceLevelShared.value,
      [-60, -20],
      [0, 1],
      'clamp'
    );

    // Apply random offset for variation between bars
    const variation = normalizedLevel * randomOffset;

    // Calculate target height
    const targetHeight = minHeight + variation * (maxHeight - minHeight);

    // Only animate when active
    const finalHeight =
      isActiveShared.value * (targetHeight - minHeight) + minHeight;

    return finalHeight;
  });

  const animatedStyle = useAnimatedStyle(() => {
    return {
      height: withSpring(animatedHeight.value, {
        damping: 8,
        stiffness: 150,
        mass: 0.5,
      }),
      opacity: interpolate(isActiveShared.value, [0, 1], [0.3, 1]),
    };
  });

  return (
    <Animated.View
      style={[
        styles.waveBar,
        { backgroundColor: WAVE_COLORS[index % WAVE_COLORS.length] },
        animatedStyle,
      ]}
    />
  );
};

// Pulsing circle behind mic button
const PulsingCircle = ({ isActive }: { isActive: boolean }) => {
  const scale = useSharedValue(1);
  const opacity = useSharedValue(0);

  useEffect(() => {
    if (isActive) {
      // Continuous pulsing animation
      const pulse = () => {
        scale.value = withTiming(
          1.4,
          { duration: 800, easing: Easing.out(Easing.ease) },
          () => {
            scale.value = withTiming(1, {
              duration: 800,
              easing: Easing.in(Easing.ease),
            });
          }
        );
        opacity.value = withTiming(0.25, { duration: 800 }, () => {
          opacity.value = withTiming(0, { duration: 800 });
        });
      };
      pulse();
      const interval = setInterval(pulse, 1600);
      return () => clearInterval(interval);
    } else {
      scale.value = withTiming(1, { duration: 300 });
      opacity.value = withTiming(0, { duration: 300 });
    }
  }, [isActive]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
    opacity: opacity.value,
  }));

  return <Animated.View style={[styles.pulsingCircle, animatedStyle]} />;
};

// Volume meter component
const VolumeMeter = ({
  voiceLevelShared,
}: {
  voiceLevelShared: SharedValue<number>;
}) => {
  const animatedStyle = useAnimatedStyle(() => {
    // Normalize dB level (-60 to -20) to percentage (0 to 100)
    const normalized = interpolate(
      voiceLevelShared.value,
      [-60, -20],
      [0, 100],
      'clamp'
    );

    return {
      width: `${normalized}%`,
      backgroundColor:
        voiceLevelShared.value > -30
          ? '#FF6B6B' // Loud - red
          : voiceLevelShared.value > -45
            ? '#4ECDC4' // Medium - teal
            : '#96CEB4', // Quiet - green
    };
  });

  return (
    <View style={styles.volumeMeterContainer}>
      <View style={styles.volumeMeterTrack}>
        <Animated.View style={[styles.volumeMeterFill, animatedStyle]} />
      </View>
      <VolumeText voiceLevelShared={voiceLevelShared} />
    </View>
  );
};

// Separate component for volume text to avoid re-renders
const VolumeText = ({
  voiceLevelShared,
}: {
  voiceLevelShared: SharedValue<number>;
}) => {
  const [displayLevel, setDisplayLevel] = useState(-60);

  useEffect(() => {
    // Update text periodically to avoid too many re-renders
    const interval = setInterval(() => {
      setDisplayLevel(voiceLevelShared.value);
    }, 100);
    return () => clearInterval(interval);
  }, []);

  return <Text style={styles.volumeText}>{displayLevel.toFixed(1)} dB</Text>;
};

// Status badge component
const StatusBadge = ({
  label,
  value,
  color,
}: {
  label: string;
  value: string;
  color: string;
}) => (
  <View style={[styles.statusBadge, { borderColor: color }]}>
    <Text style={styles.statusLabel}>{label}</Text>
    <Text style={[styles.statusValue, { color }]}>{value}</Text>
  </View>
);

const App = () => {
  const [text, setText] = useState<string>('');
  const [partialText, setPartialText] = useState<string>('');
  const [recognizing, setRecognizing] = useState<boolean>(false);
  const [speechStarted, setSpeechStarted] = useState<boolean>(false);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Shared value for voice level - this drives the wave animations
  const voiceLevelShared = useSharedValue(-60);

  // Feature showcase states
  const [currentLanguage, setCurrentLanguage] = useState<string>('');
  const [isAvailable, setIsAvailable] = useState<boolean>(false);
  const [supportedLanguages, setSupportedLanguages] = useState<string[]>([]);
  const [showLanguages, setShowLanguages] = useState<boolean>(false);

  // Initialize and check availability
  useEffect(() => {
    const init = async () => {
      try {
        const available = await isRecognitionAvailable();
        setIsAvailable(available);

        const lang = await getRecognitionLanguage();
        setCurrentLanguage(lang);

        const languages = await getSupportedLanguages();
        setSupportedLanguages(languages.slice(0, 10)); // Show first 10
      } catch (e) {
        console.log('Init error:', e);
      }
    };
    init();
  }, []);

  useEffect(() => {
    // Results - final transcription
    const resultsListener = addEventListener(
      speechRecogntionEvents.RESULTS,
      (event) => {
        console.log('📝 Final Result:', event);
        setText(event.value || '');
        setPartialText('');
      }
    );

    // Partial results - live transcription
    const partialListener = addEventListener(
      speechRecogntionEvents.PARTIAL_RESULTS,
      (event) => {
        console.log('✏️ Partial:', event.value);
        setPartialText(event.value || '');
      }
    );

    // Speech recognition ready
    const startListener = addEventListener(speechRecogntionEvents.START, () => {
      console.log('🎤 Recognition started');
      setRecognizing(true);
      setError(null);
    });

    // User started speaking
    const beginListener = addEventListener(speechRecogntionEvents.BEGIN, () => {
      console.log('🗣️ Speech detected');
      setSpeechStarted(true);
    });

    // Recognition ended
    const endListener = addEventListener(speechRecogntionEvents.END, () => {
      console.log('🔇 Recognition ended');
      setRecognizing(false);
      setSpeechStarted(false);
      voiceLevelShared.value = withTiming(-60, { duration: 300 });
    });

    // Volume changes - update shared value directly
    const volumeListener = addEventListener(
      speechRecogntionEvents.VOLUME_CHANGED,
      (event) => {
        // Update shared value directly - no state update needed
        voiceLevelShared.value = event.value ?? -60;
      }
    );

    // Errors
    const errorListener = addEventListener(
      speechRecogntionEvents.ERROR,
      (event) => {
        console.log('❌ Error:', event);
        setError(event.message || 'Recognition error');
        setRecognizing(false);
        setSpeechStarted(false);
      }
    );

    return () => {
      destroy();
      resultsListener.remove();
      partialListener.remove();
      startListener.remove();
      beginListener.remove();
      endListener.remove();
      volumeListener.remove();
      errorListener.remove();
    };
  }, []);

  const handleToggleListening = async () => {
    try {
      if (recognizing) {
        await stopListening();
      } else {
        setLoading(true);
        setText('');
        setPartialText('');
        setError(null);
        await startListening();
        setLoading(false);
      }
    } catch (e: any) {
      setLoading(false);
      setError(e.message || 'Failed to start');
    }
  };

  const handleLanguageChange = async (lang: string) => {
    try {
      await setRecognitionLanguage(lang);
      setCurrentLanguage(lang);
      setShowLanguages(false);
    } catch (e) {
      console.log('Language change error:', e);
    }
  };

  const displayText = partialText || text;

  return (
    <View style={styles.container}>
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>🎤 Speech Recognition</Text>
          <Text style={styles.subtitle}>React Native Kit Demo</Text>
        </View>

        {/* Status Badges */}
        <View style={styles.statusRow}>
          <StatusBadge
            label="Available"
            value={isAvailable ? 'Yes' : 'No'}
            color={isAvailable ? '#4ECDC4' : '#FF6B6B'}
          />
          <StatusBadge
            label="Status"
            value={
              recognizing ? (speechStarted ? 'Listening' : 'Ready') : 'Idle'
            }
            color={recognizing ? '#4ECDC4' : '#888'}
          />
          <StatusBadge
            label="Language"
            value={currentLanguage.split('-')[0]?.toUpperCase() || '—'}
            color="#45B7D1"
          />
        </View>

        {/* Audio Visualizer */}
        <View style={styles.visualizerContainer}>
          <View style={styles.waveContainer}>
            {Array.from({ length: WAVE_COUNT }).map((_, index) => (
              <WaveBar
                key={index}
                index={index}
                isActive={recognizing}
                voiceLevelShared={voiceLevelShared}
              />
            ))}
          </View>

          {recognizing && <VolumeMeter voiceLevelShared={voiceLevelShared} />}
        </View>

        {/* Main Button */}
        <View style={styles.buttonContainer}>
          <PulsingCircle isActive={recognizing} />
          <TouchableOpacity
            onPress={handleToggleListening}
            disabled={loading}
            style={[
              styles.mainButton,
              recognizing && styles.mainButtonActive,
              loading && styles.mainButtonLoading,
            ]}
            activeOpacity={0.8}
          >
            {loading ? (
              <ActivityIndicator size="large" color="#FFF" />
            ) : (
              <Text style={styles.mainButtonIcon}>
                {recognizing ? '⏹️' : '🎙️'}
              </Text>
            )}
          </TouchableOpacity>
          <Text style={styles.buttonLabel}>
            {loading
              ? 'Starting...'
              : recognizing
                ? 'Tap to Stop'
                : 'Tap to Speak'}
          </Text>
        </View>

        {/* Transcription Box */}
        <View style={styles.transcriptionContainer}>
          <Text style={styles.transcriptionLabel}>
            {partialText ? '✏️ Listening...' : '📝 Transcription'}
          </Text>
          <View style={styles.transcriptionBox}>
            {displayText ? (
              <Text
                style={[
                  styles.transcriptionText,
                  partialText && styles.partialText,
                ]}
              >
                {displayText}
              </Text>
            ) : (
              <Text style={styles.placeholderText}>
                {recognizing
                  ? 'Start speaking...'
                  : 'Tap the microphone to begin'}
              </Text>
            )}
          </View>
        </View>

        {/* Error Display */}
        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>⚠️ {error}</Text>
          </View>
        )}

        {/* Language Selector */}
        <TouchableOpacity
          style={styles.languageSelector}
          onPress={() => setShowLanguages(!showLanguages)}
        >
          <Text style={styles.languageSelectorText}>
            🌐 Language: {currentLanguage}
          </Text>
          <Text style={styles.chevron}>{showLanguages ? '▲' : '▼'}</Text>
        </TouchableOpacity>

        {showLanguages && (
          <View style={styles.languageList}>
            {supportedLanguages.map((lang) => (
              <TouchableOpacity
                key={lang}
                style={[
                  styles.languageItem,
                  lang === currentLanguage && styles.languageItemActive,
                ]}
                onPress={() => handleLanguageChange(lang)}
              >
                <Text
                  style={[
                    styles.languageItemText,
                    lang === currentLanguage && styles.languageItemTextActive,
                  ]}
                >
                  {lang}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        )}

        {/* Features List */}
        <View style={styles.featuresContainer}>
          <Text style={styles.featuresTitle}>✨ Features</Text>
          <View style={styles.featuresList}>
            <Text style={styles.featureItem}>✅ Real-time transcription</Text>
            <Text style={styles.featureItem}>✅ Voice level detection</Text>
            <Text style={styles.featureItem}>✅ Multi-language support</Text>
            <Text style={styles.featureItem}>✅ Partial results</Text>
            <Text style={styles.featureItem}>✅ Works on iOS & Android</Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
};

export default App;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F0F1A',
    paddingTop: 50,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  header: {
    alignItems: 'center',
    marginBottom: 24,
    marginTop: 10,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#FFF',
  },
  subtitle: {
    fontSize: 14,
    color: '#888',
    marginTop: 4,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 12,
    marginBottom: 24,
  },
  statusBadge: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  statusLabel: {
    fontSize: 10,
    color: '#888',
    textAlign: 'center',
  },
  statusValue: {
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
    marginTop: 2,
  },
  visualizerContainer: {
    alignItems: 'center',
    marginBottom: 24,
    height: 120,
    justifyContent: 'center',
  },
  waveContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    height: 80,
  },
  waveBar: {
    width: 10,
    borderRadius: 5,
    minHeight: 15,
  },
  volumeMeterContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 16,
    gap: 10,
  },
  volumeMeterTrack: {
    width: 150,
    height: 8,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 4,
    overflow: 'hidden',
  },
  volumeMeterFill: {
    height: '100%',
    borderRadius: 4,
  },
  volumeText: {
    fontSize: 12,
    color: '#888',
    width: 65,
    fontVariant: ['tabular-nums'],
  },
  buttonContainer: {
    alignItems: 'center',
    marginBottom: 32,
  },
  pulsingCircle: {
    position: 'absolute',
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: '#4ECDC4',
  },
  mainButton: {
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: '#4ECDC4',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#4ECDC4',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 12,
    elevation: 8,
  },
  mainButtonActive: {
    backgroundColor: '#FF6B6B',
    shadowColor: '#FF6B6B',
  },
  mainButtonLoading: {
    backgroundColor: '#888',
    shadowColor: '#888',
  },
  mainButtonIcon: {
    fontSize: 40,
  },
  buttonLabel: {
    marginTop: 12,
    fontSize: 14,
    color: '#888',
  },
  transcriptionContainer: {
    marginBottom: 20,
  },
  transcriptionLabel: {
    fontSize: 14,
    color: '#888',
    marginBottom: 8,
  },
  transcriptionBox: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    padding: 16,
    minHeight: 100,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  transcriptionText: {
    fontSize: 18,
    color: '#FFF',
    lineHeight: 26,
  },
  partialText: {
    color: '#4ECDC4',
    fontStyle: 'italic',
  },
  placeholderText: {
    fontSize: 16,
    color: '#555',
    fontStyle: 'italic',
  },
  errorContainer: {
    backgroundColor: 'rgba(255,107,107,0.1)',
    borderRadius: 12,
    padding: 12,
    marginBottom: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,107,107,0.3)',
  },
  errorText: {
    color: '#FF6B6B',
    fontSize: 14,
  },
  languageSelector: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
  },
  languageSelectorText: {
    color: '#FFF',
    fontSize: 14,
  },
  chevron: {
    color: '#888',
    fontSize: 12,
  },
  languageList: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    padding: 8,
    marginBottom: 20,
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  languageItem: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  languageItemActive: {
    backgroundColor: '#4ECDC4',
  },
  languageItemText: {
    color: '#888',
    fontSize: 12,
  },
  languageItemTextActive: {
    color: '#FFF',
    fontWeight: '600',
  },
  featuresContainer: {
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderRadius: 16,
    padding: 16,
    marginTop: 8,
  },
  featuresTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#FFF',
    marginBottom: 12,
  },
  featuresList: {
    gap: 8,
  },
  featureItem: {
    fontSize: 14,
    color: '#888',
  },
});
