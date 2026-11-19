# Cosmic Download 🌌

A space-themed Android media utility built with Flutter.

## Current first-release foundation
- Cosmic-themed home screen and full-screen download mission view foundation.
- Direct HTTP/HTTPS media downloads with progress, cancellation and retry.
- Completion and progress notifications.
- Local video playback and local audio playback.
- Download files saved to the app's private documents folder under `CosmicDownloads`.

## Build
GitHub Actions builds a release APK on every push to `main` and on demand from the Actions tab.

To publish a GitHub Release, push a version tag such as `v1.0.0`.

## Important limitations
- The initial downloader accepts direct HTTP/HTTPS media-file URLs. A social-network post URL is not necessarily a downloadable media URL.
- 4K playback depends on the downloaded source file and device decoder.
- Download speed depends on the network and remote host. Parallel segment acceleration is not yet enabled in this foundation.
- Social-platform search/download integrations and video-to-MP3 extraction are not yet implemented. Only content you own or are authorized to download/convert should be used.
- Cosmic sound toggle is currently a UI preference; audio effects will be wired in a subsequent tested build.
- Android notification permission may need to be granted by the user on Android 13+.

This project is an actively developed foundation, not a claim that every planned feature is already complete.
