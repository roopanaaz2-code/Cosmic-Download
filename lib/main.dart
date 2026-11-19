import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const bg = Color(0xFF050817);
const panel = Color(0xFF111A32);
const cyan = Color(0xFF55D9FF);
const violet = Color(0xFF9B78FF);

final notifications = FlutterLocalNotificationsPlugin();
const storageChannel = MethodChannel('cosmic_download/storage');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(android: android));
  final androidNotifications = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidNotifications?.requestNotificationsPermission();
  runApp(const CosmicApp());
}

class CosmicApp extends StatelessWidget {
  const CosmicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cosmic Download',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark),
      useMaterial3: true,
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    ),
    home: const HomePage(),
  );
}

class DownloadItem {
  DownloadItem(this.name, this.url, {this.quality = 'Original', this.audioOnly = false});
  final String name, url;
  final String quality;
  final bool audioOnly;
  final int notificationId = DateTime.now().microsecondsSinceEpoch.remainder(2000000000);
  double progress = 0;
  String status = 'Queued';
  String? path;
  String? savedLocation;
  String? error;
  CancelToken? cancelToken;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final urlController = TextEditingController();
  final browserAddressController = TextEditingController();
  late final WebViewController browserController;
  String browserPlatform = 'Web';
  bool browserLoading = false, converting = false;
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 25), receiveTimeout: const Duration(minutes: 0)));
  final items = <DownloadItem>[];
  final audio = AudioPlayer();
  bool sound = false, downloading = false, showGalaxy = false;
  String statusMessage = 'Ready for your next mission';
  int tab = 0;
  VideoPlayerController? video;
  String? playingName;

  @override
  void initState() {
    super.initState();
    browserController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() => browserLoading = true); },
        onPageFinished: (_) { if (mounted) setState(() => browserLoading = false); },
        onNavigationRequest: (request) {
          if (_isDirectMediaUrl(request.url)) {
            _startDownload(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  @override
  void dispose() {
    urlController.dispose();
    browserAddressController.dispose();
    audio.dispose();
    video?.dispose();
    super.dispose();
  }

  String fileNameFrom(String url) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final decoded = Uri.decodeComponent(last);
      if (decoded.contains('.') && decoded.length < 100) return decoded.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    } catch (_) {}
    return 'cosmic_download_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<String> _publishToDownloads(String sourcePath, String name) async {
    final lower = name.toLowerCase();
    final mime = lower.endsWith('.mp3') ? 'audio/mpeg'
        : lower.endsWith('.m4a') ? 'audio/mp4'
        : lower.endsWith('.webm') ? 'video/webm'
        : lower.endsWith('.mkv') ? 'video/x-matroska'
        : lower.endsWith('.mov') ? 'video/quicktime'
        : lower.endsWith('.mp4') ? 'video/mp4'
        : 'application/octet-stream';
    final location = await storageChannel.invokeMethod<String>('saveToDownloads', {
      'sourcePath': sourcePath, 'fileName': name, 'mimeType': mime,
    });
    if (location == null || location.isEmpty) {
      throw StateError('Android could not publish the file to Downloads.');
    }
    return location;
  }

  Future<void> startDownload() => _startDownload(urlController.text.trim());

  bool _isDirectMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return RegExp(r'\.(mp4|m4v|mov|webm|mkv|avi|mp3|m4a|aac|wav|ogg|flac)$').hasMatch(path);
  }

  Future<void> _startDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      if (mounted) setState(() => statusMessage = 'Enter a valid direct HTTP or HTTPS media link.');
      return;
    }
    String quality = 'Original';
    bool audioOnly = false;
    final choice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) {
        String selected = '720p';
        bool mp3 = false;
        return StatefulBuilder(builder: (context, refresh) => SafeArea(child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 18),
            const Text('CHOOSE DOWNLOAD FORMAT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: .8)),
            const SizedBox(height: 5),
            const Text('Choose the output size or extract audio as MP3.', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: ['Original','1080p','720p','480p','360p'].map((q) =>
              ChoiceChip(label: Text(q), selected: !mp3 && selected == q,
                onSelected: (_) => refresh(() { selected = q; mp3 = false; }))).toList(),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_rounded, color: cyan),
              title: const Text('MP3 audio only'),
              subtitle: const Text('Extract audio and save as an MP3 file'),
              trailing: Switch(value: mp3, activeColor: cyan, onChanged: (v) => refresh(() => mp3 = v)),
              onTap: () => refresh(() => mp3 = !mp3),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () => Navigator.pop(sheetContext, {'quality': selected, 'mp3': mp3}),
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.download_rounded), SizedBox(width: 9), Text('📥  DOWNLOAD', style: TextStyle(fontWeight: FontWeight.w900))],
              )),
            )),
            const SizedBox(height: 8),
            const Text('Resolution choices re-encode the downloaded source; they cannot create detail that is not in the original.', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        )));
      },
    );
    if (choice == null) return;
    quality = choice['quality'] as String;
    audioOnly = choice['mp3'] as bool;
    final originalName = fileNameFrom(url);
    final base = originalName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final outputName = audioOnly ? '$base.mp3' : (quality == 'Original' ? originalName : '$base-${quality}.mp4');
    final item = DownloadItem(outputName, url, quality: quality, audioOnly: audioOnly);
    if (mounted) setState(() { items.insert(0, item); downloading = true; showGalaxy = true; statusMessage = 'Preparing download…'; tab = 1; });
    if (sound) SystemSound.play(SystemSoundType.click);
    await notifications.show(item.notificationId, 'Cosmic Download', 'Download started: ${item.name}',
      const NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.low, priority: Priority.low, showProgress: true, maxProgress: 100, progress: 0)));
    await _download(item);
  }

  Future<void> searchInBrowser() async {
    final query = browserAddressController.text.trim();
    if (query.isEmpty) return;
    final direct = Uri.tryParse(query);
    if (direct != null && direct.hasScheme && direct.host.isNotEmpty) {
      await browserController.loadRequest(direct);
      return;
    }
    final encoded = Uri.encodeComponent(query);
    final String target;
    switch (browserPlatform) {
      case 'YouTube':
        target = 'https://www.youtube.com/results?search_query=$encoded';
        break;
      case 'TikTok':
        target = 'https://www.tiktok.com/search?q=$encoded';
        break;
      case 'Facebook':
        target = 'https://www.google.com/search?q=${Uri.encodeComponent('site:facebook.com $query')}';
        break;
      case 'Instagram':
        target = 'https://www.google.com/search?q=${Uri.encodeComponent('site:instagram.com $query')}';
        break;
      case 'X':
        target = 'https://x.com/search?q=$encoded';
        break;
      case 'Vimeo':
        target = 'https://vimeo.com/search?q=$encoded';
        break;
      default:
        target = 'https://www.google.com/search?q=$encoded';
    }
    await browserController.loadRequest(Uri.parse(target));
  }

  Future<void> convertToMp3() async {
    if (converting) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.video);
    final input = picked?.files.single.path;
    if (input == null) return;
    setState(() { converting = true; statusMessage = 'Converting audio…'; });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}/CosmicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final base = input.split(Platform.pathSeparator).last.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final output = '${folder.path}/$base.mp3';
      String quote(String value) => '"${value.replaceAll('"', r'\"')}"';
      final session = await FFmpegKit.execute('-y -i ${quote(input)} -vn -c:a libmp3lame -b:a 192k ${quote(output)}');
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code) && await File(output).exists()) {
        final item = DownloadItem('$base.mp3', 'local-conversion://$base');
        item.path = output;
        item.savedLocation = await _publishToDownloads(output, '$base.mp3');
        item.progress = 1; item.status = 'Completed';
        if (mounted) setState(() { items.insert(0, item); statusMessage = 'MP3 conversion completed'; tab = 1; });
        await notifications.show(item.notificationId, 'MP3 conversion completed', '$base.mp3 is ready.',
          const NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.high, priority: Priority.high)));
        if (sound) SystemSound.play(SystemSoundType.alert);
      } else {
        final logs = await session.getOutput() ?? 'Unsupported or protected audio stream.';
        if (mounted) setState(() => statusMessage = 'Conversion failed: ${logs.substring(0, (logs.length > 90 ? 90 : logs.length))}');
      }
    } catch (_) {
      if (mounted) setState(() => statusMessage = 'Could not convert this video to MP3.');
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  Future<void> _download(DownloadItem item) async {
    item.cancelToken = CancelToken();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/CosmicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final sourceName = fileNameFrom(item.url);
      final rawPath = '${folder.path}/source_${DateTime.now().microsecondsSinceEpoch}_$sourceName';
      item.status = 'Downloading';
      if (mounted) setState(() {});
      // Use one complete response for reliable media integrity across signed CDN URLs.
      await _downloadSingle(item, rawPath);
      final source = File(rawPath);
      if (!await source.exists() || await source.length() == 0) throw StateError('Empty download');
      final finalPath = '${folder.path}/${item.name}';
      if (item.audioOnly || item.quality != 'Original') {
        item.status = item.audioOnly ? 'Converting to MP3' : 'Optimizing video';
        if (mounted) setState(() {});
        final escapedInput = rawPath.replaceAll("'", "'\\''");
        final escapedOutput = finalPath.replaceAll("'", "'\\''");
        final command = item.audioOnly
          ? "-y -i '$escapedInput' -vn -c:a libmp3lame -b:a 192k '$escapedOutput'"
          : "-y -i '$escapedInput' -vf \"scale=-2:min(${int.parse(item.quality.replaceAll('p',''))}\\,ih)\" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -profile:v baseline -level 3.1 -c:a aac -b:a 128k -movflags +faststart '$escapedOutput'";
        final session = await FFmpegKit.execute(command);
        final code = await session.getReturnCode();
        if (!ReturnCode.isSuccess(code) || !await File(finalPath).exists() || await File(finalPath).length() == 0) {
          final logs = await session.getOutput() ?? 'Media conversion failed';
          throw StateError(logs.substring(0, math.min(logs.length, 240)));
        }
        await source.delete();
      } else {
        if (await File(finalPath).exists()) await File(finalPath).delete();
        await source.rename(finalPath);
      }
      item.path = finalPath;
      item.savedLocation = await _publishToDownloads(finalPath, item.name);
      item.progress = 1; item.status = 'Completed';
      if (sound) SystemSound.play(SystemSoundType.alert);
      await notifications.show(item.notificationId, 'Mission completed!', '${item.name} is ready in Downloads/Cosmic Download.',
        const NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.high, priority: Priority.high)));
      if (mounted) setState(() => statusMessage = 'Download ready • tap Play in Downloads');
    } on DioException catch (e) {
      item.status = CancelToken.isCancel(e) ? 'Cancelled' : 'Failed';
      item.error = item.status == 'Failed'
        ? (e.response?.statusCode != null ? 'HTTP ${e.response!.statusCode}: ${e.message ?? 'Request rejected'}' : (e.message ?? e.type.name))
        : null;
      if (mounted) setState(() => statusMessage = item.status == 'Failed' ? 'Download failed: ${item.error}' : 'Download cancelled.');
    } catch (e) {
      item.status = 'Failed';
      item.error = e.toString().replaceFirst('Bad state: ', '');
      if (mounted) setState(() => statusMessage = 'Download failed: ${item.error}');
    } finally {
      if (mounted) setState(() { downloading = items.any((e) => e.status == 'Downloading' || e.status == 'Converting to MP3' || e.status == 'Optimizing video'); if (!downloading) showGalaxy = false; });
    }
  }

  Future<void> _downloadSingle(DownloadItem item, String path) async {
    final response = await dio.download(item.url, path, cancelToken: item.cancelToken,
      options: Options(followRedirects: true, headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36'}),
      onReceiveProgress: (received, total) {
        if (total > 0) item.progress = (received / total).clamp(0.0, 1.0).toDouble();
        if (mounted) setState(() {});
        notifications.show(item.notificationId, 'Cosmic Download', '${(item.progress * 100).round()}% • ${item.name}',
          NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.low, priority: Priority.low, showProgress: true, maxProgress: 100, progress: (item.progress * 100).round())));
      });
    if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
      throw StateError('The media server returned HTTP ${response.statusCode ?? 'unknown'}.');
    }
    final downloaded = File(path);
    if (!await downloaded.exists() || await downloaded.length() < 12) {
      throw StateError('The server returned an empty or incomplete file.');
    }
    final mime = response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    if (mime.contains('text/html') || mime.contains('application/json') || mime.contains('text/plain')) {
      throw StateError('This link returned a webpage or error response, not a media file. Paste a direct video/audio file URL.');
    }
    final raf = await downloaded.open();
    final header = await raf.read(16);
    await raf.close();
    final ascii = String.fromCharCodes(header);
    final isMp4 = header.length >= 8 && ascii.substring(4, 8) == 'ftyp';
    final isWebm = header.length >= 4 && header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3;
    final isRiff = ascii.startsWith('RIFF');
    final isOgg = ascii.startsWith('OggS');
    final isFlac = ascii.startsWith('fLaC');
    final isId3 = ascii.startsWith('ID3');
    final isMp3Frame = header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0;
    final isAac = header.length >= 2 && header[0] == 0xFF && (header[1] & 0xF6) == 0xF0;
    final isMedia = isMp4 || isWebm || isRiff || isOgg || isFlac || isId3 || isMp3Frame || isAac;
    final genericMime = mime.isEmpty || mime.contains('octet-stream') || mime.contains('binary');
    if (!isMedia && genericMime) {
      throw StateError('The response is not a recognized audio/video file. Use a direct media-file link.');
    }
  }

  Future<void> retry(DownloadItem item) async { item.progress = 0; item.status = 'Queued'; setState(() {}); await _download(item); }
  Future<void> cancel(DownloadItem item) async { item.cancelToken?.cancel('User cancelled'); }

  Future<void> chooseVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result?.files.single.path != null) await playVideo(result!.files.single.path!);
  }
  Future<void> playVideo(String path) async {
    try {
      await video?.dispose();
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() { video = controller; playingName = path.split(Platform.pathSeparator).last; tab = 2; });
    } catch (error) {
      if (mounted) {
        setState(() => statusMessage = 'This file codec is not supported by the device player.');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this video. Try downloading as 720p or 480p for compatibility.')));
      }
    }
  }

  Future<void> playDownloaded(DownloadItem item) async {
    final path = item.path;
    if (path == null || !await File(path).exists()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The downloaded file is not available on this device.')));
      return;
    }
    if (item.audioOnly || item.name.toLowerCase().endsWith('.mp3') || item.name.toLowerCase().endsWith('.m4a')) {
      try {
        await audio.setFilePath(path);
        await audio.play();
        if (mounted) setState(() { playingName = item.name; tab = 3; });
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This audio file could not be opened.')));
      }
    } else {
      await playVideo(path);
    }
  }

  Future<void> playAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result?.files.single.path == null) return;
    await audio.setFilePath(result!.files.single.path!);
    await audio.play();
    if (mounted) setState(() { playingName = result.files.single.name; tab = 3; });
  }
  Future<void> openBrowserSearch() async {
    browserAddressController.text = urlController.text.trim();
    setState(() => tab = 4);
    if (browserAddressController.text.isNotEmpty) await searchInBrowser();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _downloads(), _videoPage(), _musicPage(), _browserPage()];
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: const CustomPaint(painter: GalaxyPainter()),
        )),
        Positioned.fill(child: Container(
          decoration: BoxDecoration(color: bg.withValues(alpha: .72)),
        )),
        SafeArea(child: IndexedStack(index: tab, children: pages)),
        if (showGalaxy && items.any((e) => e.status == 'Downloading'))
          Positioned.fill(child: GalaxyMissionOverlay(items: items, onClose: () => setState(() => showGalaxy = false))),
      ]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0B1124), indicatorColor: cyan.withValues(alpha: .16),
        selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.download_rounded), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.movie_rounded), label: 'Video'),
          NavigationDestination(icon: Icon(Icons.headphones_rounded), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.language_rounded), label: 'Browser'),
        ],
      ),
    );
  }

  Widget _header() => Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [cyan, violet]), borderRadius: BorderRadius.circular(14)),
      child: const Icon(Icons.rocket_launch_rounded, color: bg)),
    const SizedBox(width: 12),
    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('COSMIC DOWNLOAD', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 17)),
      Text('Beyond downloads. Into the galaxy.', style: TextStyle(color: Colors.white54, fontSize: 11)),
    ])),
    IconButton(onPressed: () => setState(() => sound = !sound), icon: Icon(sound ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: cyan), tooltip: 'Cosmic sound effects'),
  ]);

  Widget _home() => ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
    _header(), const SizedBox(height: 22),
    Container(height: 205, decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF182B57), Color(0xFF28164B), Color(0xFF090D20)])),
      child: Stack(children: [
        const Positioned.fill(child: CustomPaint(painter: GalaxyPainter())),
        Positioned(left: 20, top: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('YOUR MEDIA,\nAT WARP SPEED', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.15)),
          const SizedBox(height: 8), Text(statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        const Positioned(right: 20, bottom: 16, child: Icon(Icons.public_rounded, size: 78, color: Color(0x9955D9FF))),
      ])),
    const SizedBox(height: 22),
    const Text('DOWNLOAD FROM A LINK', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
    const SizedBox(height: 10),
    TextField(controller: urlController, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'Paste a direct video or audio URL', prefixIcon: Icon(Icons.link_rounded),)),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: FilledButton.icon(onPressed: startDownload, icon: const Icon(Icons.rocket_launch_rounded), label: const Text('DOWNLOAD'))),
      const SizedBox(width: 8),
      OutlinedButton(onPressed: openBrowserSearch, child: const Icon(Icons.search_rounded)),
    ]),
    const SizedBox(height: 22),
    const Text('YOUR COSMIC TOOLKIT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
    const SizedBox(height: 10),
    GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.55, children: [
      _tile(Icons.download_for_offline_rounded, 'Download manager', 'Track your missions', () => setState(() => tab = 1)),
      _tile(Icons.video_library_rounded, 'Video player', 'Play local videos', chooseVideo),
      _tile(Icons.library_music_rounded, 'Music player', 'Play local audio', playAudio),
      _tile(Icons.graphic_eq_rounded, 'MP3 converter', converting ? 'Converting…' : 'Extract audio from video', convertToMp3),
    ]),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Real downloads', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
      SizedBox(height: 5),
      Text('Files are saved to your phone in Downloads/Cosmic Download. Turbo mode verifies every byte-range part and automatically retries with a normal download if the server does not support ranges correctly. Only direct, accessible media-file URLs work; protected social posts and DRM streams cannot be downloaded.', style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
    ])),
  ]);

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback action) => InkWell(onTap: action, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, color: cyan, size: 23), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
  ])));

  Widget _browserPage() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: _header()),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
      Expanded(child: DropdownButtonFormField<String>(
        value: browserPlatform,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.travel_explore), isDense: true),
        items: const ['Web', 'YouTube', 'TikTok', 'Facebook', 'Instagram', 'X', 'Vimeo'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) { if (v != null) setState(() => browserPlatform = v); },
      )),
      const SizedBox(width: 8),
      Expanded(flex: 2, child: TextField(
        controller: browserAddressController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => searchInBrowser(),
        decoration: const InputDecoration(hintText: 'Search or enter URL', isDense: true),
      )),
      IconButton(onPressed: searchInBrowser, icon: const Icon(Icons.search, color: cyan)),
    ])),
    if (browserLoading) const LinearProgressIndicator(minHeight: 2, color: cyan),
    Expanded(child: WebViewWidget(controller: browserController)),
    const Padding(padding: EdgeInsets.all(8), child: Text('Search results open in the selected site. Direct media-file links can be downloaded; protected posts may not be available.', style: TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center)),
  ]);

  Widget _downloads() => ListView(padding: const EdgeInsets.all(18), children: [
    _header(), const SizedBox(height: 20), const Text('DOWNLOAD MISSIONS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    if (items.isEmpty) const Padding(padding: EdgeInsets.only(top: 70), child: Center(child: Column(children: [Icon(Icons.rocket_outlined, size: 54, color: violet), SizedBox(height: 12), Text('No missions yet'), Text('Paste a direct media link on Home to begin.', style: TextStyle(color: Colors.white54, fontSize: 12))]))),
    ...items.map((item) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.insert_drive_file_rounded, color: cyan), const SizedBox(width: 9), Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))), Text(item.status, style: TextStyle(color: item.status == 'Completed' ? Colors.greenAccent : cyan, fontSize: 11))]),
      const SizedBox(height: 10), LinearProgressIndicator(value: item.progress, backgroundColor: Colors.white12, color: cyan, minHeight: 6, borderRadius: BorderRadius.circular(9)),
      const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${(item.progress * 100).round()}%', style: const TextStyle(color: Colors.white60, fontSize: 11)), if (item.status == 'Downloading') TextButton(onPressed: () => cancel(item), child: const Text('Cancel')) else if (item.status == 'Failed') TextButton(onPressed: () => retry(item), child: const Text('Retry')) else if (item.status == 'Completed') const Text('Saved', style: TextStyle(color: Colors.greenAccent, fontSize: 11))]),
      if (item.savedLocation != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Phone storage: ${item.savedLocation}', style: const TextStyle(color: Colors.greenAccent, fontSize: 10))),
      if (item.status == 'Failed') Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.error ?? 'Check the link and try again.', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
      if (item.status == 'Completed') Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: () => playDownloaded(item),
        icon: const Icon(Icons.play_circle_fill_rounded, color: cyan),
        label: Text(item.audioOnly ? 'Play audio' : 'Play video'),
      )),
    ]))),
  ]);

  Widget _videoPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _header(), const SizedBox(height: 24), const Text('VIDEO PLAYER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
    const SizedBox(height: 16),
    if (video != null && video!.value.isInitialized) AspectRatio(aspectRatio: video!.value.aspectRatio, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: VideoPlayer(video!))) else Container(height: 190, decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)), child: const Center(child: Icon(Icons.movie_creation_outlined, size: 64, color: violet))),
    const SizedBox(height: 12), Text(playingName ?? 'Choose a video stored on your device', style: const TextStyle(color: Colors.white70)),
    if (video != null && video!.value.isInitialized) VideoProgressIndicator(video!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: cyan)) ,
    const SizedBox(height: 10), FilledButton.icon(onPressed: chooseVideo, icon: const Icon(Icons.folder_open), label: const Text('Choose video')),
    if (video != null) IconButton(onPressed: () => setState(() => video!.value.isPlaying ? video!.pause() : video!.play()), icon: Icon(video!.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 46, color: cyan)),
    const Text('Playback supports formats and resolutions that the Android device can decode.', style: TextStyle(color: Colors.white54, fontSize: 12)),
  ]);

  Widget _musicPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _header(), const SizedBox(height: 24), const Text('MUSIC PLAYER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
    const SizedBox(height: 18), Container(height: 210, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF21154B), Color(0xFF0D2946)])), child: const Center(child: Icon(Icons.album_rounded, size: 120, color: cyan))),
    const SizedBox(height: 16), Text(playingName ?? 'Choose audio from your device', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 12), StreamBuilder<Duration?>(stream: audio.durationStream, builder: (context, snap) => StreamBuilder<Duration>(stream: audio.positionStream, builder: (context, pos) {
      final duration = snap.data ?? Duration.zero, position = pos.data ?? Duration.zero;
      final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
      return Column(children: [Slider(value: position.inMilliseconds.toDouble().clamp(0.0, max).toDouble(), max: max, onChanged: (v) => audio.seek(Duration(milliseconds: v.round())), activeColor: cyan), Text('${_fmt(position)} / ${_fmt(duration)}', style: const TextStyle(color: Colors.white54, fontSize: 11))]);
    })),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: () => audio.seek(Duration.zero), icon: const Icon(Icons.replay_10)),
      StreamBuilder<PlayerState>(stream: audio.playerStateStream, builder: (context, snap) => IconButton(iconSize: 58, color: cyan, onPressed: () => snap.data?.playing == true ? audio.pause() : audio.play(), icon: Icon(snap.data?.playing == true ? Icons.pause_circle_filled : Icons.play_circle_fill))),
      IconButton(onPressed: () => audio.seek(audio.position + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10)),
    ]),
    FilledButton.icon(onPressed: playAudio, icon: const Icon(Icons.folder_open), label: const Text('Choose audio')),
  ]);

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class GalaxyPainter extends CustomPainter {
  const GalaxyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .76, size.height * .57);
    final glow = Paint()..shader = RadialGradient(colors: [cyan.withValues(alpha: .34), violet.withValues(alpha: .12), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: 115));
    canvas.drawCircle(center, 115, glow);
    final sun = Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF2B0), Color(0xFFFF9B53), Color(0x00FF784A)]).createShader(Rect.fromCircle(center: center, radius: 25));
    canvas.drawCircle(center, 25, sun);
    final orbit = Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawOval(Rect.fromCenter(center: center, width: 150, height: 65), orbit);
    canvas.drawOval(Rect.fromCenter(center: center, width: 195, height: 95), orbit);
    canvas.drawCircle(center + const Offset(74, -9), 7, Paint()..color = cyan);
    canvas.drawCircle(center + const Offset(-93, 16), 4, Paint()..color = violet);
    final random = math.Random(804);
    for (int i = 0; i < 70; i++) {
      final p = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      canvas.drawCircle(p, random.nextDouble() * 1.4 + .3, Paint()..color = Colors.white.withValues(alpha: random.nextDouble() * .75 + .15));
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class GalaxyMissionOverlay extends StatefulWidget {
  const GalaxyMissionOverlay({super.key, required this.items, required this.onClose});
  final List<DownloadItem> items;
  final VoidCallback onClose;
  @override
  State<GalaxyMissionOverlay> createState() => _GalaxyMissionOverlayState();
}

class _GalaxyMissionOverlayState extends State<GalaxyMissionOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(seconds: 32))..repeat();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final active = widget.items.where((e) => e.status == 'Downloading').toList();
    final item = active.isNotEmpty ? active.first : widget.items.first;
    return Material(
      color: const Color(0xFF030611),
      child: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(animation: controller, builder: (_, __) => CustomPaint(painter: FullGalaxyPainter(controller.value)))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          Row(children: [
            const Icon(Icons.rocket_launch_rounded, color: cyan),
            const SizedBox(width: 10),
            const Expanded(child: Text('COSMIC MISSION', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900))),
            IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
          ]),
          const Spacer(),
          AnimatedBuilder(animation: controller, builder: (_, __) => Transform.rotate(
          angle: controller.value * math.pi * 2,
          child: const Icon(Icons.public_rounded, color: cyan, size: 92),
        )),
          const SizedBox(height: 24),
          const Text('TRAVELLING THROUGH THE GALAXY', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, letterSpacing: 2, color: Colors.white70)),
          const SizedBox(height: 14),
          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          Text('${(item.progress * 100).round()}%', style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900, color: cyan)),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: item.progress, minHeight: 9, backgroundColor: Colors.white12, color: cyan)),
          const SizedBox(height: 14),
          Text(item.status == 'Downloading' ? 'Download engines are working…' : item.status, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          const Text('Keep Cosmic Download open for the live galaxy view.', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]))),
      ]),
    );
  }
}

