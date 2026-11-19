# Cosmic Download 🌌

A space-themed Android media downloader, browser, MP3 converter and offline player built with Flutter.

## Features in the current release
- Direct HTTP/HTTPS video and audio file downloads.
- Turbo mode: up to four parallel byte-range segments when the source server advertises and correctly supports HTTP Range requests; automatically falls back to a normal download when Range is unavailable.
- Multiple simultaneous downloads, progress notifications, cancellation and retry.
- Full-screen animated galaxy download mission with stars, Sun, orbiting planets and optional sound cues.
- Built-in browser with search entry points for Web, YouTube, TikTok, Facebook, Instagram, X and Vimeo.
- Browser navigation can hand off direct media-file links to the download manager.
- Local video-to-MP3 conversion at 192 kbps using FFmpeg's audio build.
- Local video player and offline music player.

## Build and release
GitHub Actions builds a release APK on pushes to `main` and uploads it as a workflow artifact. Successful main builds also publish a versioned GitHub Release.

## Important limitations
- Downloads work with direct media-file URLs and links that resolve to downloadable files. A social-network post URL is not necessarily a direct media file.
- Social search uses each service's available search page or web search indexing. It is not an unrestricted platform API.
- Protected, private, DRM-protected, or otherwise restricted streams are not bypassed. Respect each platform's terms and copyright permissions.
- Turbo acceleration requires server-side HTTP byte-range support. It cannot exceed the network or server's available bandwidth.
- The app downloads the source file as provided; 4K availability depends on the source URL. 4K playback depends on device decoding support.
- MP3 conversion is for local video files the user is allowed to convert. Output is saved in the app's private `CosmicDownloads` folder.
- Minimum Android version is API 24 (Android 7.0) due to the FFmpeg audio engine.

## Third-party components
The MP3 conversion engine uses `ffmpeg_kit_flutter_new_audio`, the LGPL audio-only variant. Review and ship the applicable FFmpeg and dependency notices when redistributing the app.
