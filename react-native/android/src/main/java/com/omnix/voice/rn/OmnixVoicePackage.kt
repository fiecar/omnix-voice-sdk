package com.omnix.voice.rn

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

/**
 * New Architecture package for React Native 0.87.
 * Legacy createNativeModules is not used; 0.87 runs the New Architecture only.
 */
class OmnixVoicePackage : BaseReactPackage() {
    override fun getModule(
        name: String,
        reactContext: ReactApplicationContext,
    ): NativeModule? =
        if (name == NativeOmnixVoiceSpec.NAME) {
            OmnixVoiceModule(reactContext)
        } else {
            null
        }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider =
        ReactModuleInfoProvider {
            mapOf(
                NativeOmnixVoiceSpec.NAME to
                    ReactModuleInfo(
                        NativeOmnixVoiceSpec.NAME,
                        OmnixVoiceModule::class.java.name,
                        false,
                        false,
                        false,
                        true,
                    ),
            )
        }
}
