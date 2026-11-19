import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

const bg = Color(0xFF050817);
const panel = Color(0xFF111A32);
const cyan = Color(0xFF55D9FF);
const violet = Color(0xFF9B78FF);

final notifications = FlutterLocalNotificationsPlugin();

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
  DownloadItem(this.name, this.url);
  final String name, url;
  final int notificationId = DateTime.now().microsecondsSinceEpoch.remainder(2000000000);
  double progress = 0;
  String status = 'Queued';
  String? path;
  CancelToken? cancelToken;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final urlController = TextEditingController();
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 25), receiveTimeout: const Duration(minutes: 0)));
  final items = <DownloadItem>[];
  final audio = AudioPlayer();
  bool sound = false, turbo = true, downloading = false, showGalaxy = false;
  String statusMessage = 'Ready for your next mission';
  int tab = 0;
  VideoPlayerController? video;
  String? playingName;

  @override
  void dispose() {
    urlController.dispose();
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

  Future<void> startDownload() async {
    final url = urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => statusMessage = 'Enter a valid direct HTTP or HTTPS media link.');
      return;
    }
    final item = DownloadItem(fileNameFrom(url), url);
    setState(() { items.insert(0, item); downloading = true; showGalaxy = true; statusMessage = 'Preparing launch sequence…'; tab = 1; });
    if (sound) SystemSound.play(SystemSoundType.click);
    await notifications.show(item.notificationId, 'Cosmic Download', 'Download started: ${item.name}',
      const NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.low, priority: Priority.low, showProgress: true, maxProgress: 100, progress: 0)));
    await _download(item);
  }

  Future<void> _download(DownloadItem item) async {
    item.cancelToken = CancelToken();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/CosmicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final safeName = item.name.replaceAll(RegExp(r'[/\\]'), '_');
      final path = '${folder.path}/$safeName';
      item.status = 'Downloading';
      setState(() {});
      await dio.download(item.url, path, cancelToken: item.cancelToken,
        options: Options(followRedirects: true, headers: {'User-Agent': 'CosmicDownload/1.0'}),
        onReceiveProgress: (received, total) {
          if (total > 0) item.progress = received / total;
          setState(() {});
          notifications.show(item.notificationId, 'Cosmic Download', '${(item.progress * 100).round()}% • ${item.name}',
            NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.low, priority: Priority.low, showProgress: true, maxProgress: 100, progress: (item.progress * 100).round())));
        });
      item.path = path; item.progress = 1; item.status = 'Completed';
      if (sound) SystemSound.play(SystemSoundType.alert);
      await notifications.show(1001, 'Mission completed!', '${item.name} is ready in CosmicDownloads.',
        const NotificationDetails(android: AndroidNotificationDetails('cosmic_downloads', 'Downloads', channelDescription: 'Download progress and completion', importance: Importance.high, priority: Priority.high)));
      if (mounted) setState(() => statusMessage = 'Mission completed • file saved');
    } on DioException catch (e) {
      item.status = CancelToken.isCancel(e) ? 'Cancelled' : 'Failed';
      if (mounted) setState(() => statusMessage = item.status == 'Failed' ? 'Download failed. Check the link or try again.' : 'Download cancelled.');
    } catch (_) {
      item.status = 'Failed';
      if (mounted) setState(() => statusMessage = 'Could not save this media file.');
    } finally {
      if (mounted) setState(() { downloading = items.any((e) => e.status == 'Downloading'); if (!downloading) showGalaxy = false; });
    }
  }

  Future<void> retry(DownloadItem item) async { item.progress = 0; item.status = 'Queued'; setState(() {}); await _download(item); }
  Future<void> cancel(DownloadItem item) async { item.cancelToken?.cancel('User cancelled'); }

  Future<void> chooseVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result?.files.single.path != null) await playVideo(result!.files.single.path!);
  }
  Future<void> playVideo(String path) async {
    await video?.dispose();
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    await controller.play();
    if (mounted) setState(() { video = controller; playingName = path.split('/').last; tab = 2; });
  }
  Future<void> playAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result?.files.single.path == null) return;
    await audio.setFilePath(result!.files.single.path!);
    await audio.play();
    if (mounted) setState(() { playingName = result.files.single.name; tab = 3; });
  }
  Future<void> openBrowserSearch() async {
    final q = Uri.encodeComponent(urlController.text.trim());
    final uri = Uri.parse('https://www.google.com/search?q=$q');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _downloads(), _videoPage(), _musicPage()];
    return Scaffold(
      body: Stack(children: [
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
      _tile(Icons.graphic_eq_rounded, 'MP3 converter', 'Coming in next engine update', () => _message('Audio extraction engine is scheduled for the next release.')),
    ]),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Speed note', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
      SizedBox(height: 5),
      Text('Cosmic Download uses direct HTTP downloads. Actual speed depends on your connection and the source server. Parallel acceleration and supported-site integrations will be added after compatibility testing.', style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
    ])),
  ]);

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback action) => InkWell(onTap: action, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, color: cyan, size: 23), const SizedBox(height: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
  ])));

  Widget _downloads() => ListView(padding: const EdgeInsets.all(18), children: [
    _header(), const SizedBox(height: 20), const Text('DOWNLOAD MISSIONS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    if (items.isEmpty) const Padding(padding: EdgeInsets.only(top: 70), child: Center(child: Column(children: [Icon(Icons.rocket_outlined, size: 54, color: violet), SizedBox(height: 12), Text('No missions yet'), Text('Paste a direct media link on Home to begin.', style: TextStyle(color: Colors.white54, fontSize: 12))]))),
    ...items.map((item) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.insert_drive_file_rounded, color: cyan), const SizedBox(width: 9), Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))), Text(item.status, style: TextStyle(color: item.status == 'Completed' ? Colors.greenAccent : cyan, fontSize: 11))]),
      const SizedBox(height: 10), LinearProgressIndicator(value: item.progress, backgroundColor: Colors.white12, color: cyan, minHeight: 6, borderRadius: BorderRadius.circular(9)),
      const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${(item.progress * 100).round()}%', style: const TextStyle(color: Colors.white60, fontSize: 11)), if (item.status == 'Downloading') TextButton(onPressed: () => cancel(item), child: const Text('Cancel')) else if (item.status == 'Failed') TextButton(onPressed: () => retry(item), child: const Text('Retry')) else if (item.status == 'Completed') const Text('Saved', style: TextStyle(color: Colors.greenAccent, fontSize: 11))]),
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
  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
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
          const Icon(Icons.public_rounded, color: cyan, size: 92),
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
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .46);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF101D45), Color(0xFF080A20), Color(0xFF02040D)]).createShader(rect));
    final nebula = Paint()..shader = RadialGradient(colors: [violet.withValues(alpha: .22), cyan.withValues(alpha: .07), Colors.transparent]).createShader(Rect.fromCircle(center: center, radius: size.width * .72));
    canvas.drawCircle(center, size.width * .72, nebula);
    final starRandom = math.Random(804);
    for (var i = 0; i < 180; i++) {
      final p = Offset(starRandom.nextDouble() * size.width, starRandom.nextDouble() * size.height);
      final twinkle = .25 + .65 * ((math.sin(phase * math.pi * 2 + i) + 1) / 2);
      canvas.drawCircle(p, starRandom.nextDouble() * 1.5 + .35, Paint()..color = Colors.white.withValues(alpha: twinkle));
    }
    final sunPaint = Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF6C5), Color(0xFFFFA24C), Color(0x00FF743A)]).createShader(Rect.fromCircle(center: center, radius: 48));
    canvas.drawCircle(center, 48, sunPaint);
    final orbitPaint = Paint()..color = cyan.withValues(alpha: .3)..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * math.pi * 2);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size.width * .66, height: size.width * .22), orbitPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size.width * .88, height: size.width * .34), orbitPaint);
    canvas.drawCircle(Offset(size.width * .33, 0), 12, Paint()..color = cyan);
    canvas.drawCircle(Offset(-size.width * .43, 0), 8, Paint()..color = violet);
    canvas.restore();
    canvas.drawCircle(Offset(size.width * .19, size.height * .22), 19, Paint()..color = const Color(0xFFB7C8E8));
    canvas.drawCircle(Offset(size.width * .82, size.height * .76), 11, Paint()..color = const Color(0xFFDAA45B));
  }
  @override
  bool shouldRepaint(covariant FullGalaxyPainter oldDelegate) => oldDelegate.phase != phase;
}
