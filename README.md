# Cosmic Download

Cosmic Download is a Flutter Android app for downloading and organizing supported public video and audio links, plus a local media player and MP3 converter.

## Features

- Extract supported public video pages and direct media-file links with the bundled `extractor` plugin, which uses yt-dlp on Android.
- Select an available video quality or extract audio as MP3. Options depend on each source.
- Show download progress, Android notifications, retry failed downloads, and cancel active extractor jobs.
- Save completed files to the phone’s Movies, Music, or Downloads area under `Cosmic Download`.
- Play local videos and audio, and convert a local video file to MP3.
- Search in the built-in browser and paste a supported page URL into the downloader.

## Build and release

GitHub Actions builds a release APK when changes are pushed to `main` and uploads it as an Actions artifact. A successful build on `main` also publishes a versioned GitHub Release with the APK attached. You can build locally with Flutter and Android build tools using `flutter pub get` followed by `flutter build apk --release`.

## Important limitations

- This is not a universal downloader. It works only when the bundled yt-dlp engine currently supports the site and can access that specific media URL. Site behavior changes, so a site that works today may stop working later.
- The app does not bypass DRM, private or sign-in-only access, paywalls, or other restrictions. Cookie-based authentication is not currently implemented.
- Download only content you own or have permission to save, and follow the relevant service’s terms and applicable law.
- Available formats and quality depend on the source. Some video/audio combinations need FFmpeg for merging or conversion.
- Android playback depends on the device’s codec support. The app requires Android API 24 or newer because of the FFmpeg package.

## Third-party components

Media extraction uses the Flutter `extractor` package and its yt-dlp-based Android engine. MP3 conversion uses `ffmpeg_kit_flutter_new_full`. Review their licenses and bundled native components, and include any required notices before redistributing the APK.
