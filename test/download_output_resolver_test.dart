import 'dart:io';

import 'package:cosmic_download/download_output_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findCompletedMediaFile', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cosmic-download-test-');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('finds the actual media file from an expanded yt-dlp template', () async {
      final expected = File('${directory.path}/cosmic_job-My video.mp4');
      await expected.writeAsBytes(List<int>.filled(32, 7));
      await File('${directory.path}/unrelated.mp4').writeAsBytes(List<int>.filled(32, 1));
      await File('${directory.path}/cosmic_job-My video.mp4.part')
          .writeAsBytes(List<int>.filled(32, 2));
      await File('${directory.path}/cosmic_job-My video.info.json')
          .writeAsString('{}');

      final result = await findCompletedMediaFile(directory, 'cosmic_job');

      expect(result?.path, expected.path);
    });

    test('returns null when only unrelated files or incomplete parts exist', () async {
      await File('${directory.path}/cosmic_other-video.mp4')
          .writeAsBytes(List<int>.filled(32, 1));
      await File('${directory.path}/cosmic_job-My video.mp4.part')
          .writeAsBytes(List<int>.filled(32, 2));
      await File('${directory.path}/cosmic_job-thumbnail.jpg')
          .writeAsBytes(List<int>.filled(32, 3));

      final result = await findCompletedMediaFile(directory, 'cosmic_job');

      expect(result, isNull);
    });

    test('finds audio files with the same job prefix', () async {
      final expected = File('${directory.path}/cosmic_audio-track.mp3');
      await expected.writeAsBytes(List<int>.filled(32, 7));

      final result = await findCompletedMediaFile(directory, 'cosmic_audio');

      expect(result?.path, expected.path);
    });
  });
}
