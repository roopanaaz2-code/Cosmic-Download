import 'dart:io';

const _mediaExtensions = <String>{
  '3g2',
  '3gp',
  'aac',
  'aiff',
  'alac',
  'asf',
  'avi',
  'f4v',
  'flac',
  'flv',
  'm4a',
  'm4v',
  'mka',
  'mkv',
  'mks',
  'mov',
  'mpg',
  'mpeg',
  'mp3',
  'mp4',
  'oga',
  'ogg',
  'ogv',
  'opus',
  'rm',
  'rmvb',
  'ts',
  'wav',
  'webm',
  'wmv',
  'vob',
};

/// Finds the completed media file produced from a yt-dlp output template.
///
/// The extractor plugin currently reports the unexpanded output template (for
/// example, `%(title)s.%(ext)s`) instead of the real filename. Callers should
/// give each request a unique [filePrefix], then locate the generated file by
/// that prefix instead of opening the plugin's template path literally.
Future<File?> findCompletedMediaFile(Directory directory, String filePrefix) async {
  if (filePrefix.isEmpty || !await directory.exists()) return null;

  final expectedStart = '$filePrefix-';
  File? newestFile;
  DateTime? newestModified;

  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;

    final path = entity.path;
    final separator = path.lastIndexOf(Platform.pathSeparator);
    final name = separator < 0 ? path : path.substring(separator + 1);
    if (!name.startsWith(expectedStart)) continue;

    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) continue;
    final extension = name.substring(dot + 1).toLowerCase();
    if (!_mediaExtensions.contains(extension)) continue;

    try {
      if (await entity.length() == 0) continue;
      final modified = await entity.lastModified();
      if (newestModified == null || modified.isAfter(newestModified)) {
        newestFile = entity;
        newestModified = modified;
      }
    } on FileSystemException {
      // A temporary file can disappear while yt-dlp performs post-processing.
      continue;
    }
  }

  return newestFile;
}
