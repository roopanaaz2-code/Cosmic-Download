# Cosmic Download

Cosmic Download is a Flutter Android app for downloading supported public video and audio links, organizing them in the phone's media folders, and playing local files.

## Features

- Paste a supported public post URL or use **Share → Cosmic Download** from a social app. The app receives the link and lets you review it before starting.
- Use **Download this page** in Cosmic Browser to inspect the page currently open in the app.
- Prefer H.264/AVC video plus AAC audio in an MP4 container for wider compatibility with Android players. Choose a maximum resolution or extract audio as MP3. The selected codecs and resolutions depend on what the source provides.
- On a YouTube HTTP 403/SABR failure, update the bundled yt-dlp stable engine and retry once. A persistent 403 is shown with an explanation instead of being silently retried forever.
- Show progress, Android notifications, retry failed downloads, and cancel active downloads.
- Save completed media under `Movies/Cosmic Download` or `Music/Cosmic Download`, and play local video/audio.

## Build and release

GitHub Actions runs analysis and the regression tests, then builds separate release APKs for `arm64-v8a` and `armeabi-v7a`. Download the APK that matches the phone architecture. Most current Android phones use `arm64-v8a`; some older 32-bit phones use `armeabi-v7a`. The two smaller APKs replace the previous all-architecture APK.

A successful build on `main` publishes both APKs to a versioned GitHub Release. For a local build, run `flutter pub get`, then `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`.

## Important limitations

- No downloader can guarantee support for every social-media site or every post. Site behavior changes, and a site's privacy, sign-in, region, DRM, or anti-automation restrictions may prevent access.
- A YouTube 403 can persist even after updating yt-dlp. YouTube may require a short-lived proof-of-origin token, sign-in, or a format unavailable to the embedded engine. The app does not bypass private or protected access.
- H.264/AAC MP4 is a common Android-compatible profile, not a guarantee for every player or device. Compatibility still depends on the source's available format and the phone's codec/profile support. The app reports when no compatible source format is available rather than silently choosing an unrelated codec.
- Android sharesheets allow a user to share a post link to Cosmic Download. Android does not let this app insert its own download button inside Facebook, Instagram, YouTube, or other third-party apps. The app provides a download button in its own browser instead.
- Download only content you own or have permission to save, and follow the relevant service's terms and applicable law.
- The app requires Android API 24 or newer.

## Third-party components

Media extraction, merging, and MP3 extraction use the Flutter `extractor` package and its yt-dlp/FFmpeg-based Android engine. The release workflow keeps Apache Commons Compress classes from being altered by the shrinker because yt-dlp uses them to extract its bundled Python runtime.
