# Cosmic Download 🌌

A space-themed Android media downloader, browser, MP3 converter and offline player built with Flutter.

## Features in the current release
- Direct HTTP/HTTPS video and audio file downloads.
- Verified single-stream HTTP downloads to avoid corrupted or incomplete files from unreliable byte-range servers.
- Multiple simultaneous downloads, progress notifications, cancellation and retry.
- Full-screen animated galaxy download mission with stars, Sun, orbiting planets and optional sound cues.
- Built-in browser with search entry points for Web, YouTube, TikTok, Facebook, Instagram, X and Vimeo.
- Browser navigation can hand off direct media-file links to the download manager.
- Optional video resizing/transcoding to H.264/AAC MP4 for broader Android playback compatibility, plus MP3 extraction at 192 kbps.
- Local video player and offline music player.

## Build and release
GitHub Actions builds a release APK on pushes to `main` and uploads it as a workflow artifact. Successful main builds also publish a versioned GitHub Release.

## Important limitations
- Downloads work with direct media-file URLs and links that resolve to downloadable files. A social-network post URL is not necessarily a direct media file.
- Social search uses each service's available search page or web search indexing. It is not an unrestricted platform API.
- Protected, private, DRM-protected, or otherwise restricted streams are not bypassed. Respect each platform's terms and copyright permissions.
- Turbo acceleration requires server-side HTTP byte-range support. It cannot exceed the network or server's available bandwidth.
- The app downloads the source file as provided; 4K availability depends on the source URL. 4K playback depends on device decoding support.
- Downloaded videos are copied into Android's Movies/Cosmic Download media library; audio is copied into Music/Cosmic Download; other files go to Downloads/Cosmic Download. The app also keeps its working copy privately.
- Minimum Android version is API 24 (Android 7.0) due to the FFmpeg audio engine.

## Third-party components
Media conversion uses `ffmpeg_kit_flutter_new_full`; review its licensing and codec availability before redistribution. Review and ship the applicable FFmpeg and dependency notices when redistributing the app.
