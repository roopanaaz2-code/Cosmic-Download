bool isYoutube403(String url, String error) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  final youtubeHost = host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
  final detail = error.toLowerCase();
  return youtubeHost && (detail.contains('403') || detail.contains('sabr'));
}
