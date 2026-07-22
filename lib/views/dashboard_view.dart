import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_card.dart';
import '../widgets/searchable_dropdown.dart';
import '../widgets/web_compat_image.dart';
import '../api_config.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

String get _kApiUrl => '${getBaseUrl()}/Dashboardview';
const _kApiKey =
    '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';
const _kBaseUrl = 'https://display.sriher.com/uploads/';

/// Times New Roman is used as the font family for all dashboard text.
const String _kFont = 'Times New Roman';

// ─── Models ───────────────────────────────────────────────────────────────────

class _DashboardData {
  final int totalDevice;
  final int activeDevice;
  final int totTemp;
  final int totScheTemp;
  final int totLocation;
  final int activeLoc;
  final int imgFile;
  final int vidFile;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<Map<String, dynamic>> deviceList;
  final List<Map<String, dynamic>> tempList;
  final List<Map<String, dynamic>> locationList;
  final List<Map<String, dynamic>> overview;

  _DashboardData({
    required this.totalDevice,
    required this.activeDevice,
    required this.totTemp,
    required this.totScheTemp,
    required this.totLocation,
    required this.activeLoc,
    required this.imgFile,
    required this.vidFile,
    required this.imageUrls,
    required this.videoUrls,
    required this.deviceList,
    required this.tempList,
    required this.locationList,
    required this.overview,
  });

  factory _DashboardData.fromJson(Map<String, dynamic> json) {
    final imgs = (json['img'] as List? ?? [])
        .map((e) => '$_kBaseUrl${e['file_name']}')
        .toList();

    final vids = json['vid'] as List?;
    final vidUrls = (vids ?? [])
        .map((e) => '$_kBaseUrl${e['file_name']}')
        .toList();

    // 'vinci' = live-enabled videos (toggled ON via File Upload)
    if (json['vinci'] != null && (json['vinci'] as List).isNotEmpty) {
      vidUrls.addAll(
        (json['vinci'] as List).map((e) => '$_kBaseUrl${e['file_name']}'),
      );
    }

    // 'live' = another possible key the backend may use for live-status videos
    if (json['live'] != null && (json['live'] as List).isNotEmpty) {
      vidUrls.addAll(
        (json['live'] as List).map((e) => '$_kBaseUrl${e['file_name']}'),
      );
    }

    return _DashboardData(
      totalDevice: json['totaldevice'] ?? 0,
      activeDevice: json['active_device'] ?? 0,
      totTemp: json['tot_temp'] ?? 0,
      totScheTemp: json['tot_sche_temp'] ?? 0,
      totLocation: json['tot_location'] ?? 0,
      activeLoc: json['active_loc'] ?? 0,
      imgFile: json['img_file'] ?? 0,
      vidFile: json['vid_file'] ?? 0,
      imageUrls: imgs,
      videoUrls: vidUrls,
      deviceList: _maps(json['deviceList']),
      tempList: _maps(json['templist']),
      locationList: _maps(json['locationlist']),
      overview: _maps(json['overview']),
    );
  }

  static List<Map<String, dynamic>> _maps(dynamic raw) =>
      (raw as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<Animation<double>> _cardAnimations = [];

  _DashboardData? _data;
  bool _loading = true;
  String? _error;

  int _slideIndex = 0;
  Timer? _slideTimer;
  late final PageController _pageCtrl;

  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  bool _videoReady = false;
  String? _videoError;
  bool _isPlaying = true;
  double _volume = 0.0;
  bool _isMuted = true;
  bool _showControls = true;
  bool _showMenu = false;
  double _playbackSpeed = 1.0;
  Timer? _hideControlsTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPiP = false;
  bool _isFullScreen = false;

  String _selectedCategory = 'Devices';
  int _entriesPerPage = 10;
  int _currentPage = 1;
  int? _sortColumnIndex;
  bool _sortAscending = true;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  void _sortData(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String? _userName;
  String? _loginTime;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    for (int i = 0; i < 10; i++) {
      _cardAnimations.add(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            i * 0.1,
            (i * 0.1 + 0.4).clamp(0.0, 1.0),
            curve: Curves.easeOutQuart,
          ),
        ),
      );
    }

