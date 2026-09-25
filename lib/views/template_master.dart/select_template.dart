import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../widgets/video_thumbnail.dart';
import '../../widgets/web_compat_image.dart';

class SelectTemplateView extends StatefulWidget {
  const SelectTemplateView({super.key});

  @override
  State<SelectTemplateView> createState() => _SelectTemplateViewState();
}

class _SelectTemplateViewState extends State<SelectTemplateView> {
  int entriesValue = 10;
  int currentPage = 1;
  int availableEntriesValue = 10;
  int availableCurrentPage = 1;
  String searchQuery = "";
  int? selectedTemplateId;
  int? selectedCategoryId;
  String? fileType;

  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  /// Resolves the device_id string for the currently selected template by
  /// checking multiple possible field names in the template record:
  ///   device_id → device_ids → Device_id → access_code
  ///
  /// Returns `null` only when no template is selected or when none of the
  /// known fields carry a usable value.  Works generically for ANY device
  /// code (1001, 1004, 1006, 1008, 1009, or any arbitrary future code)
  /// without hardcoded restrictions.
  String? _resolveActiveDeviceId() {
    if (selectedTemplateId == null) return null;
    try {
      final t = templates.firstWhere(
        (t) => int.tryParse(t['id']?.toString() ?? '') == selectedTemplateId,
        orElse: () => null,
      );
      if (t == null) return null;

      // Try every known field name the backend may use for the device identifier.
      final candidates = [
        t['device_id'],
        t['device_ids'],
        t['Device_id'],
        t['access_code'],
        t['device_code'],
      ];
      for (final raw in candidates) {
        if (raw == null) continue;
        final val = raw.toString().trim();
        if (val.isNotEmpty && val != 'null') return val;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<dynamic> templates = [];
  List<dynamic> categories = [];

  /// Files fetched for the current template + file-type category.
  /// Populated by [_fetchAvailableFiles] and sorted newest-first (id desc).
  /// category_id 1 = Images, 2 = Videos (matches server upload convention).
  List<dynamic> _displayedFiles = [];
  List<dynamic> assignedFiles = [];
  List<dynamic>? _pendingAssignedFiles;

  bool isLoading = false;
  bool isAddingLoading = false;
  bool isUpdatingOrder = false;
  bool isLoadingTemplates = false;
  bool isLoadingCategories = false;
  bool isLoadingAvailableFiles = false;
  bool isLoadingAssignedFiles = false;

  final TextEditingController _durationController = TextEditingController(
    text: "10",
  );
  final TextEditingController _popupNameController = TextEditingController();
  final TextEditingController _newTemplateNameController =
      TextEditingController();
  final TextEditingController _newDepartmentNameController =
      TextEditingController();

  // Map to store controllers for each available file to prevent recreation
  final Map<int, TextEditingController> _availableFileControllers = {};

  // Set tracking file IDs currently in the process of being assigned (debouncing)
  final Set<int> _addingFileIds = {};

  // Set tracking file IDs currently in the process of being removed
  final Set<int> _removingFileIds = {};

  // Background polling timer — re-fetches assignedFiles every 30 s when a
  // template is selected so the controller list stays in sync with the backend
  // (e.g. another user reordered, or the TV completed a cycle and updated).
  Timer? _pollingTimer;

  final GlobalKey<FormState> _templateFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _deptFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
    _fetchCategories();
    // Start background polling — only fires when a template is selected
    _startPollingTimer();
  }

  /// Restarts the 30-second background polling timer.
  void _startPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && selectedTemplateId != null) {
        final now = DateTime.now();
        print('\n[⏱ POLL_TIMER] ────────────────────────────────────────────');
        print('[POLL_TIMER] Tick at $now');
        print('[POLL_TIMER] baseUrl = ${getBaseUrl()}');
        print('[POLL_TIMER] templateId = $selectedTemplateId  deptId = $selectedCategoryId');
        print('[POLL_TIMER] ────────────────────────────────────────────');
        _silentRefreshAssignedFiles();
        // Also silently sync available files in the background
        _silentRefreshAvailableFiles();
      }
    });
    print('[POLL_TIMER] 30-second polling timer started. baseUrl = ${getBaseUrl()}');
  }

  @override
  void deactivate() {
    _pollingTimer?.cancel();
    _tvSlideTimer?.cancel();
    for (var controller in _availableFileControllers.values) {
      controller.dispose();
    }
    _availableFileControllers.clear();
    super.deactivate();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tvSlideTimer?.cancel();
    _durationController.dispose();
    _popupNameController.dispose();
    _newTemplateNameController.dispose();
    _newDepartmentNameController.dispose();
    for (var controller in _availableFileControllers.values) {
      controller.dispose();
    }
    _availableFileControllers.clear();
    super.dispose();
  }

  bool get isSelectionComplete =>
      selectedTemplateId != null && selectedCategoryId != null;

  // Format seconds (int or float) to MM:SS
  String _formatSeconds(dynamic secs) {
    // Handle float strings like "107.228345"
    double d = double.tryParse(secs.toString()) ?? 0;
    int totalSeconds = d.truncate();
    int m = totalSeconds ~/ 60;
    int r = totalSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}";
  }

  // Parse MM:SS back to total seconds
  int _parseFormattedDuration(String formatted) {
    final parts = formatted.split(':');
    if (parts.length == 2) {
      int m = int.tryParse(parts[0]) ?? 0;
      int s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    return int.tryParse(formatted) ?? 10;
  }

  // Store raw durations (in seconds) for API calls
  final Map<int, int> _rawFileDurations = {};

  // ──────────────────────────────────────────────────────────────────────────
  // API CALLS
  // ──────────────────────────────────────────────────────────────────────────

  Future<dynamic> _parseJsonAsync(String body) async {
    if (kIsWeb) {
      return jsonDecode(body);
    }
    return await compute(jsonDecode, body);
  }

  Future<void> _fetchTemplates() async {
    if (!mounted) return;
    setState(() => isLoadingTemplates = true);
    try {
      final response = await http.post(
        Uri.parse(
          '$_baseUrl/new_templateview?_t=${DateTime.now().millisecondsSinceEpoch}',
        ),
        body: jsonEncode({"api_key": _apiKey}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = await _parseJsonAsync(response.body);
        if (mounted) {
          setState(() {
            final List<dynamic> list = data['data'] ?? [];
            list.sort((a, b) {
              final idA = int.tryParse(a['id']?.toString() ?? '') ?? 0;
              final idB = int.tryParse(b['id']?.toString() ?? '') ?? 0;
              return idA.compareTo(idB);
            });
            templates = list;
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => isLoadingTemplates = false);
    }
  }

  Future<void> _fetchCategories() async {
    if (!mounted) return;
    setState(() => isLoadingCategories = true);
    try {
      final response = await http.post(
        Uri.parse(
          '$_baseUrl/categoryview?_t=${DateTime.now().millisecondsSinceEpoch}',
        ),
        body: jsonEncode({"api_key": _apiKey}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = await _parseJsonAsync(response.body);
        if (mounted) {
          setState(() {
            final List<dynamic> list = data['data'] ?? [];
            list.sort((a, b) {
              final idA = int.tryParse(a['id']?.toString() ?? '') ?? 0;
              final idB = int.tryParse(b['id']?.toString() ?? '') ?? 0;
              return idA.compareTo(idB);
            });
            categories = list;
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => isLoadingCategories = false);
    }
  }

  /// Fetches files available for the current template, scoped by file-type
  /// category: category_id=1 (Images) or category_id=2 (Videos).
  /// Results are sorted descending by [id] — newest uploads appear first.
  /// Called on initial load and whenever the radio button selection changes.
  /// Helper that fetches template-scoped available files and merges them
  /// with master uploaded files from `/fileview` so that all old and new
  /// videos/images uploaded via `file_upload.dart` are available.
  Future<List<dynamic>> _fetchMergedAvailableFilesList(
    int categoryId,
    bool wantVideos,
  ) async {
    final List<dynamic> categoryFiles = [];
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = '$_baseUrl/selectTemplate_availableFilesview?_t=$ts';
    final payload = {
      'api_key': _apiKey,
      'template_id': selectedTemplateId,
      'category_id': categoryId,
    };

    // 1. Fetch template-scoped available files
    try {
      final response = await http
          .post(
            Uri.parse(url),
            body: jsonEncode(payload),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = await _parseJsonAsync(response.body);
        if (data is Map && data['data'] is List) {
          categoryFiles.addAll(List<dynamic>.from(data['data']));
        }
      }
    } catch (e) {
      debugPrint('[AvailableFiles] category fetch error: $e');
    }

    // 2. Fetch master repository files (/fileview) to include all uploaded files from file_upload.dart
    final List<dynamic> masterFiles = [];
    try {
      final masterResponse = await http
          .post(
            Uri.parse('$_baseUrl/fileview'),
            body: jsonEncode({'api_key': _apiKey}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (masterResponse.statusCode == 200) {
        final mData = await _parseJsonAsync(masterResponse.body);
        if (mData is Map && mData['data'] is List) {
          masterFiles.addAll(List<dynamic>.from(mData['data']));
        }
      }
    } catch (e) {
      debugPrint('[AvailableFiles] master fileview fetch error: $e');
    }

    // Filter categoryFiles and masterFiles by requested file type (videos vs images/docs)
    final filteredCategory = categoryFiles.where((f) {
      if (f == null) return false;
      if (wantVideos) {
        // Videos tab: exclude any explicit images, accept videos or category 2 files
        if (_hasImageExtension(f)) return false;
        return true;
      } else {
        // Images tab: exclude any explicit videos, accept images or category 1 files
        if (_hasVideoExtension(f)) return false;
        return true;
      }
    }).toList();

    final filteredMaster = masterFiles.where((f) {
      if (f == null) return false;
      if (wantVideos) {
        if (_hasImageExtension(f)) return false;
        return _isFileVideo(f);
      } else {
        if (_hasVideoExtension(f)) return false;
        return !_isFileVideo(f);
      }
    }).toList();

    // 3. Merge filteredCategory and filteredMaster by ID
    final Map<String, dynamic> mergedMap = {};
    for (var f in filteredCategory) {
      if (f == null) continue;
      final idStr = (f['id'] ?? f['file_id'])?.toString();
      if (idStr != null && idStr.isNotEmpty) {
        mergedMap[idStr] = f;
      }
    }

    for (var f in filteredMaster) {
      if (f == null) continue;
      final idStr = (f['id'] ?? f['file_id'])?.toString();
      if (idStr != null && idStr.isNotEmpty && !mergedMap.containsKey(idStr)) {
        mergedMap[idStr] = f;
      }
    }

    return mergedMap.values.toList();
  }

  /// Fetches files available for the current template, scoped by file-type
  /// category: category_id=1 (Images) or category_id=2 (Videos).
  /// Results are sorted descending by [id] — newest uploads appear first.
  /// Merges all uploaded videos from master file repository.
  Future<void> _fetchAvailableFiles() async {
    if (selectedTemplateId == null || fileType == null) {
      if (mounted) {
        setState(() {
          isLoadingAvailableFiles = false;
          _displayedFiles = [];
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      isLoadingAvailableFiles = true;
      _displayedFiles = [];
      for (var c in _availableFileControllers.values) {
        c.dispose();
      }
      _availableFileControllers.clear();
    });

    try {
      final bool wantVideos = fileType == 'videos';
      final int categoryId = wantVideos ? 2 : 1;
      final List<dynamic> merged =
          await _fetchMergedAvailableFilesList(categoryId, wantVideos);

      if (mounted) {
        final List<dynamic> normalized = _normalizeAvailableFiles(merged);
        setState(() => _displayedFiles = normalized);
        debugPrint(
          '[AvailableFiles] Loaded ${normalized.length} total file(s) for '
          'template=$selectedTemplateId category_id=$categoryId (${fileType ?? "none"})',
        );
      }
    } catch (e) {
      debugPrint('_fetchAvailableFiles error: $e');
    } finally {
      if (mounted) setState(() => isLoadingAvailableFiles = false);
    }
  }

  /// Silent background refresh — no spinner, no UI lock.
  /// Re-fetches files and updates [_displayedFiles] when the list changes.
  Future<void> _silentRefreshAvailableFiles() async {
    if (selectedTemplateId == null || fileType == null || !mounted) return;
    try {
      final bool wantVideos = fileType == 'videos';
      final int categoryId = wantVideos ? 2 : 1;
      final List<dynamic> merged =
          await _fetchMergedAvailableFilesList(categoryId, wantVideos);

      if (!mounted) return;
      final List<dynamic> fresh = _normalizeAvailableFiles(merged);

      final currentIds =
          _displayedFiles.map((f) => (f['id'] ?? f['file_id'])?.toString()).join(',');
      final freshIds =
          fresh.map((f) => (f['id'] ?? f['file_id'])?.toString()).join(',');
      if (currentIds != freshIds) {
        debugPrint(
          '[BgSync] Available files updated: ${fresh.length} total for category_id=$categoryId',
        );
        if (mounted) setState(() => _displayedFiles = fresh);
      }
    } catch (e) {
      debugPrint('[BgSync] _silentRefreshAvailableFiles error: $e');
    }
  }

  /// Sends a GET request to notify the digital signage TV device that the
  /// play list has changed and it should re-sync within its 10-minute cycle.
  ///
  /// [deviceId] is resolved dynamically from the selected template's device_id
  /// field so any screen (1001, 1002, 1003, 1004 …) is notified correctly.
  Future<void> _triggerSignageSync(String deviceId) async {
    final syncUrl =
        '$_baseUrl/mobile_app/viewdevice1.php?device_id=$deviceId&sync_status=2';
    print('\n[SIGNAGE_SYNC] ══════════════════════════════════════════');
    print('[SIGNAGE_SYNC] ➤ Triggering digital signage device sync');
    print('[SIGNAGE_SYNC]   baseUrl   : $_baseUrl');
    print('[SIGNAGE_SYNC]   deviceId  : $deviceId');
    print('[SIGNAGE_SYNC]   Full URL  : $syncUrl');
    try {
      final response = await http
          .get(Uri.parse(syncUrl))
          .timeout(const Duration(seconds: 15));
      debugPrint('[API_CALL] GET $syncUrl -> Status: ${response.statusCode}, Body: ${response.body.substring(0, response.body.length.clamp(0, 400))}');
      final truncatedBody = response.body.length > 300
          ? '${response.body.substring(0, 300)}…'
          : response.body;
      print('[SIGNAGE_SYNC] ✔ HTTP ${response.statusCode} — Body: $truncatedBody');
      if (response.statusCode != 200) {
        print('[SIGNAGE_SYNC] ⚠ Non-200 status. TV device may not have received the sync signal.');
      } else {
        print('[SIGNAGE_SYNC] ✅ Sync signal delivered successfully.');
      }
    } catch (e, st) {
      print('[SIGNAGE_SYNC] ❌ Exception during sync: $e');
      print('[SIGNAGE_SYNC]   StackTrace: $st');
    }
    print('[SIGNAGE_SYNC] ══════════════════════════════════════════\n');
  }

  String _normalizeAbsoluteUrl(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$_baseUrl$trimmed';
    }
    if (trimmed.startsWith('uploads/')) {
      return '$_baseUrl/$trimmed';
    }
    return '$_baseUrl/uploads/${Uri.encodeFull(trimmed)}';
  }

  List<dynamic> _normalizeAssignedFiles(List<dynamic> rawList) {
    return rawList.map((file) {
      final Map<String, dynamic> item = Map<String, dynamic>.from(file);
      final String rawName = (item['file_name'] ?? item['user_filename'] ?? '').toString();
      final String video720 = (item['video_720p'] ?? '').toString();
      final String video1080 = (item['video_1080p'] ?? '').toString();
      final bool isVid = _isFileVideo(item);

      // Always build full URLs for image/video fields
      final String fullRawUrl = _normalizeAbsoluteUrl(rawName);
      final String full720 = _normalizeAbsoluteUrl(video720);
      final String full1080 = _normalizeAbsoluteUrl(video1080);

      item['file_url'] = fullRawUrl;
      item['url'] = fullRawUrl;

      if (isVid) {
        // For video files, ensure video_720p and video_1080p always point to a
        // playable URL. Fall back to file_name URL when the converted fields
        // are still empty (e.g. file_status == 2, conversion in progress).
        item['video_720p'] = full720.isNotEmpty ? full720 : fullRawUrl;
        item['video_1080p'] = full1080.isNotEmpty ? full1080 : fullRawUrl;
        // video_url: canonical field the TV device uses
        item['video_url'] = full720.isNotEmpty
            ? full720
            : full1080.isNotEmpty
                ? full1080
                : fullRawUrl;
      } else {
        if (full720.isNotEmpty) item['video_720p'] = full720;
        if (full1080.isNotEmpty) item['video_1080p'] = full1080;
      }

      return item;
    }).toList();
  }

  /// Normalises [file_url], [url720p] / [video_720p], and [video_1080p] fields
  /// for the **available-files** list returned by
  /// [selectTemplate_availableFilesview].  Mirrors [_normalizeAssignedFiles]
  /// but handles the slightly different field names the available-files
  /// endpoint may return (e.g. `file_url`, `url720p`).
  List<dynamic> _normalizeAvailableFiles(List<dynamic> rawList) {
    return rawList.map((file) {
      if (file == null) return file;
      final Map<String, dynamic> item = Map<String, dynamic>.from(file);

      // Raw file path — the server can return this in several field names.
      final String rawName = [
        item['file_name'],
        item['user_filename'],
        item['name'],
        item['file_url'],
        item['url'],
      ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '')?.toString() ?? '';

      if ((item['user_filename'] == null || item['user_filename'].toString().isEmpty) &&
          item['name'] != null && item['name'].toString().isNotEmpty) {
        item['user_filename'] = item['name'];
      }
      if ((item['file_name'] == null || item['file_name'].toString().isEmpty) &&
          item['name'] != null && item['name'].toString().isNotEmpty) {
        item['file_name'] = item['name'];
      }

      // 720p / 1080p video rendition fields
      final String raw720 = [
        item['url720p'],
        item['video_720p'],
        item['url_720p'],
      ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '')?.toString() ?? '';

      final String raw1080 = [
        item['url1080p'],
        item['video_1080p'],
        item['url_1080p'],
      ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '')?.toString() ?? '';

      final bool isVid = _isFileVideo(item);

      final String fullUrl    = _normalizeAbsoluteUrl(rawName);
      final String full720    = _normalizeAbsoluteUrl(raw720);
      final String full1080   = _normalizeAbsoluteUrl(raw1080);

      // Always expose a canonical file_url and url so _buildFilePreview works.
      item['file_url'] = fullUrl;
      item['url']      = fullUrl;

      if (isVid) {
        // For videos: populate all rendition fields and derive video_url.
        // When the converted file is not yet ready (empty), fall back to the
        // original upload URL so the preview still plays.
        item['url720p']     = full720.isNotEmpty  ? full720  : fullUrl;
        item['video_720p']  = full720.isNotEmpty  ? full720  : fullUrl;
        item['url1080p']    = full1080.isNotEmpty ? full1080 : fullUrl;
        item['video_1080p'] = full1080.isNotEmpty ? full1080 : fullUrl;
        item['video_url']   = full720.isNotEmpty
            ? full720
            : full1080.isNotEmpty
                ? full1080
                : fullUrl;
      }

      return item;
    }).toList()
      // Sort newest uploads first (descending id) — guaranteed in both the
      // full-fetch and background silent-refresh paths.
      ..sort((a, b) {
        final idA = int.tryParse(
                a['id']?.toString() ?? a['file_id']?.toString() ?? '') ??
            0;
        final idB = int.tryParse(
                b['id']?.toString() ?? b['file_id']?.toString() ?? '') ??
            0;
        return idB.compareTo(idA);
      });
  }

  /// Helper to merge fresh server data with any optimistic items that have not yet been reflected in the server response.
  List<dynamic> _mergeWithOptimisticAssignedFiles(List<dynamic> serverNormalized) {
    final List<dynamic> merged = serverNormalized.where((n) {
      final nId = int.tryParse((n['file_id'] ?? n['id'])?.toString() ?? '') ?? 0;
      return nId <= 0 || !_removingFileIds.contains(nId);
    }).toList();

    for (var existing in assignedFiles) {
      final exId = int.tryParse((existing['file_id'] ?? existing['id'])?.toString() ?? '') ?? 0;
      if (exId > 0 && !_removingFileIds.contains(exId) && (_addingFileIds.contains(exId) || existing['_isOptimistic'] == true)) {
        final inNormalized = merged.any((n) {
          final nId = int.tryParse((n['file_id'] ?? n['id'])?.toString() ?? '') ?? 0;
          return nId == exId;
        });
        if (!inNormalized) {
          merged.add(existing);
        }
      }
    }
    return merged;
  }

  Future<void> _fetchAssignedFiles({bool forceImmediate = false, bool showLoading = false}) async {
    if (selectedTemplateId == null) return;
    if (!mounted) return;
    if (showLoading && assignedFiles.isEmpty) {
      setState(() => isLoadingAssignedFiles = true);
    }
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_filesview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      debugPrint('[API_CALL] ${response.request?.url} -> Status: ${response.statusCode}, Body: ${response.body.substring(0, response.body.length.clamp(0, 400))}');
      if (response.statusCode == 200) {
        final data = await _parseJsonAsync(response.body);
        debugPrint('[AssignedFiles] response: ${response.body.substring(0, response.body.length.clamp(0, 400))}');
        if (mounted) {
          final List<dynamic> normalized = _normalizeAssignedFiles(data['data'] ?? []);
          final List<dynamic> merged = _mergeWithOptimisticAssignedFiles(normalized);

          final bool isPlayerActive = _tvSlideTimer != null && _tvSlideTimer!.isActive && assignedFiles.isNotEmpty;
          if (!forceImmediate && isPlayerActive && _tvSlideIndex > 0 && _tvSlideIndex < assignedFiles.length) {
            _pendingAssignedFiles = merged;
            debugPrint('[AssignedFiles] Stored updated playlist in pending buffer for next cycle.');
          } else {
            setState(() {
              assignedFiles = merged;
              _pendingAssignedFiles = null;
              if (_tvSlideIndex >= assignedFiles.length) {
                _tvSlideIndex = 0;
              }
            });
            if (_tvSlideTimer == null || !_tvSlideTimer!.isActive) {
              _startTvPlayer();
            }
          }
        }
      } else {
        debugPrint('[AssignedFiles] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint("_fetchAssignedFiles error: $e");
    } finally {
      if (mounted) setState(() => isLoadingAssignedFiles = false);
    }
  }

  /// Silent background refresh — no loading spinner.
  /// Called by the polling timer every 30 s or on slide transitions.
  /// Only updates state if the file_ids sequence has changed so the UI
  /// doesn't rebuild unnecessarily on every poll tick.
  Future<void> _silentRefreshAssignedFiles() async {
    if (selectedTemplateId == null || !mounted) return;
    final endpoint = '$_baseUrl/selectTemplate_filesview';
    print('[POLL] → GET assigned files: $endpoint  template=$selectedTemplateId');
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      print('[POLL] ← HTTP ${response.statusCode} — body length: ${response.body.length}');
      if (response.statusCode == 200 && mounted) {
        final data = await _parseJsonAsync(response.body);
        final List<dynamic> fresh = _normalizeAssignedFiles(data['data'] ?? []);
        final List<dynamic> merged = _mergeWithOptimisticAssignedFiles(fresh);

        final currentIds = assignedFiles
            .map((f) => (f['file_id'] ?? f['id'])?.toString())
            .join(',');
        final mergedIds = merged
            .map((f) => (f['file_id'] ?? f['id'])?.toString())
            .join(',');

        print('[POLL] current IDs: $currentIds');
        print('[POLL]   merged IDs: $mergedIds');
        if (currentIds != mergedIds) {
          print('[POLL] ⚡ Change detected! Updating UI...');
          final bool isPlayerActive = _tvSlideTimer != null && _tvSlideTimer!.isActive && assignedFiles.isNotEmpty;
          if (isPlayerActive && _tvSlideIndex > 0 && _tvSlideIndex < assignedFiles.length) {
            _pendingAssignedFiles = merged;
            print('[POLL] Stored fresh playlist in pending buffer for next loop cycle.');
            debugPrint('[Poll] Stored fresh playlist in pending buffer for next loop cycle.');
          } else {
            if (mounted) {
              setState(() {
                assignedFiles = merged;
                _pendingAssignedFiles = null;
              });
              print('[POLL] ✔ setState() called — UI re-rendered with ${merged.length} items.');
            }
          }
        } else {
          print('[POLL] No change in file order — skipping setState.');
        }
      }
    } catch (e) {
      print('[POLL] ❌ Error: $e');
      debugPrint('[Poll] _silentRefreshAssignedFiles error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TV PLAYER SLIDESHOW LOOP & LOGGING
  // ──────────────────────────────────────────────────────────────────────────
  int _tvSlideIndex = 0;
  Timer? _tvSlideTimer;

  void _startTvPlayer() {
    _tvSlideTimer?.cancel();
    _tvSlideTimer = null;
    _tvSlideIndex = 0;
    if (assignedFiles.isNotEmpty) {
      _playNextTvSlide();
    }
  }

  Future<void> _playNextTvSlide() async {
    _tvSlideTimer?.cancel();
    if (!mounted || selectedTemplateId == null) return;

    if (assignedFiles.isEmpty) return;

    if (_tvSlideIndex >= assignedFiles.length) {
      debugPrint('[TV_PLAYER] Cycle complete. Applying pending playlist or re-fetching from backend...');
      if (_pendingAssignedFiles != null && _pendingAssignedFiles!.isNotEmpty) {
        if (mounted) {
          setState(() {
            assignedFiles = List.from(_pendingAssignedFiles!);
            _pendingAssignedFiles = null;
          });
        }
        debugPrint('[TV_PLAYER] Smoothly applied pending play order list for new loop cycle.');
      } else {
        await _fetchAssignedFiles();
      }
      _tvSlideIndex = 0;
      if (assignedFiles.isEmpty) return;
    }

    final currentItem = assignedFiles[_tvSlideIndex % assignedFiles.length];
    final String itemId = (currentItem['file_id'] ?? currentItem['id'] ?? '').toString();
    final String userFilename = (currentItem['user_filename'] ?? currentItem['file_name'] ?? '').toString();
    final bool isVideo = _isFileVideo(currentItem);

    if (mounted) setState(() {});

    int durationSecs = 10;
    final rawDur = currentItem['file_duration'] ?? currentItem['video_duration'] ?? currentItem['duration'];
    if (rawDur != null && rawDur.toString() != 'null') {
      double d = double.tryParse(rawDur.toString()) ?? 10.0;
      durationSecs = d.ceil();
    }
    if (durationSecs < 1) durationSecs = 10;

    debugPrint(
      '[TV_PLAYER] Playing slide ${_tvSlideIndex + 1}/${assignedFiles.length}: '
      '$itemId - $userFilename [${isVideo ? "VIDEO" : "IMAGE"}, ${durationSecs}s]',
    );

    _tvSlideTimer = Timer(Duration(seconds: durationSecs), () async {
      if (!mounted || selectedTemplateId == null) return;

      // Auto-Fetch Next Order on Slide Transition
      await _silentRefreshAssignedFiles();

      if (mounted) {
        setState(() {
          _tvSlideIndex++;
        });
        _playNextTvSlide();
      }
    });
  }

  Future<void> addFileToTemplate(
    int fileId,
    String formattedDuration,
    String fileName, {
    dynamic fileRecord,
  }) async {
    if (fileId <= 0 || selectedTemplateId == null) return;

    // Debounce rapid double-clicks
    if (_addingFileIds.contains(fileId)) return;

    // Duplicate check: check if fileId is already in assignedFiles
    final bool isAlreadyAssigned = assignedFiles.any((f) {
      final id = int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0;
      return id == fileId;
    });

    if (isAlreadyAssigned) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "'$fileName' is already in the Current Selection List.",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFF57C00),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    final bool isVideo = _isFileVideo(fileRecord);

    int durationSecs =
        _rawFileDurations[fileId] ?? _parseFormattedDuration(formattedDuration);
    if (fileRecord != null) {
      final rawDur = fileRecord['file_duration'] ??
          fileRecord['video_duration'] ??
          fileRecord['duration'];
      if (rawDur != null && rawDur.toString() != 'null') {
        double d = double.tryParse(rawDur.toString()) ?? 0;
        if (d > 0) durationSecs = d.ceil();
      }
    }
    if (durationSecs < 1) durationSecs = isVideo ? 15 : 10;

    if (mounted) {
      setState(() {
        _addingFileIds.add(fileId);
        isAddingLoading = true;
        isLoading = true;
      });
    }

    // ── Cache the messenger BEFORE any await so we can use it safely
    // ── even if the widget is deactivated before the callback fires.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final Map<String, dynamic> payload = {
      "api_key": _apiKey,
      "template_id": selectedTemplateId,
      "file_id": fileId,
      "duration": durationSecs,
    };

    debugPrint('[ASSIGN FILE REQUEST]: $payload');

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_assignFileview'),
        body: jsonEncode(payload),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('[API_CALL] ${response.request?.url} -> Status: ${response.statusCode}, Body: ${response.body.substring(0, response.body.length.clamp(0, 400))}');

      if (response.statusCode == 200) {
        // Show success banner IMMEDIATELY on HTTP 200 before any further async work
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "'$fileName' has been successfully added to the Current Selection List.",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B8A3D),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        // Build normalized item model
        dynamic newItem;
        try {
          if (fileRecord != null) {
            final tempMap = Map<String, dynamic>.from(fileRecord);
            tempMap['id'] = fileId;
            tempMap['file_id'] = fileId;
            tempMap['user_filename'] = fileName;
            tempMap['file_name'] = fileName;
            tempMap['duration'] = durationSecs;
            tempMap['file_duration'] = durationSecs;
            if (tempMap['file_type'] == null || tempMap['file_type'].toString().isEmpty) {
              tempMap['file_type'] = isVideo ? 'Video' : 'Image';
            }
            newItem = _normalizeAssignedFiles([tempMap]).first;
          } else {
            newItem = {
              'id': fileId,
              'file_id': fileId,
              'user_filename': fileName,
              'file_name': fileName,
              'file_type': isVideo ? 'Video' : 'Image',
              'duration': durationSecs,
              'file_duration': durationSecs,
            };
          }
        } catch (normalizeErr) {
          debugPrint('[addFileToTemplate] normalization error (non-fatal): $normalizeErr');
          newItem = {
            'id': fileId,
            'file_id': fileId,
            'user_filename': fileName,
            'file_name': fileName,
            'file_type': isVideo ? 'Video' : 'Image',
            'duration': durationSecs,
            'file_duration': durationSecs,
          };
        }

        // Add to currentSelectionList (assignedFiles) locally after server confirmation
        if (mounted) {
          setState(() {
            final exists = assignedFiles.any((f) {
              final id = int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0;
              return id == fileId;
            });
            if (!exists && newItem != null) {
              assignedFiles.add(newItem);
            }
          });
        }

        // Re-fetch assigned files to stay 100% in sync with database (wrapped in non-fatal catch)
        try {
          await _fetchAssignedFiles(forceImmediate: true, showLoading: false);

          final fileIds = assignedFiles
              .map((f) => int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0)
              .where((id) => id > 0)
              .toList();

          if (fileIds.isNotEmpty) {
            await http.post(
              Uri.parse('$_baseUrl/selectTemplate_updatePlayOrderview'),
              body: jsonEncode({
                "api_key": _apiKey,
                "template_id": selectedTemplateId,
                "file_ids": fileIds,
              }),
              headers: {'Content-Type': 'application/json'},
            );
            // Notify the TV device to re-sync using the dynamically resolved device_id.
            // Always trigger sync on HTTP 200 — never skip.
            final String? deviceId = _resolveActiveDeviceId();
            if (deviceId != null && deviceId.isNotEmpty) {
              _triggerSignageSync(deviceId);
            } else {
              debugPrint('[addFileToTemplate] ⚠ Could not resolve device_id for template $selectedTemplateId — signage sync skipped.');
            }
          }
        } catch (postSyncErr) {
          debugPrint('[addFileToTemplate] Post-assignment sync error (non-fatal): $postSyncErr');
        }
      } else {
        debugPrint('[ASSIGN FILE ERROR]: HTTP ${response.statusCode}: ${response.body}');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Failed to add '$fileName'. Please try again.",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD32F2F),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("addFileToTemplate error: $e");
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Something went wrong while adding '$fileName'. Please try again.",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingFileIds.remove(fileId);
          isAddingLoading = false;
          isLoading = false;
        });
      }
    }
  }

  Future<void> deleteFileFromTemplate(int fileId, String fileName, {dynamic fileRecord}) async {
    if (fileId <= 0) return;

    if (mounted) {
      setState(() {
        _removingFileIds.add(fileId);
      });
    }

    // ── Cache the messenger BEFORE any await so we can use it safely
    // ── even if the widget is deactivated before the callback fires.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_removeFileview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
          "file_id": fileId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      debugPrint('[API_CALL] ${response.request?.url} -> Status: ${response.statusCode}, Body: ${response.body.substring(0, response.body.length.clamp(0, 400))}');

      if (response.statusCode == 200) {
        // Show success banner IMMEDIATELY on HTTP 200 — before any further async work
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "'$fileName' has been successfully removed from the Current Selection List.",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B8A3D),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        // Only remove from local state after server confirms success
        if (mounted) {
          setState(() {
            assignedFiles.removeWhere((f) {
              if (fileRecord != null && f == fileRecord) return true;
              final id = int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0;
              return id > 0 && id == fileId;
            });
            if (_tvSlideIndex >= assignedFiles.length) {
              _tvSlideIndex = 0;
            }
          });
        }

        // Auto-sync remaining play order to backend (wrapped in non-fatal catch)
        try {
          final remainingFileIds = assignedFiles
              .map((f) => int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0)
              .where((id) => id > 0 && id != fileId)
              .toList();

          if (selectedTemplateId != null && remainingFileIds.isNotEmpty) {
            await http.post(
              Uri.parse('$_baseUrl/selectTemplate_updatePlayOrderview'),
              body: jsonEncode({
                "api_key": _apiKey,
                "template_id": selectedTemplateId,
                "file_ids": remainingFileIds,
              }),
              headers: {'Content-Type': 'application/json'},
            );
            // Notify the TV device to re-sync using the dynamically resolved device_id.
            // Always trigger sync on HTTP 200 — never skip.
            final String? deviceId = _resolveActiveDeviceId();
            if (deviceId != null && deviceId.isNotEmpty) {
              _triggerSignageSync(deviceId);
            } else {
              debugPrint('[deleteFileFromTemplate] ⚠ Could not resolve device_id for template $selectedTemplateId — signage sync skipped.');
            }
          }

          await _fetchAssignedFiles(forceImmediate: true, showLoading: false);
        } catch (postSyncErr) {
          debugPrint('[deleteFileFromTemplate] Post-removal sync error (non-fatal): $postSyncErr');
        }
      } else {
        debugPrint('[REMOVE FILE ERROR]: HTTP ${response.statusCode}: ${response.body}');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Failed to remove '$fileName'. Please try again.",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD32F2F),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("deleteFileFromTemplate error: $e");
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Something went wrong while removing '$fileName'. Please try again.",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _removingFileIds.remove(fileId);
        });
      }
    }
  }



  /// Sends the reordered [file_ids] to the backend in the exact dragged
  /// sequence, then — only on a confirmed HTTP 200 — triggers the digital
  /// signage sync so the TV device refreshes within its next sync cycle.
  ///
  /// Sends the reordered [file_ids] to the backend in the exact dragged
  /// sequence, then — only on a confirmed HTTP 200 — triggers the digital
  /// signage sync so the TV device refreshes within its next sync cycle.
  ///
  /// [orderedFiles] is the list in the new play order. When omitted,
  /// [assignedFiles] is used as a fallback.
  Future<void> _updatePlayOrder([List<dynamic>? orderedFiles]) async {
    if (selectedTemplateId == null) return;

    final filesToProcess = orderedFiles ?? assignedFiles;
    if (filesToProcess.isEmpty) return;

    if (isUpdatingOrder) return;

    // Immediately update local state so the UI reflects the reordering without delay
    if (orderedFiles != null) {
      final normalized = _normalizeAssignedFiles(orderedFiles);
      if (mounted) {
        setState(() {
          assignedFiles = normalized;
          _pendingAssignedFiles = null;
          if (_tvSlideIndex >= assignedFiles.length) {
            _tvSlideIndex = 0;
          }
        });
      }
    }

    if (mounted) {
      setState(() {
        isUpdatingOrder = true;
      });
    }

    // ── Cache the messenger BEFORE any await so we can use it safely
    // ── even if the widget is deactivated before the callback fires.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final List<int> orderedFileIds = filesToProcess
          .map((item) => int.tryParse((item['file_id'] ?? item['id'] ?? item['file_master_id'])?.toString() ?? '') ?? 0)
          .where((id) => id > 0)
          .toList();

      if (orderedFileIds.isEmpty) {
        debugPrint('[PLAY_ORDER] ⚠ No valid file IDs found — aborting update.');
        return;
      }

      final playOrderUrl = '$_baseUrl/selectTemplate_updatePlayOrderview';
      final playOrderPayload = {
        "api_key": _apiKey,
        "template_id": selectedTemplateId,
        "file_ids": orderedFileIds,
      };

      debugPrint('[PLAY_ORDER] Sending play-order update: $playOrderPayload');

      final response = await http
          .post(
            Uri.parse(playOrderUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(playOrderPayload),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[API_CALL] ${response.request?.url} -> Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // ── Always trigger signage sync for the active template's device on
        // ── HTTP 200 — never skip. Resolve the device ID dynamically from
        // ── the selected template's known fields.
        final String? activeDeviceId = _resolveActiveDeviceId();
        if (activeDeviceId != null && activeDeviceId.isNotEmpty) {
          debugPrint('[PLAY_ORDER] Triggering signage sync for device: $activeDeviceId');
          _triggerSignageSync(activeDeviceId);
        } else {
          debugPrint('[PLAY_ORDER] ⚠ Could not resolve device_id for template $selectedTemplateId — signage sync could not be triggered.');
        }

        // Show success SnackBar using the pre-cached messenger
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Play order updated successfully",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B8A3D),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      } else {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Failed to update play order on server. Please try again.",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD32F2F),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PLAY_ORDER] ❌ Exception: $e');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Something went wrong while updating the play order. Please try again.",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUpdatingOrder = false;
        });
      }
    }
  }


  // ──────────────────────────────────────────────────────────────────────────
  // UI BUILDERS
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 950;

    final configCard = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.blue.shade50),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnimatedHeading(
            text: "TEMPLATE CONFIGURATION",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 33, 150, 243),
            ),
          ),
          const SizedBox(height: 32),
          _buildFormRow(
            context,
            "Select Template Name",
            selectedTemplateId,
            "Template",
            templates,
            (v) {
              setState(() {
                selectedTemplateId = v;
                fileType = null;
                _displayedFiles.clear();
                assignedFiles.clear();
                _pendingAssignedFiles = null;
                if (v != null) {
                  isLoadingAvailableFiles = true;
                  isLoadingAssignedFiles = true;
                }
              });
              if (v != null) {
                _fetchAssignedFiles(showLoading: true);
                _fetchAvailableFiles();
                // Restart background polling for the newly selected template
                _startPollingTimer();
              }
            },
          ),
          const SizedBox(height: 10),
          _buildFormRow(
            context,
            "Select Department Name",
            selectedCategoryId,
            "Department",
            categories,
            (v) {
              setState(() {
                selectedCategoryId = v;
                fileType = null;
                _displayedFiles.clear();
                if (v != null) {
                  isLoadingAvailableFiles = true;
                }
              });
              if (v != null) {
                _fetchAvailableFiles();
                if (selectedTemplateId != null) {
                  _fetchAssignedFiles(showLoading: true);
                }
              }
            },
          ),
          const SizedBox(height: 24),
          const Text(
            "FILE TYPE",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Radio<String>(
                  value: "images",
                  groupValue: fileType,
                  activeColor: Colors.blue,
                  onChanged: (v) {
                    if (v == fileType) return;
                    setState(() => fileType = v!);
                    // Re-fetch from server with category_id=1 (Images)
                    _fetchAvailableFiles();
                  },
                ),
                const Text(
                  "Images",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 20),
                Radio<String>(
                  value: "videos",
                  groupValue: fileType,
                  activeColor: Colors.blue,
                  onChanged: (v) {
                    if (v == fileType) return;
                    setState(() => fileType = v!);
                    // Re-fetch from server with category_id=2 (Videos)
                    _fetchAvailableFiles();
                  },
                ),
                const Text(
                  "Videos",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final rightCard = selectedTemplateId != null
        ? Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    "CURRENT SELECTION LIST",
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.sort, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                8,
                              ),
                            ),
                          ),
                          onPressed: () =>
                              _showPlayOrderDialog(context),
                          label: const Text(
                            "Change Play Order",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildAssignedDataTable(),
                    ],
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (isMobile) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                configCard,
                if (selectedCategoryId != null) ...[
                  const SizedBox(height: 20),
                  _buildAvailableFilesTable(),
                ],
                if (selectedTemplateId != null) ...[
                  const SizedBox(height: 20),
                  rightCard,
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT PANEL: Configuration Card & Available Files Table
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      configCard,
                      if (selectedCategoryId != null) ...[
                        const SizedBox(height: 32),
                        _buildAvailableFilesTable(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 32),
              // RIGHT PANEL: Content Area (Current Selection List)
              Expanded(
                flex: 6,
                child: selectedTemplateId != null
                    ? SingleChildScrollView(
                        child: rightCard,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 48,
                              color: Colors.blue.shade200,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Select a Template to view & manage its play list",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableFilesTable() {
    final bool wantVideos = fileType == 'videos';
    final filteredFiles = _displayedFiles.where((f) {
      if (f == null) return false;
      final bool isVid = _isFileVideo(f);
      return wantVideos ? isVid : !isVid;
    }).toList();
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 600;

    final String entriesString = availableEntriesValue.toString();

    // ── 1. Top-Right Entries Selector Header ─────────────────────────
    final entriesHeader = Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            fileType == 'videos'
                ? "AVAILABLE VIDEOS (${filteredFiles.length})"
                : "AVAILABLE IMAGES (${filteredFiles.length})",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E293B),
              letterSpacing: 0.5,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Show ",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF334155),
                ),
              ),
              SizedBox(
                width: 75,
                height: 35,
                child: DropdownButtonFormField<String>(
                  value: ["10", "25", "50", "100"].contains(entriesString)
                      ? entriesString
                      : "10",
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  items: ["10", "25", "50", "100"]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        availableEntriesValue = int.tryParse(v) ?? 10;
                        availableCurrentPage = 1;
                      });
                    }
                  },
                ),
              ),
              if (isDesktop) ...[
                const SizedBox(width: 6),
                const Text(
                  " entries",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // ── 2. Pagination Calculations ────────────────────────────────────
    final int perPage = availableEntriesValue > 0 ? availableEntriesValue : 10;
    final int totalCount = filteredFiles.length;
    final int totalPages = (totalCount / perPage).ceil().clamp(1, 999999);
    if (availableCurrentPage > totalPages) availableCurrentPage = totalPages;
    if (availableCurrentPage < 1) availableCurrentPage = 1;
    final int startIndex = ((availableCurrentPage - 1) * perPage).clamp(0, totalCount);
    final int endIndex = (startIndex + perPage).clamp(0, totalCount);
    final List<dynamic> paginatedFiles = (startIndex < totalCount && startIndex >= 0)
        ? filteredFiles.sublist(startIndex, endIndex)
        : [];

    // ── Table header ──────────────────────────────────────────────────────────
    final header = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text("File", style: _headerStyle())),
          const SizedBox(width: 8),
          Expanded(flex: 4, child: Text("File Name", style: _headerStyle())),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "File Type",
                textAlign: TextAlign.center,
                style: _headerStyle(),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              "Action",
              textAlign: TextAlign.center,
              style: _headerStyle(),
            ),
          ),
        ],
      ),
    );

    // ── Body ─────────────────────────────────────────────────────────────────
    Widget body;
    if (isLoadingAvailableFiles) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: LinearProgressIndicator(),
      );
    } else if (filteredFiles.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: Text(
            "No files available for this selection",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } else {
      // ── Lazy ListView.builder — renders only visible rows instantly ─────────
      body = ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: paginatedFiles.length,
        itemBuilder: (context, i) {
          if (i < 0 || i >= paginatedFiles.length) {
            return const SizedBox.shrink();
          }
          final file = paginatedFiles[i];
          if (file == null) return const SizedBox.shrink();
          // Resolve ID from either 'id' or 'file_id' — both field names
          // are used depending on which endpoint returned this file.
          final fileId = int.tryParse(
                (file['id'] ?? file['file_id'])?.toString() ?? '0',
              ) ?? 0;
          final bool isVideo = _isFileVideo(file);

          // Lazily initialise the duration controller for this row
          if (!_availableFileControllers.containsKey(fileId)) {
            final rawDurationVal = file['file_duration'] ?? file['duration'];
            final rawDurationStr =
                (rawDurationVal != null &&
                    rawDurationVal.toString() != 'null')
                    ? rawDurationVal.toString()
                    : '30';
            final rawSecs = double.tryParse(rawDurationStr)?.toInt() ?? 30;
            _rawFileDurations[fileId] = rawSecs;
            _availableFileControllers[fileId] = TextEditingController(
              text: _formatSeconds(rawSecs),
            );
          }
          final controller = _availableFileControllers[fileId]!;
          final bool isMobile = screenWidth < 600;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    // ── Thumbnail ─────────────────────────────────────────
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: isMobile ? (isVideo ? 85 : 65) : (isVideo ? 120 : 75),
                          height: isMobile ? 65 : 75,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildFilePreview(file),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── File name ─────────────────────────────────────────
                    Expanded(
                      flex: 4,
                      child: Text(
                        file['user_filename'] ?? file['file_name'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── File Type Badge ──────────────────────────────────
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            file['file_type']?.toString() ?? (isVideo ? 'Video' : 'Image'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── Add button ────────────────────────────────────────
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: ElevatedButton(
                          onPressed: (_addingFileIds.contains(fileId) || isAddingLoading || isLoading)
                              ? null
                              : () async {
                                  if (mounted) {
                                    setState(() {
                                      isAddingLoading = true;
                                      isLoading = true;
                                    });
                                  }
                                  try {
                                    await addFileToTemplate(
                                      fileId,
                                      controller.text,
                                      file['user_filename'] ??
                                          file['file_name'] ??
                                          'File',
                                      fileRecord: file,
                                    );
                                  } catch (e) {
                                    debugPrint('Add file error: $e');
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        isAddingLoading = false;
                                        isLoading = false;
                                      });
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 10 : 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: (_addingFileIds.contains(fileId) || isAddingLoading || isLoading)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Add",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    final int startItem = totalCount == 0 ? 0 : startIndex + 1;
    final int endItem = endIndex;

    final footer = Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Showing $startItem to $endItem of $totalCount entries",
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (totalPages > 1)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: availableCurrentPage > 1
                      ? () => setState(() => availableCurrentPage--)
                      : null,
                ),
                Text(
                  "$availableCurrentPage / $totalPages",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: availableCurrentPage < totalPages
                      ? () => setState(() => availableCurrentPage++)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entriesHeader,
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              body,
            ],
          ),
        ),
        footer,
      ],
    );
  }

  bool _hasImageExtension(dynamic file) {
    if (file == null) return false;
    final String fn = (file['file_name'] ?? file['user_filename'] ?? file['name'] ?? file['file_url'] ?? file['url'] ?? '').toString().toLowerCase();
    final String ft = (file['file_type'] ?? '').toString().toLowerCase();
    final String mime = (file['mime_type'] ?? '').toString().toLowerCase();

    if (ft == 'jpg' || ft == 'jpeg' || ft == 'png' || ft == 'gif' || ft == 'webp' || ft == 'bmp' || ft == 'svg' || ft == 'image') {
      return true;
    }
    if (mime.startsWith('image/')) return true;

    const imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.jfif', '.heic'];
    for (final ext in imageExts) {
      if (fn.endsWith(ext) || fn.contains('$ext?') || fn.contains('$ext#')) {
        return true;
      }
    }
    return false;
  }

  bool _hasVideoExtension(dynamic file) {
    if (file == null) return false;
    final String fn = (file['file_name'] ?? file['user_filename'] ?? file['name'] ?? file['file_url'] ?? file['url'] ?? '').toString().toLowerCase();
    final String ft = (file['file_type'] ?? '').toString().toLowerCase();
    final String mime = (file['mime_type'] ?? '').toString().toLowerCase();

    if (ft == 'mp4' || ft == 'mov' || ft == 'avi' || ft == 'mkv' || ft == 'webm' || ft == 'm4v' || ft == '3gp' || ft == 'flv' || ft == 'wmv' || ft == 'ts' || ft == 'video') {
      return true;
    }
    if (mime.startsWith('video/')) return true;

    const videoExts = ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.flv', '.wmv', '.ts'];
    for (final ext in videoExts) {
      if (fn.endsWith(ext) || fn.contains('$ext?') || fn.contains('$ext#')) {
        return true;
      }
    }
    return false;
  }

  bool _isFileVideo(dynamic file) {
    if (file == null) return false;
    if (_hasImageExtension(file)) return false;
    if (_hasVideoExtension(file)) return true;

    final String fType = (file['file_type'] ?? '').toString().toLowerCase();
    final String fFormat = (file['file_format'] ?? '').toString().toLowerCase();
    final String mimeType = (file['mime_type'] ?? '').toString().toLowerCase();

    if (fType.contains('video') || fType.contains('vinci') || fType.contains('live') ||
        fFormat.contains('video') || mimeType.contains('video')) {
      return true;
    }

    final String v720 = (file['video_720p'] ?? '').toString().trim().toLowerCase();
    final String v1080 = (file['video_1080p'] ?? '').toString().trim().toLowerCase();
    final String vUrl = (file['video_url'] ?? '').toString().trim().toLowerCase();
    if (v720.isNotEmpty || v1080.isNotEmpty || vUrl.isNotEmpty) return true;

    return false;
  }

  String _getMediaUrl(dynamic file) {
    if (file == null) return '';
    final bool isVid = _isFileVideo(file);
    String raw = '';
    if (isVid) {
      // For videos: prefer pre-converted URLs, fall back to original file_name or file_url
      raw = [
        file['video_url'],
        file['video_720p'],
        file['url720p'],
        file['video_1080p'],
        file['url1080p'],
        file['file_url'],
        file['url'],
        file['file_name'],
      ].firstWhere(
        (v) => v != null && v.toString().trim().isNotEmpty,
        orElse: () => '',
      ).toString();
    } else {
      raw = [
        file['file_url'],
        file['url'],
        file['file_name'],
      ].firstWhere(
        (v) => v != null && v.toString().trim().isNotEmpty,
        orElse: () => '',
      ).toString();
    }
    return _normalizeAbsoluteUrl(raw);
  }

  Widget _buildFilePreview(dynamic file, {bool staticOnly = false}) {
    if (file == null) return _buildFallbackThumbnail();
    String fileName = (file['file_name'] ?? file['user_filename'] ?? '').toString();
    String userFileName = (file['user_filename'] ?? file['file_name'] ?? '').toString();
    bool isVideo = _isFileVideo(file);
    final fileUrl = _getMediaUrl(file);

    if (fileUrl.trim().isEmpty) {
      return _buildFallbackThumbnail(isVideo: isVideo);
    }

    if (isVideo) {
      if (staticOnly) {
        return _buildFallbackThumbnail(isVideo: true);
      }
      return VideoThumbnail(
        url: fileUrl,
        title: userFileName.isNotEmpty ? userFileName : fileName,
      );
    } else {
      return WebCompatImage(
        url: fileUrl,
        fit: BoxFit.cover,
        cacheWidth: 300,
        cacheHeight: 300,
      );
    }
  }

  Widget _buildFallbackThumbnail({bool isVideo = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam : Icons.image,
          color: Colors.white54,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildAssignedDataTable() {
    if (isLoadingAssignedFiles) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double minTableWidth = isMobile ? 550.0 : 650.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _buildListHeader(),
                const SizedBox(height: 8),
                assignedFiles.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(48.0),
                        child: Text(
                          "No files selected",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: assignedFiles.length,
                        separatorBuilder: (c, i) {
                          if (i < 0 || i >= assignedFiles.length - 1) {
                            return const SizedBox.shrink();
                          }
                          return const Divider(height: 1);
                        },
                        itemBuilder: (c, i) {
                          if (i < 0 || i >= assignedFiles.length) {
                            return const SizedBox.shrink();
                          }
                          final file = assignedFiles[i];
                          if (file == null) return const SizedBox.shrink();
                          final String fType = (file['file_type'] ?? '').toString().toLowerCase();
                          final int fileId = int.tryParse(file['id']?.toString() ?? '') ?? 0;
                          final availableFile = _displayedFiles.firstWhere(
                            (f) => (int.tryParse(f['id']?.toString() ?? '') ?? 0) == fileId,
                            orElse: () => null,
                          );
                          final String availFType = (availableFile?['file_type'] ?? '').toString().toLowerCase();
                          final String availFStatus = (availableFile?['file_status'] ?? availableFile?['status'] ?? '0').toString();
                          final bool isLive = (file['file_status']?.toString() ??
                                  file['status']?.toString() ??
                                  '0') ==
                              '1' ||
                              fType == 'vinci' ||
                              fType == 'live' ||
                              fType.contains('vinci') ||
                              fType.contains('live') ||
                              file['_isLive'] == true ||
                              file['is_live'] == true ||
                              availFStatus == '1' ||
                              availFType == 'vinci' ||
                              availFType == 'live' ||
                              availFType.contains('vinci') ||
                              availFType.contains('live') ||
                              availableFile?['_isLive'] == true ||
                              availableFile?['is_live'] == true;
                          // ── Wider thumbnail for videos, square for images ──
                          final bool isVidItem = _isFileVideo(file);
                          // Fixed column width — MUST match the header SizedBox width
                          // so File Name / File Type / Action always align correctly.
                          final double thumbW = isMobile ? 120.0 : 160.0;
                          final double thumbH = isVidItem
                              ? (isMobile ? 75.0  : 100.0)
                              : (isMobile ? 65.0  : 80.0);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // ── Preview column — FIXED WIDTH matching header ──
                                SizedBox(
                                  width: thumbW,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // LIVE badge: only for live-stream videos
                                      if (isLive && _isFileVideo(file)) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade600,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.wifi_tethering,
                                                color: Colors.white,
                                                size: 10,
                                              ),
                                              SizedBox(width: 3),
                                              Text(
                                                'LIVE',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                      // Thumbnail — height varies, width fills the fixed column
                                      SizedBox(
                                        width: thumbW,
                                        height: thumbH,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: _buildFilePreview(file),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // ── File name column — expanded & scrollable ──
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        "${file['user_filename'] ?? file['file_name'] ?? '-'}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        file['file_type']?.toString() ?? '-',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: IconButton(
                                      icon: _removingFileIds.contains(fileId)
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.red,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20,
                                            ),
                                      onPressed: _removingFileIds.contains(fileId)
                                          ? null
                                          : () {
                                              final int targetFileId = int.tryParse(
                                                    (file['file_id'] ?? file['id'])?.toString() ?? '',
                                                  ) ??
                                                  0;
                                              deleteFileFromTemplate(
                                                targetFileId,
                                                file['user_filename'] ??
                                                    file['file_name'] ??
                                                    'File',
                                                fileRecord: file,
                                              );
                                            },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListHeader() {
    // This width MUST match the fixed thumbW used in the row builder above.
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double previewColW = isMobile ? 120.0 : 160.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Preview header — SAME fixed width as the thumbnail SizedBox in the row
          SizedBox(
            width: previewColW,
            child: Text(
              "Preview",
              style: _headerStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              "File Name",
              style: _headerStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                "File Type",
                style: _headerStyle(),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                "Action",
                textAlign: TextAlign.center,
                style: _headerStyle(),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Colors.blueGrey,
  );

  Widget _buildFormRow(
    BuildContext context,
    String hint,
    int? value,
    String label,
    List<dynamic> items,
    ValueChanged<int?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SearchableDropdown<int>(
                value: value,
                hint: hint,
                items: items.map((item) {
                  return SearchableDropdownItem<int>(
                    value: int.tryParse(item['id'].toString()) ?? 0,
                    label: item['temp_name'] ?? item['category_name'] ?? '',
                  );
                }).toList(),
                onChanged: onChanged,
                helperText: ' ', // Reserve space
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Material(
                   color: Colors.blue.shade300,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: (label == 'Template')
                        ? () => _showAddTemplateDialog()
                        : () => _showAddDepartmentDialog(),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addNewTemplate(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/insertNew_templateview'),
        body: jsonEncode({"api_key": _apiKey, "template_name": name}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        bool found = false;
        for (int i = 0; i < 4; i++) {
          await _fetchTemplates();
          dynamic newTemplate;
          for (var t in templates) {
            if (t['temp_name'] == name || t['name'] == name) {
              newTemplate = t;
              break;
            }
          }
          if (newTemplate != null) {
            found = true;
            if (mounted) {
              setState(() {
                selectedTemplateId = int.tryParse(newTemplate['id'].toString());
                selectedCategoryId = null;
                _displayedFiles = [];
                assignedFiles = [];
              });
              _fetchAssignedFiles();
            }
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1500));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                found ? "Template added successfully" : "Processing...",
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error adding template: $e");
    }
  }

  Future<void> _addNewDepartment(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/insertCategoryview'),
        body: jsonEncode({"api_key": _apiKey, "category_name": name}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        bool found = false;
        for (int i = 0; i < 4; i++) {
          await _fetchCategories();
          dynamic newCategory;
          for (var c in categories) {
            if (c['category_name'] == name || c['name'] == name) {
              newCategory = c;
              break;
            }
          }
          if (newCategory != null) {
            found = true;
            if (mounted) {
              setState(() {
                selectedCategoryId = int.tryParse(newCategory['id'].toString());
              });
              _fetchAvailableFiles();
            }
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1500));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                found ? "Department added successfully" : "Processing...",
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error adding department: $e");
    }
  }

  void _showAddTemplateDialog() {
    _newTemplateNameController.clear();
    StylishDialog.show(
      context: context,
      title: "Add Template",
      subtitle: "Define a new template for your display layout.",
      maxWidth: 480,
      builder: (ctx, setPopupState) {
        return Form(
          key: _templateFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      "Template Name",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: _newTemplateNameController,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please enter the template name'
                        : null,
                    decoration: InputDecoration(
                      hintText: "Enter the template name",
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF334155),
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_templateFormKey.currentState!.validate()) {
                        final name = _newTemplateNameController.text.trim();
                        Navigator.pop(context);
                        _addNewTemplate(name);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 32,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Submit",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddDepartmentDialog() {
    _newDepartmentNameController.clear();
    StylishDialog.show(
      context: context,
      title: "Add Department",
      subtitle: "Define a new department for your organization.",
      maxWidth: 480,
      builder: (ctx, setPopupState) {
        return Form(
          key: _deptFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      "Department Name",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: _newDepartmentNameController,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please enter the department name'
                        : null,
                    decoration: InputDecoration(
                      hintText: "Enter the department name",
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF334155),
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_deptFormKey.currentState!.validate()) {
                        final name = _newDepartmentNameController.text.trim();
                        Navigator.pop(context);
                        _addNewDepartment(name);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 32,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Submit",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }


  void _showPlayOrderDialog(BuildContext context) {
    StylishDialog.show(
      context: context,
      title: "Change Play Order",
      subtitle:
          "Drag and drop to reorder files. This sequence determines the display loop.",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      maxWidth: 800,
      builder: (ctx, setDialogState) {
        return _PlayOrderDialogContent(
          initialFiles: assignedFiles,
          displayedFiles: _displayedFiles,
          isFileVideo: _isFileVideo,
          buildFilePreview: _buildFilePreview,
          isUpdatingOrder: isUpdatingOrder,
          onSave: (orderedList) async {
            // Let _updatePlayOrder handle all state changes (pending-buffer
            // logic defers the update to end-of-loop when the slideshow is
            // mid-cycle, preventing glitches).
            await _updatePlayOrder(orderedList);
          },
        );
      },
    );
  }
}

class _PlayOrderDialogContent extends StatefulWidget {
  final List<dynamic> initialFiles;
  final List<dynamic> displayedFiles;
  final bool Function(dynamic file) isFileVideo;
  final Widget Function(dynamic file, {bool staticOnly}) buildFilePreview;
  final bool isUpdatingOrder;
  final Function(List<dynamic> orderedFiles) onSave;

  const _PlayOrderDialogContent({
    required this.initialFiles,
    required this.displayedFiles,
    required this.isFileVideo,
    required this.buildFilePreview,
    this.isUpdatingOrder = false,
    required this.onSave,
  });

  @override
  State<_PlayOrderDialogContent> createState() =>
      _PlayOrderDialogContentState();
}

class _PlayOrderDialogContentState extends State<_PlayOrderDialogContent> {
  late ScrollController _scrollController;
  late List<dynamic> _dialogFiles;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _dialogFiles = List.from(widget.initialFiles);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                scrollController: _scrollController,
                itemCount: _dialogFiles.length,
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < 0 || oldIndex >= _dialogFiles.length) return;
                  if (newIndex < 0) return;

                  if (mounted) {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      if (oldIndex < 0 || oldIndex >= _dialogFiles.length) return;
                      if (newIndex < 0 || newIndex > _dialogFiles.length) return;
                      final item = _dialogFiles.removeAt(oldIndex);
                      _dialogFiles.insert(newIndex, item);
                    });
                  }
                },
                itemBuilder: (context, index) {
                  if (index < 0 || index >= _dialogFiles.length) {
                    return const SizedBox.shrink();
                  }
                  final file = _dialogFiles[index];
                  if (file == null) return const SizedBox.shrink();
                  final String fileIdStr =
                      (file['file_id'] ?? file['id'] ?? 'item').toString();
                  final String fType =
                      (file['file_type'] ?? '').toString().toLowerCase();
                  final int fileId =
                      int.tryParse(file['id']?.toString() ?? '') ?? 0;
                  final availableFile = widget.displayedFiles.firstWhere(
                    (f) =>
                        (int.tryParse(f['id']?.toString() ?? '') ?? 0) == fileId,
                    orElse: () => null,
                  );
                  final String availFType =
                      (availableFile?['file_type'] ?? '').toString().toLowerCase();
                  final String availFStatus = (availableFile?['file_status'] ??
                          availableFile?['status'] ??
                          '0')
                      .toString();
                  final bool isLive = (file['file_status']?.toString() ??
                              file['status']?.toString() ??
                              '0') ==
                          '1' ||
                      fType == 'vinci' ||
                      fType == 'live' ||
                      fType.contains('vinci') ||
                      fType.contains('live') ||
                      file['_isLive'] == true ||
                      file['is_live'] == true ||
                      availFStatus == '1' ||
                      availFType == 'vinci' ||
                      availFType == 'live' ||
                      availFType.contains('vinci') ||
                      availFType.contains('live') ||
                      availableFile?['_isLive'] == true ||
                      availableFile?['is_live'] == true;
                  return Container(
                    key: ValueKey('playorder_${fileIdStr}_$index'),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: const Color(0xFFE2E8F0).withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 16.0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                file['user_filename'] ??
                                    file['file_name'] ??
                                    '',
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isLive && widget.isFileVideo(file)) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade600,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.wifi_tethering,
                                            color: Colors.white,
                                            size: 10,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'LIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Container(
                                    width: widget.isFileVideo(file) ? 80 : 55,
                                    height: 55,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: widget.buildFilePreview(file, staticOnly: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                file['file_type']?.toString() ?? '-',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ReorderableDragStartListener(
                            index: index,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                borderRadius: BorderRadius.zero,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 20,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: widget.isUpdatingOrder
                    ? null
                    : () {
                        final orderedList = List<dynamic>.from(_dialogFiles);
                        Navigator.pop(context);
                        widget.onSave(orderedList);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 32,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: widget.isUpdatingOrder
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Update Play Order",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
