import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'web_video_thumbnail.dart';
import '../../api_config.dart';

class VideoThumbnail extends StatefulWidget {
  final String url;
  final String? title;
  final BoxFit fit;

  const VideoThumbnail({
    super.key,
    required this.url,
    this.title,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  String _normalizedUrl = '';
  vp.VideoPlayerController? _vpController;
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;

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
      _disposeControllers();
    }
  }

  void _disposeControllers() {
    _vpController?.pause();
    _vpController?.dispose();
    _vpController = null;

    _mkPlayer?.pause();
    _mkPlayer?.dispose();
    _mkPlayer = null;
    _mkController = null;

    _isPlayingInline = false;
    _isInitializing = false;
    _hasError = false;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  String _normalizeUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/uploads/')) {
      return '$baseUrl$url';
    }
    if (url.startsWith('uploads/')) {
      return '$baseUrl/$url';
    }
    return '$baseUrl/uploads/${Uri.encodeFull(url)}';
  }

  Future<void> _toggleInlinePlay() async {
    if (_normalizedUrl.isEmpty) return;

    if (!kIsWeb) {
      // ── Desktop (Linux / Windows) using media_kit ──
      if (_mkPlayer == null) {
        setState(() {
          _isInitializing = true;
          _hasError = false;
        });
        try {
          final player = mk.Player();
          final controller = mkv.VideoController(player);
          _mkPlayer = player;
          _mkController = controller;

          await player.open(mk.Media(_normalizedUrl));
          await player.setPlaylistMode(mk.PlaylistMode.loop);
          await player.play();

          if (mounted) {
            setState(() {
              _isInitializing = false;
              _isPlayingInline = true;
            });
          }
        } catch (e) {
          debugPrint("Desktop MediaKit error: $e");
          if (mounted) {
            setState(() {
              _isInitializing = false;
              _hasError = true;
            });
          }
        }
      } else {
        if (_isPlayingInline) {
          await _mkPlayer?.pause();
          if (mounted) setState(() => _isPlayingInline = false);
        } else {
          await _mkPlayer?.play();
          if (mounted) setState(() => _isPlayingInline = true);
        }
      }
    } else {
      // ── Web (Chrome) using video_player ──
      if (_vpController == null) {
        setState(() {
          _isInitializing = true;
          _hasError = false;
        });
        try {
          final controller = vp.VideoPlayerController.networkUrl(
            Uri.parse(_normalizedUrl),
          );
          _vpController = controller;
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
          debugPrint("Web VideoPlayer error: $e");
          if (mounted) {
            setState(() {
              _isInitializing = false;
              _hasError = true;
            });
          }
        }
      } else {
        if (_vpController!.value.isPlaying) {
          _vpController!.pause();
          setState(() {
            _isPlayingInline = false;
          });
        } else {
          _vpController!.play();
          setState(() {
            _isPlayingInline = true;
          });
        }
      }
    }
  }

  void _openFullScreen() {
    if (!kIsWeb) {
      _mkPlayer?.pause();
    } else {
      _vpController?.pause();
    }
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
      decoration: const BoxDecoration(color: Colors.black),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video layer (when initialized) or Static / Web Thumbnail ──
          if (!kIsWeb && _mkController != null && _isPlayingInline)
            ClipRect(
              child: SizedOverflowBox(
                size: Size.infinite,
                child: mkv.Video(
                  controller: _mkController!,
                  controls: mkv.NoVideoControls,
                  fill: Colors.black,
                ),
              ),
            )
          else if (kIsWeb && _vpController != null && _vpController!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: _vpController!.value.size.width > 0
                    ? _vpController!.value.size.width
                    : 100,
                height: _vpController!.value.size.height > 0
                    ? _vpController!.value.size.height
                    : 60,
                child: vp.VideoPlayer(_vpController!),
              ),
            )
          else if (kIsWeb && _normalizedUrl.isNotEmpty)
            WebVideoThumbnail(url: _normalizedUrl, fit: widget.fit)
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
                          _hasError
                              ? Icons.warning_amber_rounded
                              : (_isPlayingInline
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
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
  // Web controller
  vp.VideoPlayerController? _vpController;

  // Desktop media_kit controller
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;

  bool _initialized = false;
  bool _hasError = false;
  String _normalizedUrl = '';

  bool _isPlaying = true;
  bool _isMuted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;

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
      return '$baseUrl$url';
    }
    if (url.startsWith('uploads/')) {
      return '$baseUrl/$url';
    }
    return '$baseUrl/uploads/${Uri.encodeFull(url)}';
  }

  Future<void> _initializePlayer() async {
    if (!mounted || _normalizedUrl.isEmpty) return;
    setState(() {
      _initialized = false;
      _hasError = false;
    });

    if (!kIsWeb) {
      // ── Desktop (Linux / Windows) ──
      try {
        final player = mk.Player();
        final controller = mkv.VideoController(player);
        _mkPlayer = player;
        _mkController = controller;

        _posSub = player.stream.position.listen((pos) {
          if (mounted) setState(() => _position = pos);
        });
        _durSub = player.stream.duration.listen((dur) {
          if (mounted) setState(() => _duration = dur);
        });
        _playSub = player.stream.playing.listen((playing) {
          if (mounted) setState(() => _isPlaying = playing);
        });

        await player.open(mk.Media(_normalizedUrl));
        await player.setPlaylistMode(mk.PlaylistMode.loop);
        await player.play();

        if (mounted) {
          setState(() {
            _initialized = true;
            _isPlaying = true;
          });
        }
      } catch (e) {
        debugPrint("FullScreen Desktop MediaKit error: $e");
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      }
    } else {
      // ── Web (Chrome) ──
      try {
        final controller = vp.VideoPlayerController.networkUrl(
          Uri.parse(_normalizedUrl),
        );
        _vpController = controller;
        await controller.initialize();
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          controller.play();
          controller.setLooping(true);
        }
      } catch (e) {
        debugPrint("FullScreen Web VideoPlayer error: $e");
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      }
    }
  }

  @override
  void deactivate() {
    if (!kIsWeb) {
      _mkPlayer?.pause();
    } else {
      _vpController?.pause();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();

    _vpController?.pause();
    _vpController?.dispose();
    _vpController = null;

    _mkPlayer?.pause();
    _mkPlayer?.dispose();
    _mkPlayer = null;
    _mkController = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _initialized
                ? (!kIsWeb && _mkController != null
                    ? SizedBox.expand(
                        child: mkv.Video(
                          controller: _mkController!,
                          controls: mkv.NoVideoControls,
                          fill: Colors.black,
                        ),
                      )
                    : (_vpController != null
                        ? SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: _vpController!.value.size.width > 0
                                    ? _vpController!.value.size.width
                                    : 1920,
                                height: _vpController!.value.size.height > 0
                                    ? _vpController!.value.size.height
                                    : 1080,
                                child: vp.VideoPlayer(_vpController!),
                              ),
                            ),
                          )
                        : const SizedBox.shrink()))
                : _hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.movie_creation_rounded,
                        color: Colors.white70,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        onPressed: _initializePlayer,
                        child: const Text(
                          'Retry Playback',
                          style: TextStyle(color: Colors.white),
                        ),
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
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
          if (_initialized)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xC0000000),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        !kIsWeb
                            ? (_isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded)
                            : (_vpController != null && _vpController!.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () {
                        setState(() {
                          if (!kIsWeb) {
                            _mkPlayer?.playOrPause();
                          } else {
                            if (_vpController != null) {
                              if (_vpController!.value.isPlaying) {
                                _vpController!.pause();
                              } else {
                                _vpController!.play();
                              }
                            }
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: !kIsWeb
                            ? SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds.toDouble().clamp(
                                        0.0,
                                        _duration.inMilliseconds.toDouble() > 0
                                            ? _duration.inMilliseconds.toDouble()
                                            : 1.0,
                                      ),
                                  max: _duration.inMilliseconds.toDouble() > 0
                                      ? _duration.inMilliseconds.toDouble()
                                      : 1.0,
                                  onChanged: (val) {
                                    _mkPlayer?.seek(
                                      Duration(milliseconds: val.toInt()),
                                    );
                                  },
                                  activeColor: Colors.blueAccent,
                                  inactiveColor: Colors.white24,
                                ),
                              )
                            : (_vpController != null
                                ? vp.VideoProgressIndicator(
                                    _vpController!,
                                    allowScrubbing: true,
                                    colors: const vp.VideoProgressColors(
                                      playedColor: Colors.blueAccent,
                                      bufferedColor: Colors.white38,
                                      backgroundColor: Colors.white24,
                                    ),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 24),
                                  )
                                : const SizedBox.shrink()),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        !kIsWeb
                            ? (_isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded)
                            : (_vpController != null &&
                                    _vpController!.value.volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded),
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () {
                        setState(() {
                          if (!kIsWeb) {
                            _isMuted = !_isMuted;
                            _mkPlayer?.setVolume(_isMuted ? 0.0 : 100.0);
                          } else {
                            if (_vpController != null) {
                              if (_vpController!.value.volume == 0) {
                                _vpController!.setVolume(1.0);
                              } else {
                                _vpController!.setVolume(0.0);
                              }
                            }
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
