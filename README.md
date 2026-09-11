# TikTokAudioMix — Codespaces build

This is the Theos/Logos source project for the TikTok v46.8.0 LiveContainer/TweakLoader tweak.

The project:
- targets `com.zhiliaoapp.musically`
- adds `MixWithOthers` to TikTok AVAudioSession categories
- hooks the known TikTok player mute/volume selectors
- provides a floating MUTE/UNMUTE button

## Build from an iPhone

Use GitHub Actions:
1. Open the repository's **Actions** tab.
2. Select **Build TikTokAudioMix tweak**.
3. Tap **Run workflow**.
4. Open the completed run.
5. Download the `TikTokAudioMix-build` artifact.

The artifact contains the build output from `dist/`.

## Important

This is source code for a tweak, not a pre-signed iOS app. The resulting dylib must be loaded by a compatible tweak loader such as LiveContainer's TweakLoader.
