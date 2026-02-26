module.exports = {
  presets: [
    ['module:@react-native/babel-preset', { disableDeepImportWarnings: true }],
  ],
  plugins: [
    'react-native-worklets/plugin',
  ],
};
