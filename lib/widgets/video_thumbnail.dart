import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'web_video_thumbnail.dart';

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
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _normalizedUrl = '';

  @override
  void initState() {
    super.initState();
    _normalizedUrl = _normalizeUrl(widget.url);
    if (!kIsWeb && _normalizedUrl.isNotEmpty) {
      _initializePlayer();
    }
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _normalizedUrl = _normalizeUrl(widget.url);
      if (!kIsWeb && _normalizedUrl.isNotEmpty) {
        _controller?.dispose();
        _initializePlayer();
      }
    }
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/uploads/')) {
      return 'https://display.sriher.com$url';
    }
    if (url.startsWith('uploads/')) {
      return 'https://display.sriher.com/$url';
    }
    return 'https://display.sriher.com/uploads/${Uri.encodeFull(url)}';
  }

  Future<void> _initializePlayer() async {
    if (!mounted || _normalizedUrl.isEmpty) return;
    setState(() {
      _initialized = false;
      _hasError = false;
    });
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(_normalizedUrl));
      _controller = controller;
      await controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      debugPrint("VideoThumbnail initialization error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _togglePlay() {
    if (_controller == null || !_initialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── WEB PLATFORM: render native HTML5 video thumbnail via WebVideoThumbnail ──
    if (kIsWeb && _normalizedUrl.isNotEmpty) {
      return GestureDetector(
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebVideoThumbnail(
              url: _normalizedUrl,
              fit: BoxFit.cover,
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black38, Colors.transparent, Colors.black45],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── NON-WEB / FALLBACK PLATFORM ──
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Container(color: const Color(0xFF0F172A)),
          if (_initialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
          if (!_initialized || _hasError)
            // Styled video thumbnail card — clean, professional, never displays error box
            Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 26,
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          widget.title ?? 'Video',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (_initialized && _controller != null && !_controller!.value.isPlaying)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
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
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 16,
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
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _normalizedUrl = '';

  @override
  void initState() {
    super.initState();
    _normalizedUrl = _normalizeUrl(widget.url);
    _initializePlayer();
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/uploads/')) {
      return 'https://display.sriher.com$url';
    }
    if (url.startsWith('uploads/')) {
      return 'https://display.sriher.com/$url';
    }
    return 'https://display.sriher.com/uploads/${Uri.encodeFull(url)}';
  }

  Future<void> _initializePlayer() async {
    if (!mounted || _normalizedUrl.isEmpty) return;
    setState(() {
      _initialized = false;
      _hasError = false;
    });
    try {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse(_normalizedUrl));
      _controller = controller;
      await controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
        });
        controller.play();
        controller.setLooping(true);
      }
    } catch (e) {
      debugPrint("FullScreenVideoPlayer initialization error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _initialized && _controller != null
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  )
                : _hasError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.movie_creation_rounded,
                              color: Colors.white70, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            widget.title,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                            onPressed: _initializePlayer,
                            child: const Text('Retry Playback',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(color: Colors.white),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
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
          if (_initialized && _controller != null)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