    _controller.forward();
    _pageCtrl = PageController(initialPage: 5000);
    _loadUserInfo();
    _fetchDashboard();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName');
      final rawTime = prefs.getString('loginTime');
      if (rawTime != null) {
        try {
          final dt = DateTime.parse(rawTime);
          _loginTime =
              "${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        } catch (_) {
          _loginTime = rawTime;
        }
      }
    });
  }

  Future<void> _fetchDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse(_kApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': _kApiKey}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Server did not respond. Please check your connection.',
            ),
          );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['status'] == 'Success') {
          final d = _DashboardData.fromJson(body['data']);
          setState(() {
            _data = d;
            _loading = false;
          });
          _startSlideshow(d.imageUrls.length);
          _initVideo(d.videoUrls);
          return;
        }
      }
      setState(() {
        _loading = false;
        _error = 'Failed to load dashboard data';
      });
    } catch (ex) {
      setState(() {
        _loading = false;
        _error = ex.toString();
      });
    }
  }

  void _startSlideshow(int count) {
    _slideTimer?.cancel();
    if (count == 0) return;
    _slideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_pageCtrl.hasClients) {
        _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutQuart,
        );
      }
    });
  }

  void _initVideo(List<String> urls) {
    if (urls.isEmpty) return;
    try {
      final playlist = Playlist(urls.map((u) => Media(u)).toList());
      _player.open(playlist, play: true);
      _player.setPlaylistMode(PlaylistMode.loop);
      _player.setVolume(0.0);

      // Wait for actual playback before showing the Video widget.
      _player.stream.playing.listen((playing) {
        if (playing && mounted && !_videoReady) {
          setState(() => _videoReady = true);
        }
        if (mounted) setState(() => _isPlaying = playing);
      });
      _player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
    } catch (err) {
      setState(() => _videoError = err.toString());
    }
  }

  void _togglePiP() {
    setState(() {
      _isPiP = !_isPiP;
      if (_isPiP) {
        _isFullScreen = false;
        _showMenu = false;
      }
    });
  }

  void _toggleFullScreen() {
    if (!_isFullScreen) {
      setState(() {
        _isFullScreen = true;
        _isPiP = false;
        _showMenu = false;
      });
      // Push a full-screen overlay route that covers EVERYTHING (including drawer)
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, _, __) => _FullScreenVideoPage(
            videoController: _videoController,
            player: _player,
            isPlaying: _isPlaying,
            onClose: () {
              Navigator.of(context).pop();
              setState(() => _isFullScreen = false);
            },
            onPlayPause: () {
              _player.playOrPause();
              setState(() => _isPlaying = !_isPlaying);
            },
          ),
        ),
      );
    } else {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isFullScreen = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _slideTimer?.cancel();
    _hideControlsTimer?.cancel();
    _pageCtrl.dispose();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();

    final d = _data!;
    // Wrap the entire dashboard in a DefaultTextStyle so that every Text
    // widget inherits Times New Roman without explicit per-widget overrides.
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: _kFont),
      child: _buildDashboardContent(d),
    );
  }

  Widget _buildDashboardContent(_DashboardData d) {
    return Stack(
      children: [
        SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeHeader(),
                const SizedBox(height: 24),
                _buildMetricsGrid(d),
                const SizedBox(height: 32),
                _buildMediaSection(d),
                const SizedBox(height: 32),
                _buildRegistrySection(d),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
        // Fullscreen is now handled via Navigator push (covers entire screen)
        if (_isPiP) _buildPiPOverlay(),
      ],
    );
  }

  Widget _buildWelcomeHeader() {
    final hour = DateTime.now().hour;
    String greeting = "Welcome back";
    if (hour < 12)
      greeting = "Good morning";
    else if (hour < 17)
      greeting = "Good afternoon";
    else
      greeting = "Good evening";

    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.05),
          end: Offset.zero,
        ).animate(_controller),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      return Text(
                        "$greeting, ${_userName ?? 'User'}",
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: isMobile ? 18 : 28,
                          fontWeight: FontWeight.normal,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "Login Time • ${_loginTime ?? 'Just now'}",
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Floating Refresh Button
            IconButton.filled(
              onPressed: _fetchDashboard,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              hoverColor: Colors.blue.withOpacity(0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 3),
          SizedBox(height: 24),
          Text(
            'Syncing your dashboard...',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchDashboard,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(_DashboardData d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildCompactMetric(
            'Active Devices',
            '${d.activeDevice}/${d.totalDevice}',
            Icons.devices_rounded,
            const Color(0xFF3B82F6),
            _cardAnimations[0],
          ),
          _buildCompactMetric(
            'Templates',
            '${d.totScheTemp}/${d.totTemp}',
            Icons.auto_awesome_mosaic_rounded,
            const Color(0xFF8B5CF6),
            _cardAnimations[1],
          ),
          _buildCompactMetric(
            'Live Loc',
            '${d.activeLoc}/${d.totLocation}',
            Icons.location_on_rounded,
            const Color(0xFF10B981),
            _cardAnimations[2],
          ),
          _buildCompactMetric(
            'Assets',
            '${d.imgFile + d.vidFile}',
            Icons.perm_media_rounded,
            const Color(0xFFF59E0B),
            _cardAnimations[3],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetric(
    String title,
    String value,
    IconData icon,
    Color color,
    Animation<double> anim,
  ) {
    return ScaleTransition(
      scale: anim,
      child: FadeTransition(
        opacity: anim,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.01),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 12, color: const Color(0xFFE2E8F0)),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection(_DashboardData d) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: _buildMediaCard(
                'LIVE IMAGE ROTATION',
                'Dynamic display of rotating image galleries',
                _buildSlideshow(d.imageUrls),
                _cardAnimations[4],
              ),
            ),
            if (!isNarrow) const SizedBox(width: 20),
            if (!isNarrow)
              Expanded(
                flex: 1,
                child: _buildMediaCard(
                  'VIDEO BROADCAST',
                  'Streaming real-time video feed broadcast',
                  _buildVideoPlayer(d.videoUrls),
                  _cardAnimations[5],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMediaCard(
    String title,
    String subtitle,
    Widget content,
    Animation<double> anim,
  ) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(anim),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ConstrainedBox(
              // Min height keeps the card visible even on very small windows;
              // it can grow freely above 280 px.
              constraints: const BoxConstraints(minHeight: 280),
              child: Container(
                // No fixed height — the card now uses all available space
                // given by the parent (Expanded inside a Row).
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 40,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Media content: fixed 320px height, shrinks to 200 minimum
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 200,
                        maxHeight: 360,
                      ),
                      child: Container(
                        height: 320,
                        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: -5,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // LIVE badge — top-right corner
            Positioned(
              top: 14,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
                    SizedBox(width: 6),
                    Text(
                      "LIVE",
                      style: TextStyle(
                        color: Color(0xFF3730A3),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideshow(List<String> urls) {
    if (urls.isEmpty)
      return _buildMediaPlaceholder(
        Icons.image_not_supported_rounded,
        'No images available',
      );
    // Full-screen image: fills the card, no blur, no background duplicate.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // ── Background fill (light grey for letterbox areas) ──
          Container(color: const Color(0xFFF1F5F9)),

          // ── Full image — not cropped, fully visible ──
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _slideIndex = i % urls.length),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.all(20),
              child: WebCompatImage(
                url: urls[i % urls.length],
                fit: BoxFit.contain, // whole image always visible
              ),
            ),
          ),

          // ── Blurred border strips (top, bottom, left, right) ── 8px wide, sigma 20
          // Top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 8,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
          // Bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 8,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
          // Left
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 8,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
          // Right
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 8,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(List<String> urls) {
    if (urls.isEmpty)
      return _buildMediaPlaceholder(
        Icons.videocam_off_rounded,
        'No videos available',
      );
    if (!_videoReady) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
      );
    }
    return StatefulBuilder(
      builder: (context, setVideoState) {
        return MouseRegion(
          onEnter: (_) {
            setVideoState(() => _showControls = true);
            _hideControlsTimer?.cancel();
          },
          onExit: (_) {
            _hideControlsTimer?.cancel();
            _hideControlsTimer = Timer(const Duration(seconds: 3), () {
              if (mounted)
                setVideoState(() {
                  _showControls = false;
                  _showMenu = false;
                });
            });
          },
          child: GestureDetector(
            onTap: () {
              setVideoState(() {
                _showControls = !_showControls;
                if (!_showControls) _showMenu = false;
              });
              if (_showControls) {
                _hideControlsTimer?.cancel();
                _hideControlsTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted)
                    setVideoState(() {
                      _showControls = false;
                      _showMenu = false;
                    });
                });
              }
            },
            child: Stack(
              children: [
                // Video Layer
                Positioned.fill(
                  child: SizedBox.expand(
                    child: (_isPiP || _isFullScreen)
                        ? Container(
                            color: Colors.black,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.picture_in_picture_alt_rounded,
                                    color: Colors.white24,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isFullScreen
                                        ? "Playing in Full Screen"
                                        : "Playing in Picture in Picture",
                                    style: const TextStyle(
                                      color: Colors.white24,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            fill: Colors.black,
                          ),
                  ),
                ),

                // Gradient overlay for controls
                if (_showControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 100,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Seek bar + Control bar
                if (_showControls)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Seek Bar ──
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                                activeTrackColor: const Color(0xFF3B82F6),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: const Color(0xFF3B82F6),
                              ),
                              child: Slider(
                                value: _duration.inMilliseconds > 0
                                    ? (_position.inMilliseconds /
                                              _duration.inMilliseconds)
                                          .clamp(0.0, 1.0)
                                    : 0.0,
                                onChanged: (v) {
                                  final target = Duration(
                                    milliseconds: (v * _duration.inMilliseconds)
                                        .toInt(),
                                  );
                                  _player.seek(target);
                                },
                              ),
                            ),
                          ),

                          // ── Control Row ──
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              right: 12,
                              bottom: 8,
                            ),
                            child: Row(
                              children: [
                                // Play / Pause
                                _controlIcon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  onTap: () {
                                    _player.playOrPause();
                                    setVideoState(
                                      () => _isPlaying = !_isPlaying,
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),

                                // Current Position / Duration
                                Text(
                                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),

                                const Spacer(),

                                // Volume Icon + Slider (right side)
                                _controlIcon(
                                  _isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  onTap: () {
                                    setVideoState(() {
                                      _isMuted = !_isMuted;
                                      _player.setVolume(
                                        _isMuted ? 0.0 : _volume * 100,
                                      );
                                    });
                                  },
                                ),
                                SizedBox(
                                  width: 70,
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 8,
                                          ),
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.white,
                                    ),
                                    child: Slider(
                                      value: _isMuted ? 0.0 : _volume,
                                      onChanged: (v) {
                                        setVideoState(() {
                                          _volume = v;
                                          _isMuted = v == 0.0;
                                          _player.setVolume(v * 100);
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Fullscreen
                                _controlIcon(
                                  Icons.fullscreen_rounded,
                                  size: 24,
                                  onTap: _toggleFullScreen,
                                ),

                                // 3-dot menu
                                _controlIcon(
                                  Icons.more_vert_rounded,
                                  onTap: () {
                                    setVideoState(() => _showMenu = !_showMenu);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 3-dot popup menu
                if (_showMenu && _showControls)
                  Positioned(
                    bottom: 64,
                    right: 12,
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE6181818),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _menuItem(
                            Icons.speed_rounded,
                            'Playback Speed',
                            trailing: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            onTap: () {
                              setVideoState(() {
                                const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
                                final idx = speeds.indexOf(_playbackSpeed);
                                _playbackSpeed =
                                    speeds[(idx + 1) % speeds.length];
                                _player.setRate(_playbackSpeed);
                              });
                            },
                          ),
                          Container(
                            height: 1,
                            color: Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          _menuItem(
                            Icons.download_rounded,
                            'Download',
                            onTap: () => setVideoState(() => _showMenu = false),
                          ),
                          Container(
                            height: 1,
                            color: Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          _menuItem(
                            Icons.picture_in_picture_alt_rounded,
                            'Picture in Picture',
                            onTap: _togglePiP,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _controlIcon(IconData icon, {VoidCallback? onTap, double size = 22}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  // _buildFullScreenOverlay is now handled by _FullScreenVideoPage via Navigator.push

  Widget _buildPiPOverlay() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Material(
        elevation: 20,
        color: Colors.transparent,
        child: Container(
          width: 320,
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_in_picture_alt_rounded,
                      color: Color(0xFF3B82F6),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Picture to Picture',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _togglePiP,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              // Video
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                        fill: Colors.black,
                      ),
                    ),
                    // Play/Pause button at bottom
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () {
                            _player.playOrPause();
                            setState(() => _isPlaying = !_isPlaying);
                          },
                          hoverColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrySection(_DashboardData d) {
    return FadeTransition(
      opacity: _cardAnimations[6],
      child: ConstrainedBox(
        // Can grow above 480 px but never forces below that even on small windows.
        constraints: const BoxConstraints(minHeight: 480),
        child: Container(
          // Use a preferred height that stays within the available space;
          // the ConstrainedBox minHeight keeps it tall on big screens.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Hide the 240px side panel when the card is narrower than 600px
              final showSidePanel = constraints.maxWidth >= 600;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Side View (Category Selector) — hidden on narrow screens
                  if (showSidePanel) _buildRegistrySideView(),

                  // On narrow screens show a compact category selector row instead
                  // Main Table View
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!showSidePanel) _buildNarrowCategorySelector(),
                        _buildRegistryHeaderTitle(),
                        // Give the table a fixed 380px slot; it scrolls internally.
                        SizedBox(
                          height: 380,
                          child: _buildRegistryTable(d),
                        ),
                        _buildRegistryFooter(d),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Compact horizontal scrollable category selector for narrow screens
  Widget _buildNarrowCategorySelector() {
    final categories = [
      ('Devices', Icons.devices_rounded, const Color(0xFF3B82F6)),
      ('Templates', Icons.auto_awesome_mosaic_rounded, const Color(0xFF8B5CF6)),
      ('Locations', Icons.location_on_rounded, const Color(0xFF10B981)),
      (
        'Over Views',
        Icons.dashboard_customize_rounded,
        const Color(0xFFF59E0B),
      ),
    ];
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        color: Color(0xFFF8FAFC),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: categories.map((cat) {
            final isSel = _selectedCategory == cat.$1;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = cat.$1;
                _currentPage = 1;
                _sortColumnIndex = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSel ? cat.$3.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSel ? cat.$3 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat.$2,
                      size: 14,
                      color: isSel ? cat.$3 : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat.$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel ? cat.$3 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRegistrySideView() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'PROGRESS TRACK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  'Monitoring the overall progress',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Use Flexible instead of Expanded so the sidebar shrinks with parent
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSideCategoryItem(
                  'Devices',
                  Icons.devices_rounded,
                  const Color(0xFF3B82F6),
                ),
                _buildSideCategoryItem(
                  'Templates',
                  Icons.auto_awesome_mosaic_rounded,
                  const Color(0xFF8B5CF6),
                ),
                _buildSideCategoryItem(
                  'Locations',
                  Icons.location_on_rounded,
                  const Color(0xFF10B981),
                ),
                _buildSideCategoryItem(
                  'Over Views',
                  Icons.dashboard_customize_rounded,
                  const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideCategoryItem(String title, IconData icon, Color color) {
    final isSel = _selectedCategory == title;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedCategory = title;
        _currentPage = 1;
        _sortColumnIndex = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSel
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
          border: isSel ? Border.all(color: const Color(0xFFE2E8F0)) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSel
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF64748B),
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (isSel)
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistryHeaderTitle() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final showEntriesWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Show ',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              width: 75,
              height: 36,
              child: DropdownButtonFormField<int>(
                value: _entriesPerPage,
                dropdownColor: Colors.white,
                icon: const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                ),
                items: [10, 25, 50, 100]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.toString()),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _entriesPerPage = val;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'entries',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

        final searchWidget = SizedBox(
          width: isNarrow ? 180 : 200,
          height: 36,
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _currentPage = 1;
              });
            },
            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
            decoration: InputDecoration(
              hintText: 'Search records...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF334155), width: 1.5),
              ),
            ),
          ),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    showEntriesWidget,
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: searchWidget,
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    showEntriesWidget,
                    searchWidget,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildRegistryTable(_DashboardData d) {
    final rows = _getFilteredRows(d);

    final startIndex = (_currentPage - 1) * _entriesPerPage;
    final endIndex = (startIndex + _entriesPerPage).clamp(0, rows.length);
    final pageRows = rows.sublist(startIndex, endIndex);

    final headers = _getTableHeaders();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minWidth = headers.length * 150.0;
        final double tableWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                // Header
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: headers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final h = entry.value;
                      return Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                h.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  letterSpacing: 1.0,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _sortData(idx, true),
                                  child: Align(
                                    heightFactor: 0.4,
                                    child: Icon(
                                      Icons.arrow_drop_up,
                                      size: 18,
                                      color: _sortColumnIndex == idx && _sortAscending 
                                          ? Colors.blue 
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _sortData(idx, false),
                                  child: Align(
                                    heightFactor: 0.4,
                                    child: Icon(
                                      Icons.arrow_drop_down,
                                      size: 18,
                                      color: _sortColumnIndex == idx && !_sortAscending 
                                          ? Colors.blue 
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Body
                Expanded(
                  child: pageRows.isEmpty
                      ? _buildMediaPlaceholder(
                          Icons.search_off_rounded,
                          'No data available',
                        )
                      : ListView.builder(
                          itemCount: pageRows.length,
                          itemBuilder: (context, index) {
                            final row = pageRows[index];
                            final isOdd = index % 2 != 0;
                            return Container(
                              height: 64,
                              color: isOdd ? const Color(0xFFF8FAFC).withOpacity(0.5) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                children: row.map((cellValue) {
                                  return Expanded(
                                    child: Text(
                                      cellValue.toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF334155),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _getTableHeaders() {
    switch (_selectedCategory) {
      case 'Devices':
        return ['Name', 'Code', 'Model'];
      case 'Templates':
        return ['Name', 'Duration'];
      case 'Locations':
        return ['Name', 'Floor', 'Sub-Location'];
      case 'Over Views':
        return ['Device Name', 'Schedule Name', 'Template Name', 'Template Duration', 'Location Name'];
      default:
        return [];
    }
  }

  List<List<dynamic>> _getFilteredRows(_DashboardData d) {
    List<List<dynamic>> rows = [];
    switch (_selectedCategory) {
      case 'Devices':
        rows = d.deviceList
            .map(
              (e) => [
                e['device_name'] ?? '-',
                e['device_code'] ?? '-',
                e['device_model'] ?? '-',
              ],
            )
            .toList();
        break;
      case 'Templates':
        rows = d.tempList
            .map((e) => [e['temp_name'] ?? '-', e['duration'] ?? '-'])
            .toList();
        break;
      case 'Locations':
        rows = d.locationList
            .map(
              (e) => [
                e['location_name'] ?? '-',
                e['floor'] ?? '-',
                e['sublocation'] ?? '-',
              ],
            )
            .toList();
        break;
      case 'Over Views':
        rows = d.overview
            .map(
              (e) => [
                e['device_name'] ?? '-',
                e['schedule_name'] ?? '-',
                e['template_name'] ?? '-',
                e['template_duration'] ?? '-',
                e['location_name'] ?? '-',
              ],
            )
            .toList();
        break;
      default:
        rows = [];
    }

    // Apply Search Filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      rows = rows.where((row) {
        return row.any((cell) => cell.toString().toLowerCase().contains(query));
      }).toList();
    }
    
    if (_sortColumnIndex != null && rows.isNotEmpty && _sortColumnIndex! < rows.first.length) {
      rows.sort((a, b) {
        final aVal = a[_sortColumnIndex!].toString().toLowerCase();
        final bVal = b[_sortColumnIndex!].toString().toLowerCase();
        
        // Push empty or placeholder values to the absolute bottom
        bool aEmpty = aVal == '-' || aVal.trim().isEmpty;
        bool bEmpty = bVal == '-' || bVal.trim().isEmpty;
        
        if (aEmpty && !bEmpty) return 1;
        if (!aEmpty && bEmpty) return -1;
        if (aEmpty && bEmpty) return 0;
        
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    }
    return rows;
  }

  Widget _buildRegistryFooter(_DashboardData d) {
    final rows = _getFilteredRows(d);
    final total = rows.length;
    final totalPages = (total / _entriesPerPage).ceil().clamp(1, 999999);
    final start = (total == 0) ? 0 : (_currentPage - 1) * _entriesPerPage + 1;
    final end = (_currentPage * _entriesPerPage).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.start,
        overflowSpacing: 8,
        children: [
          Text(
            'Showing $start to $end of $total entries',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPageBtn(
                "Previous",
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
              ),
              ..._buildPageNumberButtons(totalPages),
              _buildPageBtn(
                "Next",
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumberButtons(int totalPages) {
    final visibleCount = totalPages.clamp(1, 3);
    int windowStart = _currentPage - 1;
    if (windowStart < 1) windowStart = 1;
    if (windowStart + visibleCount - 1 > totalPages) {
      windowStart = totalPages - visibleCount + 1;
      if (windowStart < 1) windowStart = 1;
    }
    List<Widget> widgets = [];
    for (int i = windowStart; i < windowStart + visibleCount; i++) {
      final pageNum = i;
      widgets.add(
        _buildPageBtn(
          "$pageNum",
          active: _currentPage == pageNum,
          onTap: () => setState(() => _currentPage = pageNum),
        ),
      );
    }
    return widgets;
  }

  Widget _buildPageBtn(
    String label, {
    bool active = false,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: EdgeInsets.zero,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: active
              ? Colors.blue
              : enabled
                  ? Colors.grey.shade100
                  : Colors.grey.shade50,
          foregroundColor: active
              ? Colors.white
              : enabled
                  ? Colors.black87
                  : Colors.grey.shade400,
          side: active
              ? const BorderSide(color: Colors.blue)
              : BorderSide(color: Colors.grey.shade300),
          padding: EdgeInsets.symmetric(
              horizontal: label.length > 1 ? 15 : 12),
          minimumSize: const Size(40, 36),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero),
        ),
        onPressed: enabled ? onTap : null,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Full-screen video page that covers the ENTIRE screen including the drawer.
/// Pushed via Navigator.of(context, rootNavigator: true).push() to escape
/// the Scaffold/drawer hierarchy.
class _FullScreenVideoPage extends StatefulWidget {
  final VideoController videoController;
  final Player player;
  final bool isPlaying;
  final VoidCallback onClose;
  final VoidCallback onPlayPause;

  const _FullScreenVideoPage({
    required this.videoController,
    required this.player,
    required this.isPlaying,
    required this.onClose,
    required this.onPlayPause,
  });

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late bool _playing;

  @override
  void initState() {
    super.initState();
    _playing = widget.isPlaying;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Video(
              controller: widget.videoController,
              controls: NoVideoControls,
              fill: Colors.black,
            ),
          ),
          // Close button
          Positioned(
            top: 40,
            right: 40,
            child: IconButton(
              icon: const Icon(
                Icons.close_fullscreen_rounded,
                color: Colors.white,
                size: 32,
              ),
              onPressed: widget.onClose,
            ),
          ),
          // Play/Pause button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: IconButton(
                icon: Icon(
                  _playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                  color: Colors.white,
                  size: 64,
                ),
                onPressed: () {
                  widget.onPlayPause();
                  setState(() => _playing = !_playing);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
