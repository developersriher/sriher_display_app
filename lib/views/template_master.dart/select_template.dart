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
  String? fileType = 'images';

  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  List<dynamic> templates = [];
  List<dynamic> categories = [];

  /// Master list: ALL files fetched for current dept+template (images+videos combined).
  /// Radio buttons filter this in-memory — no extra network calls.
  List<dynamic> _masterAvailableFiles = [];

  /// Derived filtered view — updated whenever _masterAvailableFiles or fileType changes.
  List<dynamic> _displayedFiles = [];
  List<dynamic> assignedFiles = [];

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

  /// Restarts the 30-second polling timer.
  void _startPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && selectedTemplateId != null) {
        _silentRefreshAssignedFiles();
        // Also silently sync available files in the background
        _silentRefreshAvailableFiles();
      }
    });
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

  /// Filters _masterAvailableFiles by the current [fileType] and stores result in
  /// [_displayedFiles]. Pure in-memory — zero network calls.
  void _applyFileTypeFilter() {
    if (fileType == 'videos') {
      _displayedFiles = _masterAvailableFiles.where((f) => _isFileVideo(f)).toList();
    } else {
      _displayedFiles = _masterAvailableFiles.where((f) => !_isFileVideo(f)).toList();
    }
  }

  /// Fetches files available for the selected department + template by fetching
  /// BOTH [selectTemplate_availableFilesview] and the Department Library [/fileview].
  /// Merges both lists into [_masterAvailableFiles] and deduplicates by file_id.
  Future<void> _fetchAvailableFiles() async {
    if (selectedTemplateId == null || selectedCategoryId == null) return;
    if (!mounted) return;
    setState(() {
      isLoadingAvailableFiles = true;
      _masterAvailableFiles = [];
      _displayedFiles = [];
      for (var c in _availableFileControllers.values) c.dispose();
      _availableFileControllers.clear();
    });

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;

      // Parallel fetch:
      // a) selectTemplate_availableFilesview (template + category scoped)
      // b) /fileview (Department library uploaded files)
      final results = await Future.wait([
        http.post(
          Uri.parse('$_baseUrl/selectTemplate_availableFilesview?_t=$ts'),
          body: jsonEncode({
            "api_key": _apiKey,
            "template_id": selectedTemplateId,
            "category_id": selectedCategoryId,
          }),
          headers: {'Content-Type': 'application/json'},
        ),
        http.post(
          Uri.parse('$_baseUrl/fileview?_t=$ts'),
          body: jsonEncode({"api_key": _apiKey}),
          headers: {'Content-Type': 'application/json'},
        ),
      ]);

      if (!mounted) return;

      final List<dynamic> merged = [];
      final Set<String> seenIds = {};

      // 1. Parse selectTemplate_availableFilesview
      final r1 = results[0];
      if (r1.statusCode == 200) {
        final data = await _parseJsonAsync(r1.body);
        final List<dynamic> files = List<dynamic>.from(data['data'] ?? []);
        for (final f in files) {
          final id = f['id']?.toString() ?? f['file_id']?.toString() ?? '';
          if (id.isNotEmpty && seenIds.add(id)) {
            merged.add(f);
          }
        }
      }

      // 2. Parse /fileview — filter by selectedCategoryId department if set
      final r2 = results[1];
      if (r2.statusCode == 200) {
        final data = await _parseJsonAsync(r2.body);
        if ((data['status']?.toString() ?? '') == 'Success') {
          final List<dynamic> allFiles = List<dynamic>.from(data['data'] ?? []);
          for (final f in allFiles) {
            final deptId = f['category_id']?.toString() ?? '';
            final deptMatches = deptId.isEmpty || deptId == selectedCategoryId.toString();
            if (!deptMatches) continue;
            final id = f['id']?.toString() ?? f['file_id']?.toString() ?? '';
            if (id.isNotEmpty && seenIds.add(id)) {
              merged.add(f);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _masterAvailableFiles = merged;
          _applyFileTypeFilter();
        });
        debugPrint(
          '[AvailableFiles] Merged ${merged.length} master file(s), ${_displayedFiles.length} filtered for '
          'template=$selectedTemplateId dept=$selectedCategoryId fileType=$fileType',
        );
      }
    } catch (e) {
      debugPrint('_fetchAvailableFiles error: $e');
    } finally {
      if (mounted) setState(() => isLoadingAvailableFiles = false);
    }
  }

  /// Silent background refresh — no spinner, no UI lock.
  /// Updates [_masterAvailableFiles] if any new files are available.
  Future<void> _silentRefreshAvailableFiles() async {
    if (selectedTemplateId == null || selectedCategoryId == null || !mounted) return;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;

      final results = await Future.wait([
        http.post(
          Uri.parse('$_baseUrl/selectTemplate_availableFilesview?_t=$ts'),
          body: jsonEncode({
            "api_key": _apiKey,
            "template_id": selectedTemplateId,
            "category_id": selectedCategoryId,
          }),
          headers: {'Content-Type': 'application/json'},
        ),
        http.post(
          Uri.parse('$_baseUrl/fileview?_t=$ts'),
          body: jsonEncode({"api_key": _apiKey}),
          headers: {'Content-Type': 'application/json'},
        ),
      ]);
      if (!mounted) return;

      final List<dynamic> merged = [];
      final Set<String> seenIds = {};

      final r1 = results[0];
      if (r1.statusCode == 200) {
        final data = await _parseJsonAsync(r1.body);
        for (final f in List<dynamic>.from(data['data'] ?? [])) {
          final id = f['id']?.toString() ?? f['file_id']?.toString() ?? '';
          if (id.isNotEmpty && seenIds.add(id)) merged.add(f);
        }
      }

      final r2 = results[1];
      if (r2.statusCode == 200) {
        final data = await _parseJsonAsync(r2.body);
        if ((data['status']?.toString() ?? '') == 'Success') {
          for (final f in List<dynamic>.from(data['data'] ?? [])) {
            final deptId = f['category_id']?.toString() ?? '';
            if (deptId.isNotEmpty && deptId != selectedCategoryId.toString()) {
              continue;
            }
            final id = f['id']?.toString() ?? f['file_id']?.toString() ?? '';
            if (id.isNotEmpty && seenIds.add(id)) merged.add(f);
          }
        }
      }

      final currentIds = _masterAvailableFiles.map((f) => f['id']?.toString()).join(',');
      final freshIds = merged.map((f) => f['id']?.toString()).join(',');
      if (currentIds != freshIds) {
        debugPrint('[BgSync] Available files updated: ${merged.length} total');
        if (mounted) {
          setState(() {
            _masterAvailableFiles = merged;
            _applyFileTypeFilter();
          });
        }
      }
    } catch (e) {
      debugPrint('[BgSync] _silentRefreshAvailableFiles error: $e');
    }
  }

  String _normalizeAbsoluteUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/uploads/')) {
      return 'https://display.sriher.com$path';
    }
    if (path.startsWith('uploads/')) {
      return 'https://display.sriher.com/$path';
    }
    return 'https://display.sriher.com/uploads/${Uri.encodeFull(path)}';
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

  Future<void> _fetchAssignedFiles() async {
    if (selectedTemplateId == null) return;
    if (!mounted) return;
    setState(() => isLoadingAssignedFiles = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_filesview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = await _parseJsonAsync(response.body);
        debugPrint('[AssignedFiles] response: ${response.body.substring(0, response.body.length.clamp(0, 400))}');
        if (mounted) {
          final List<dynamic> normalized = _normalizeAssignedFiles(data['data'] ?? []);
          setState(() => assignedFiles = normalized);
          if (_tvSlideTimer == null || !_tvSlideTimer!.isActive) {
            _startTvPlayer();
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
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_filesview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 && mounted) {
        final data = await _parseJsonAsync(response.body);
        final List<dynamic> fresh = _normalizeAssignedFiles(data['data'] ?? []);
        // Compare id sequences — only rebuild if order/content changed
        final currentIds = assignedFiles.map((f) => f['id']?.toString()).join(',');
        final freshIds = fresh.map((f) => f['id']?.toString()).join(',');
        if (currentIds != freshIds) {
          debugPrint('[Poll] Assigned files changed — updating list');
          if (mounted) setState(() => assignedFiles = fresh);
        }
      }
    } catch (e) {
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
      debugPrint('[TV_PLAYER] Cycle complete. Re-fetching playlist from backend...');
      await _fetchAssignedFiles();
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

  Future<void> _assignFile(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'$fileName' is already in the current selection list."),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _addingFileIds.add(fileId);
    });

    // Check if file is a video
    final bool isVideo = _isFileVideo(fileRecord);

    // Extract video-specific or configured duration
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

      // Terminal Diagnostic Logging
      print('[ASSIGN VIDEO SUCCESS]: Status ${response.statusCode} - ${response.body}');
      debugPrint('[ASSIGN VIDEO SUCCESS]: Status ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        // Refetch current assigned files via selectTemplate_filesview
        await _fetchAssignedFiles();

        // Extract the updated array of assigned file_ids
        final fileIds = assignedFiles
            .map((f) => int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .toList();

        // Automatically update play order
        if (fileIds.isNotEmpty) {
          try {
            await http.post(
              Uri.parse('$_baseUrl/selectTemplate_updatePlayOrderview'),
              body: jsonEncode({
                "api_key": _apiKey,
                "template_id": selectedTemplateId,
                "file_ids": fileIds,
              }),
              headers: {'Content-Type': 'application/json'},
            );
            debugPrint('[Auto-Sync PlayOrder] Success for fileIds: $fileIds');
          } catch (e) {
            debugPrint('[Auto-Sync PlayOrder] Error: $e');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text: " (${isVideo ? 'Video' : 'Image'}, ${durationSecs}s) has been added to the current selection list.",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        debugPrint('[ASSIGN FILE ERROR]: HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint("_assignFile error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _addingFileIds.remove(fileId);
        });
      }
    }
  }

  Future<void> _removeFile(int fileId, String fileName) async {
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
      if (response.statusCode == 200) {
        await _fetchAssignedFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "'$fileName' has been removed.",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  /// Sends the reordered file_ids to the backend in the exact dragged sequence.
  /// [orderedFiles] is the list in the new play order (must not be null/empty).
  Future<void> _updatePlayOrder([List<dynamic>? orderedFiles]) async {
    if (selectedTemplateId == null) return;
    final files = orderedFiles ?? assignedFiles;
    if (files.isEmpty) return;
    try {
      final fileIds = files
          .map((f) => int.tryParse((f['file_id'] ?? f['id'])?.toString() ?? '') ?? 0)
          .where((id) => id > 0)
          .toList();
      if (fileIds.isEmpty) return;

      debugPrint('[PlayOrder] Sending file_ids: $fileIds for template $selectedTemplateId');

      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_updatePlayOrderview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
          "file_ids": fileIds,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        debugPrint('[PlayOrder] Success: ${response.body}');
        // Persist the new order into parent state immediately
        if (orderedFiles != null && mounted) {
          setState(() {
            assignedFiles = List.from(orderedFiles);
            if (_tvSlideIndex >= assignedFiles.length) {
              _tvSlideIndex = 0;
            }
          });
        }
        await _fetchAssignedFiles();
        if (_tvSlideTimer == null || !_tvSlideTimer!.isActive) {
          _startTvPlayer();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Play order updated successfully"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        debugPrint('[PlayOrder] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[PlayOrder] Error: $e');
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
                _masterAvailableFiles.clear();
                _displayedFiles.clear();
                assignedFiles.clear();
                if (v != null) {
                  isLoadingAvailableFiles = true;
                  isLoadingAssignedFiles = true;
                }
              });
              if (v != null) {
                _fetchAssignedFiles();
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
                _masterAvailableFiles.clear();
                _displayedFiles.clear();
                if (v != null) {
                  isLoadingAvailableFiles = true;
                }
              });
              if (v != null) {
                _fetchAvailableFiles();
                if (selectedTemplateId != null) {
                  _fetchAssignedFiles();
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
                    setState(() {
                      fileType = v!;
                      _applyFileTypeFilter();
                    });
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
                    setState(() {
                      fileType = v!;
                      _applyFileTypeFilter();
                    });
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
                flex: 5,
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
    // _displayedFiles is already filtered by _applyFileTypeFilter().
    // No secondary filter needed — just use it directly.
    final filteredFiles = _displayedFiles;

    // ── Table header ──────────────────────────────────────────────────────────
    final header = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text("File", style: _headerStyle())),
          const SizedBox(width: 28),
          Expanded(flex: 5, child: Text("File Name", style: _headerStyle())),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              "Add",
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
        itemCount: filteredFiles.length,
        itemBuilder: (context, i) {
          final file = filteredFiles[i];
          final fileId = int.tryParse(file['id']?.toString() ?? '0') ?? 0;
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

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 15,
                ),
                child: Row(
                  children: [
                    // ── Thumbnail ─────────────────────────────────────────
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: isVideo ? 140 : 75,
                          height: 75,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildFilePreview(file),
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    // ── File name ─────────────────────────────────────────
                    Expanded(
                      flex: 5,
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
                    const SizedBox(width: 12),
                    // ── Add button ────────────────────────────────────────
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: ElevatedButton(
                          onPressed: _addingFileIds.contains(fileId)
                              ? null
                              : () => _assignFile(
                                    fileId,
                                    controller.text,
                                    file['user_filename'] ??
                                        file['file_name'] ??
                                        'File',
                                    fileRecord: file,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _addingFileIds.contains(fileId)
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
          ),
          child: body,
        ),
      ],
    );
  }

  bool _isFileVideo(dynamic file) {
    if (file == null) return false;
    final String fileName = (file['file_name'] ?? '').toString();
    final String userFileName = (file['user_filename'] ?? '').toString();
    final String fType = (file['file_type'] ?? '').toString().toLowerCase();
    final String fFormat = (file['file_format'] ?? '').toString().toLowerCase();
    final String mimeType = (file['mime_type'] ?? '').toString().toLowerCase();
    final String lowerName = fileName.toLowerCase();
    final String lowerUser = userFileName.toLowerCase();

    // 1. Check file extension in file_name / user_filename
    const exts = ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.flv', '.wmv', '.ts', '.m2ts'];
    for (final ext in exts) {
      if (lowerName.endsWith(ext) || lowerUser.endsWith(ext)) return true;
    }

    // 2. file_type field — raw extension string or MIME-like
    if (fType == 'mp4' || fType == 'mov' || fType == 'avi' ||
        fType == 'mkv' || fType == 'webm' || fType == 'm4v' ||
        fType == '3gp' || fType == 'flv' || fType == 'wmv' ||
        fType == 'ts' || fType == 'm2ts' ||
        fType == 'vinci' || fType == 'live' ||
        fType.contains('video') || fType.contains('vinci') ||
        fType.contains('live')) {
      return true;
    }

    // 3. file_format or mime_type contains 'video'
    if (fFormat.contains('video') || mimeType.contains('video')) return true;

    // 4. Presence of video_720p or video_1080p field with a non-empty value
    //    — server sets these only for video files.
    final String v720 = (file['video_720p'] ?? '').toString().trim();
    final String v1080 = (file['video_1080p'] ?? '').toString().trim();
    final String vUrl = (file['video_url'] ?? '').toString().trim();
    if (v720.isNotEmpty || v1080.isNotEmpty || vUrl.isNotEmpty) return true;

    return false;
  }

  String _getMediaUrl(dynamic file) {
    if (file == null) return '';
    final bool isVid = _isFileVideo(file);
    String raw;
    if (isVid) {
      // For videos: prefer pre-converted URLs, fall back to original file_name
      raw = (file['video_url'] ??
              file['video_720p'] ??
              file['video_1080p'] ??
              file['file_url'] ??
              file['url'] ??
              file['file_name'] ??
              file['user_filename'] ??
              '').toString();
    } else {
      raw = (file['file_url'] ??
              file['url'] ??
              file['file_name'] ??
              file['user_filename'] ??
              '').toString();
    }
    return _normalizeAbsoluteUrl(raw);
  }

  Widget _buildFilePreview(dynamic file) {
    String fileName = (file['file_name'] ?? file['user_filename'] ?? '').toString();
    String userFileName = (file['user_filename'] ?? file['file_name'] ?? '').toString();
    bool isVideo = _isFileVideo(file);
    final fileUrl = _getMediaUrl(file);

    if (isVideo) {
      return VideoThumbnail(
        url: fileUrl,
        title: userFileName.isNotEmpty ? userFileName : fileName,
      );
    } else {
      return WebCompatImage(
        url: fileUrl,
        fit: BoxFit.cover,
        cacheWidth: 300,
      );
    }
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
    return Column(
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
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final file = assignedFiles[i];
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
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // LIVE badge: only show for videos, not images
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
                                Container(
                                  width: _isFileVideo(file) ? 110 : 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildFilePreview(file),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
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
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _removeFile(
                                int.parse(file['id'].toString()),
                                file['user_filename'] ??
                                    file['file_name'] ??
                                    'File',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "File",
              style: _headerStyle(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
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
              child: Text(
                "File Type",
                textAlign: TextAlign.center,
                style: _headerStyle(),
                maxLines: 1,
                softWrap: false,
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
                _masterAvailableFiles = [];
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
    final scrollController = ScrollController();
    List<dynamic> dialogFiles = List.from(assignedFiles);

    StylishDialog.show(
      context: context,
      title: "Change Play Order",
      subtitle:
          "Drag and drop to reorder files. This sequence determines the display loop.",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      maxWidth: 700,
      builder: (context, setDialogState) {
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
                    scrollController: scrollController,
                    itemCount: dialogFiles.length,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < 0 || oldIndex >= dialogFiles.length) return;
                      if (newIndex < 0) return;
                      if (newIndex > dialogFiles.length) newIndex = dialogFiles.length;

                      setDialogState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = dialogFiles.removeAt(oldIndex);
                        dialogFiles.insert(newIndex, item);
                      });
                      setState(() {
                        assignedFiles = List.from(dialogFiles);
                      });
                    },
                    itemBuilder: (context, index) {
                      final file = dialogFiles[index];
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
                      return Container(
                        key: ValueKey(file['id']),
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
                                flex: 3,
                                child: Text(
                                  file['user_filename'] ??
                                      file['file_name'] ??
                                      '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
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
                                      // LIVE badge: only show for videos
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
                                      Container(
                                        width: _isFileVideo(file) ? 80 : 55,
                                        height: 55,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: _buildFilePreview(file),
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
                      shape: RoundedRectangleBorder(
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
                    onPressed: () async {
                      // Capture the exact dragged order before closing dialog
                      final orderedList = List<dynamic>.from(dialogFiles);
                      // Immediately update parent state so the list & TV reflect new order
                      setState(() {
                        assignedFiles = orderedList;
                        if (_tvSlideIndex >= assignedFiles.length) {
                          _tvSlideIndex = 0;
                        }
                      });
                      Navigator.pop(context);
                      // Push exact order to backend
                      await _updatePlayOrder(orderedList);
                      // Re-fetch from server to confirm persisted order
                      await _fetchAssignedFiles();
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
      },
    );
  }
}
