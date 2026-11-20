String compatibleMp4FormatSelector(int? maxHeight) {
  final heightFilter = maxHeight == null ? '' : '[height<=$maxHeight]';
  return 'bestvideo$heightFilter[vcodec^=avc1][ext=mp4]+'
      'bestaudio[acodec^=mp4a][ext=m4a]/'
      'best$heightFilter[vcodec^=avc1][acodec^=mp4a][ext=mp4]';
}

String mediaFormatSelector({
  required bool audioOnly,
  required String quality,
  bool directMedia = false,
}) {
  if (audioOnly) return 'bestaudio/best';
  if (directMedia) return 'best';
  final maxHeight = quality == 'Most compatible MP4'
      ? null
      : int.tryParse(quality.replaceAll('p', ''));
  return compatibleMp4FormatSelector(maxHeight);
}
