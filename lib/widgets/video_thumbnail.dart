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
  String _normalizedUrl = '';
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _isPlayingInline = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _normalizedUrl = _normalizeUrl(widget.url);
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _normalizedUrl = _normalizeUrl(widget.url);
      _disposeController();
    }
  }

  void _disposeController() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _isPlayingInline = false;
    _isInitializing = false;
    _hasError = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
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

  Future<void> _toggleInlinePlay() async {
    if (_normalizedUrl.isEmpty) return;

    if (_controller == null) {
      setState(() {
        _isInitializing = true;
        _hasError = false;
      });
      try {
        final controller =
            VideoPlayerController.networkUrl(Uri.parse(_normalizedUrl));
        _controller = controller;
        await controller.initialize();
        if (mounted) {
          controller.setLooping(true);
          controller.play();
          setState(() {
            _isInitializing = false;
            _isPlayingInline = true;
          });
        }
      } catch (e) {
        debugPrint("Inline VideoPlayer error: $e");
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _hasError = true;
          });
        }
      }
    } else {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        setState(() {
          _isPlayingInline = false;
        });
      } else {
        _controller!.play();
        setState(() {
          _isPlayingInline = true;
        });
      }
    }
  }

  void _openFullScreen() {
    _controller?.pause();
    setState(() {
      _isPlayingInline = false;
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenVideoPlayer(
          url: widget.url,
          title: widget.title ?? 'Video Preview',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video layer (when initialized) or Static / Web Thumbnail ──
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: _controller!.value.size.width > 0
                    ? _controller!.value.size.width
                    : 100,
                height: _controller!.value.size.height > 0
                    ? _controller!.value.size.height
                    : 60,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (kIsWeb && _normalizedUrl.isNotEmpty)
            WebVideoThumbnail(
              url: _normalizedUrl,
              fit: BoxFit.cover,
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Padding(
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
              ),
            ),

          // Gradient overlay when paused or initial
          if (!_isPlayingInline)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black38, Colors.transparent, Colors.black45],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

          // ── Center Play/Pause triangle button: INLINE PLAYBACK ONLY ──
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleInlinePlay,
                borderRadius: BorderRadius.circular(20),
                child: _isInitializing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlayingInline
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
              ),
            ),
          ),

          // ── Bottom Right Fullscreen icon: FULLSCREEN DISPLAY ONLY ──
          Positioned(
            bottom: 2,
            right: 2,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openFullScreen,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 14,
                  ),
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
  void deactivate() {
    _controller?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
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
