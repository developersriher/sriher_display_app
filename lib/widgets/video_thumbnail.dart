import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoThumbnail extends StatefulWidget {
  final String url;
  final String? title;

  const VideoThumbnail({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    try {
      final player = Player();
      final controller = VideoController(player);

      if (!kIsWeb && player.platform is NativePlayer) {
        (player.platform as dynamic).setProperty('hwdec', 'auto');
        (player.platform as dynamic).setProperty('cache', 'yes');
        (player.platform as dynamic).setProperty('demuxer-max-bytes', '10000000');
      }

      // Open media but keep paused so the first frame loads and displays
      player.open(Media(widget.url), play: false);

      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });

      setState(() {
        _player = player;
        _controller = controller;
        _initialized = true;
      });
    } catch (e) {
      debugPrint("VideoThumbnail initialization error: $e");
    }
  }

  void _togglePlay() {
    _player?.playOrPause();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Container(color: Colors.black),
          if (_initialized && _controller != null)
            SizedBox.expand(
              child: Video(
                controller: _controller!,
                controls: NoVideoControls,
                fit: BoxFit.cover,
                fill: Colors.black,
              ),
            ),
          if (!_initialized)
            Container(
              color: Colors.black54,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_initialized && !_isPlaying)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          if (_initialized && _isPlaying)
            Container(
              color: Colors.transparent,
              child: const Center(
                child: Icon(
                  Icons.pause_circle_filled,
                  color: Colors.white54,
                  size: 28,
                ),
              ),
            ),
          // Fullscreen button
          Positioned(
            bottom: 4,
            right: 4,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FullScreenVideoPlayer(
                      url: widget.url,
                      title: widget.title ?? 'Video Preview',
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  final String title;

  const FullScreenVideoPlayer({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    if (!kIsWeb && _player.platform is NativePlayer) {
      (_player.platform as dynamic).setProperty('hwdec', 'auto');
      (_player.platform as dynamic).setProperty('cache', 'yes');
      (_player.platform as dynamic).setProperty('demuxer-max-bytes', '10000000');
    }
    _player.open(Media(widget.url), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: SizedBox.expand(
              child: Video(
                controller: _controller,
                controls: AdaptiveVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Top bar with Back button and Title
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
