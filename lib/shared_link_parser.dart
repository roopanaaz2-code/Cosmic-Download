String? firstHttpUrl(String text) {
  final match = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(text);
  if (match == null) return null;
  final candidate = match.group(0)!.replaceFirst(RegExp(r'[),.;!?]+$'), '');
  final uri = Uri.tryParse(candidate);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
    return null;
  }
  return candidate;
}
