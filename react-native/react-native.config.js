/**
 * Autolinking for @omnix/voice-sdk (SDK-048).
 * The Android package extends BaseReactPackage; declare it explicitly.
 */
module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: 'import com.omnix.voice.rn.OmnixVoicePackage;',
        packageInstance: 'new OmnixVoicePackage()',
      },
    },
  },
};