class FullGalaxyPainter extends CustomPainter {
  FullGalaxyPainter(this.phase);
  final double phase;

  void _planet(Canvas canvas, Offset center, double rx, double ry, double angle,
      Color color, double radius, {double tilt = 0}) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    final orbit = Paint()..color = color.withValues(alpha: .25)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), orbit);
    final p = Offset(math.cos(angle) * rx, math.sin(angle) * ry);
    final glow = Paint()..shader = RadialGradient(
      colors: [color.withValues(alpha: .55), Colors.transparent],
    ).createShader(Rect.fromCircle(center: p, radius: radius * 2.8));
    canvas.drawCircle(p, radius * 2.8, glow);
    final body = Paint()..shader = RadialGradient(
      center: const Alignment(-.35, -.4),
      colors: [Colors.white.withValues(alpha: .8), color, color.withValues(alpha: .45)],
    ).createShader(Rect.fromCircle(center: p, radius: radius));
    canvas.drawCircle(p, radius, body);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF101D45), Color(0xFF080A20), Color(0xFF02040D)],
    ).createShader(rect));
    final center = Offset(size.width * .5, size.height * .46);
    final nebula = Paint()..shader = RadialGradient(
      colors: [violet.withValues(alpha: .28), cyan.withValues(alpha: .09), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center, radius: size.width * .78));
    canvas.drawCircle(center, size.width * .78, nebula);

    final random = math.Random(804);
    for (var i = 0; i < 260; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final twinkle = .15 + .8 * ((math.sin(phase * math.pi * 4 + i * 1.7) + 1) / 2);
      final drift = (phase * (8 + (i % 15)) * (i.isEven ? 1 : -1)) % size.width;
      canvas.drawCircle(Offset((x + drift) % size.width, y), random.nextDouble() * 1.55 + .25,
        Paint()..color = Colors.white.withValues(alpha: twinkle));
    }

    for (var arm = 0; arm < 3; arm++) {
      for (var i = 0; i < 38; i++) {
        final t = i / 38;
        final angle = phase * math.pi * 2 + arm * math.pi * 2 / 3 + t * 4.8;
        final radius = 24 + t * size.width * .39;
        final p = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius * .43);
        canvas.drawCircle(p, 1.0 + (1 - t) * 1.5,
          Paint()..color = (arm.isEven ? cyan : violet).withValues(alpha: .12 + .45 * (1 - t)));
      }
    }

    final sunGlow = Paint()..shader = RadialGradient(
      colors: [const Color(0xFFFFF6C5).withValues(alpha: .65), const Color(0xFFFFA24C).withValues(alpha: .22), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center, radius: 74));
    canvas.drawCircle(center, 74, sunGlow);
    final sun = Paint()..shader = const RadialGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFFFE7A0), Color(0xFFFF8B43)],
    ).createShader(Rect.fromCircle(center: center, radius: 28));
    canvas.drawCircle(center, 28 + math.sin(phase * math.pi * 4) * 1.8, sun);

    _planet(canvas, center, size.width * .32, size.width * .105, phase * math.pi * 2, cyan, 10, tilt: -.2);
    _planet(canvas, center, size.width * .43, size.width * .16, -phase * math.pi * 1.35 + 1, violet, 7, tilt: .18);
    _planet(canvas, center, size.width * .24, size.width * .075, phase * math.pi * 3.2 + 2, const Color(0xFFFFB45F), 5, tilt: .32);
    _planet(canvas, center, size.width * .49, size.width * .19, phase * math.pi * .8 + 3, const Color(0xFF75E0B2), 4, tilt: -.28);

    for (var i = 0; i < 2; i++) {
      final t = (phase * (i == 0 ? 1.15 : .72) + i * .48) % 1.0;
      final x = t * (size.width + 160) - 80;
      final y = size.height * (i == 0 ? .18 : .72) + math.sin(t * math.pi * 2) * 35;
      final tail = Paint()..shader = LinearGradient(
        colors: [Colors.transparent, (i == 0 ? cyan : violet).withValues(alpha: .8)],
      ).createShader(Rect.fromLTWH(x - 85, y - 2, 85, 4));
      canvas.drawLine(Offset(x - 85, y), Offset(x, y), tail..strokeWidth = 2.2);
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant FullGalaxyPainter oldDelegate) => oldDelegate.phase != phase;
}
