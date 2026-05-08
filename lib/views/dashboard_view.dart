import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_card.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kApiUrl = 'https://display.sriher.com/Dashboardview';
const _kApiKey =
    '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';
const _kBaseUrl = 'https://display.sriher.com/uploads/';

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

    if (json['vinci'] != null && (json['vinci'] as List).isNotEmpty) {
      vidUrls.addAll(
        (json['vinci'] as List).map((e) => '$_kBaseUrl${e['file_name']}'),
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

  String _selectedCategory = 'Devices';
  int _entriesPerPage = 10;
  int _currentPage = 1;
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
                'Server did not respond. Please check your connection.'),
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
      setState(() => _videoReady = true);
    } catch (err) {
      setState(() => _videoError = err.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _slideTimer?.cancel();
    _pageCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();

    final d = _data!;
    return SingleChildScrollView(
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$greeting, ${_userName ?? 'User'}",
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
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
                    Text(
                      "Login Time • ${_loginTime ?? 'Just now'}",
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
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
              ),
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
                  _buildVideoPlayer(d.videoUrls),
                  _cardAnimations[5],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMediaCard(String title, Widget content, Animation<double> anim) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(anim),
        child: Container(
          height: 420,
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
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
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
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
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
                  ],
                ),
              ),
              Expanded(
                child: Container(
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
    );
  }

  Widget _buildSlideshow(List<String> urls) {
    if (urls.isEmpty)
      return _buildMediaPlaceholder(
        Icons.image_not_supported_rounded,
        'No images available',
      );
    return Stack(
      children: [
        // Cinematic Blurred Background
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(seconds: 1),
            child: Image.network(
              urls[_slideIndex % urls.length],
              key: ValueKey(urls[_slideIndex % urls.length]),
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.4),
              colorBlendMode: BlendMode.darken,
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withOpacity(0.1)),
          ),
        ),
        // Main Image
        PageView.builder(
          controller: _pageCtrl,
          onPageChanged: (i) => setState(() => _slideIndex = i % urls.length),
          itemBuilder: (_, i) => Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                urls[i % urls.length],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
        ),
        // Stylish Pagination Indicators
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              urls.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: i == _slideIndex ? 32 : 8,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: i == _slideIndex
                      ? const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                        )
                      : null,
                  color: i == _slideIndex
                      ? null
                      : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer(List<String> urls) {
    if (urls.isEmpty)
      return _buildMediaPlaceholder(
        Icons.videocam_off_rounded,
        'No videos available',
      );
    return Stack(
      children: [
        Positioned.fill(
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
            fill: Colors.black,
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(
              Icons.fullscreen_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {},
          ),
        ),
      ],
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
      child: Container(
        height: 600,
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
        child: Row(
          children: [
            // Side View (Category Selector)
            _buildRegistrySideView(),

            // Main Table View
            Expanded(
              child: Column(
                children: [
                  _buildRegistryHeaderTitle(),
                  Expanded(child: _buildRegistryTable(d)),
                  _buildRegistryFooter(d),
                ],
              ),
            ),
          ],
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
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'PROGRESS TRACK',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: ListView(
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedCategory.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Managing system ${_selectedCategory.toLowerCase()} registry',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const Spacer(),
          // Entries selector
          Row(
            children: [
              const Text(
                'Show ',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white,
                ),
                alignment: Alignment.center,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _entriesPerPage,
                    isDense: true,
                    icon: const Icon(Icons.unfold_more_rounded,
                        size: 16, color: Color(0xFF64748B)),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _entriesPerPage = val;
                          _currentPage = 1;
                        });
                      }
                    },
                    items: [10, 50, 100]
                        .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                        .toList(),
                  ),
                ),
              ),
              const Text(
                ' rows',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegistryTable(_DashboardData d) {
    final rows = _getFilteredRows(d);
    if (rows.isEmpty) {
      return _buildMediaPlaceholder(
        Icons.search_off_rounded,
        'No records found',
      );
    }

    final startIndex = (_currentPage - 1) * _entriesPerPage;
    final endIndex = (startIndex + _entriesPerPage).clamp(0, rows.length);
    final pageRows = rows.sublist(startIndex, endIndex);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                ),
                child: DataTable(
                  columnSpacing: 40,
                  horizontalMargin: 24,
                  dataRowMaxHeight: 64,
                  headingRowHeight: 56,
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                  columns: _getTableHeaders()
                      .map((h) => DataColumn(label: Text(h.toUpperCase())))
                      .toList(),
                  rows: pageRows.asMap().entries.map((entry) {
                    final row = entry.value;
                    return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (entry.key % 2 != 0) {
                          return const Color(0xFFF8FAFC).withOpacity(0.5);
                        }
                        return null;
                      }),
                      cells: row.asMap().entries.map((cellEntry) {
                        final cellValue = cellEntry.value.toString();
                        return DataCell(
                          Text(
                            cellValue,
                            style: TextStyle(
                              color: cellEntry.key == 0
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF334155),
                              fontWeight: cellEntry.key == 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
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
        return ['Device', 'Schedule', 'Template', 'Duration', 'Location'];
      default:
        return [];
    }
  }

  List<List<dynamic>> _getFilteredRows(_DashboardData d) {
    switch (_selectedCategory) {
      case 'Devices':
        return d.deviceList
            .map((e) => [
                  e['device_name'] ?? '-',
                  e['device_code'] ?? '-',
                  e['device_model'] ?? '-',
                ])
            .toList();
      case 'Templates':
        return d.tempList
            .map((e) => [e['temp_name'] ?? '-', e['duration'] ?? '-'])
            .toList();
      case 'Locations':
        return d.locationList
            .map((e) => [
                  e['location_name'] ?? '-',
                  e['floor'] ?? '-',
                  e['sublocation'] ?? '-',
                ])
            .toList();
      case 'Over Views':
        return d.overview
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
      default:
        return [];
    }
  }

  Widget _buildRegistryFooter(_DashboardData d) {
    final rows = _getFilteredRows(d);
    final total = rows.length;
    final totalPages = (total / _entriesPerPage).ceil();
    final start = (total == 0) ? 0 : (_currentPage - 1) * _entriesPerPage + 1;
    final end = (_currentPage * _entriesPerPage).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $start to $end of $total entries',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              _buildPageNavBtn(
                Icons.chevron_left_rounded,
                _currentPage > 1 ? () => setState(() => _currentPage--) : null,
              ),
              const SizedBox(width: 12),
              Text(
                'Page $_currentPage of $totalPages',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              _buildPageNavBtn(
                Icons.chevron_right_rounded,
                _currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? const Color(0xFFE2E8F0) : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

