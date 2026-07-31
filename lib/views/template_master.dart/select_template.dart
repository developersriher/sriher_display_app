import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
  List<dynamic> availableFiles = [];
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
        final data = jsonDecode(response.body);
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
        final data = jsonDecode(response.body);
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

  Future<void> _fetchAvailableFiles() async {
    if (selectedTemplateId == null || selectedCategoryId == null) return;
    if (!mounted) return;
    setState(() => isLoadingAvailableFiles = true);

    // ── FIX #1: category_id in selectTemplate_availableFilesview is a MEDIA
    // type (1 = images, 2 = videos), NOT the department id. Fetch both in
    // parallel so that videos (category_id=2) are never silently excluded.
    try {
      final results = await Future.wait([
        http.post(
          Uri.parse('$_baseUrl/selectTemplate_availableFilesview'),
          body: jsonEncode({
            "api_key": _apiKey,
            "template_id": selectedTemplateId,
            "category_id": 1, // images
          }),
          headers: {'Content-Type': 'application/json'},
        ),
        http.post(
          Uri.parse('$_baseUrl/selectTemplate_availableFilesview'),
          body: jsonEncode({
            "api_key": _apiKey,
            "template_id": selectedTemplateId,
            "category_id": 2, // videos
          }),
          headers: {'Content-Type': 'application/json'},
        ),
      ]);

      if (mounted) {
        final List<dynamic> merged = [];
        final Set<String> seenIds = {};

        for (final resp in results) {
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final files = List<dynamic>.from(data['data'] ?? []);
            for (final f in files) {
              final id = f['id']?.toString() ?? '';
              if (seenIds.add(id)) merged.add(f);
            }
          }
        }

        setState(() {
          availableFiles = merged;
          for (var c in _availableFileControllers.values) c.dispose();
          _availableFileControllers.clear();
        });

        debugPrint(
          '[AvailableFiles] fetched ${merged.length} file(s) '
          '(images + videos) for template $selectedTemplateId',
        );
      }
    } catch (e) {
      debugPrint("_fetchAvailableFiles error: $e");
    } finally {
      if (mounted) setState(() => isLoadingAvailableFiles = false);
    }

    // Also pull in any extra video files that are marked LIVE in the
    // file_upload screen, so they always appear in the video category.
    await _fetchAndMergeLiveVideos();
  }

  /// Fetches all uploaded files from /fileview and merges VIDEO files that are
  /// LIVE (status=1) into [availableFiles] without duplicates.
  /// NOTE: /fileview uses category_id as a DEPARTMENT id, which is unrelated
  /// to the media-type category_id used by selectTemplate_availableFilesview.
  /// We therefore only use the LIVE status flag here — no category_id filter.
  Future<void> _fetchAndMergeLiveVideos() async {
    if (!mounted) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fileview'),
        body: jsonEncode({"api_key": _apiKey}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if ((data['status']?.toString() ?? '') != 'Success') return;

      final allFiles = List<dynamic>.from(data['data'] ?? []);

      // IDs already in the available list (to avoid duplicates)
      final existingIds = availableFiles
          .map((f) => f['id']?.toString() ?? '')
          .toSet();

      // ── FIX #1 (continued): Do NOT filter by category_id here because
      // /fileview's category_id is a department id, not a media type. Only
      // include files that are explicitly toggled LIVE.
      final matchingVideos = allFiles
          .where((f) {
            // Skip if already in the list
            if (existingIds.contains(f['id']?.toString() ?? '')) return false;

            // Must be a video file
            final type = f['file_type']?.toString().toLowerCase() ?? '';
            final fmt = f['file_format']?.toString().toLowerCase() ?? '';
            final name = f['file_name']?.toString().toLowerCase() ?? '';
            final isVideo =
                type.contains('video') ||
                type == 'mp4' ||
                type == 'avi' ||
                type == 'mov' ||
                type == 'mkv' ||
                type == 'webm' ||
                type == 'vinci' ||
                type == 'live' ||
                fmt.contains('video') ||
                name.endsWith('.mp4') ||
                name.endsWith('.avi') ||
                name.endsWith('.mov') ||
                name.endsWith('.mkv') ||
                name.endsWith('.webm');
            if (!isVideo) return false;

            // Only include if the file is set as LIVE
            final status =
                f['file_status']?.toString() ?? f['status']?.toString() ?? '0';
            return status == '1';
          })
          .map((f) {
            return Map<String, dynamic>.from(f)..['_isLive'] = true;
          })
          .toList();

      if (mounted && matchingVideos.isNotEmpty) {
        setState(() => availableFiles = [...availableFiles, ...matchingVideos]);
      }

      debugPrint(
        '[LiveVideos] merged ${matchingVideos.length} LIVE video(s) into available files',
      );
    } catch (e) {
      debugPrint("_fetchAndMergeLiveVideos error: $e");
    }
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
        final data = jsonDecode(response.body);
        debugPrint('[AssignedFiles] response: ${response.body.substring(0, response.body.length.clamp(0, 400))}');
        if (mounted) {
          setState(() => assignedFiles = data['data'] ?? []);
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
        final data = jsonDecode(response.body);
        final List<dynamic> fresh = data['data'] ?? [];
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
      print('[TV_PLAYER] Cycle complete. Re-fetching playlist from backend...');
      await _fetchAssignedFiles();
      _tvSlideIndex = 0;
      if (assignedFiles.isEmpty) return;
    }

    final currentItem = assignedFiles[_tvSlideIndex];
    final String itemId = (currentItem['file_id'] ?? currentItem['id'] ?? '').toString();
    final String userFilename = (currentItem['user_filename'] ?? currentItem['file_name'] ?? '').toString();

    print('[TV_PLAYER] Now Playing Slide: $itemId - $userFilename');

    if (mounted) setState(() {});

    int durationSecs = 10;
    if (currentItem['duration'] != null) {
      durationSecs = int.tryParse(currentItem['duration'].toString()) ?? 10;
    }
    if (durationSecs < 1) durationSecs = 10;

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
    String fileName,
  ) async {
    // Use stored raw duration or parse formatted back to seconds
    final int durationSecs =
        _rawFileDurations[fileId] ?? _parseFormattedDuration(formattedDuration);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_assignFileview'),
        body: jsonEncode({
          "api_key": _apiKey,
          "template_id": selectedTemplateId,
          "file_id": fileId,
          "duration": durationSecs,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        await _fetchAssignedFiles();
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
                    const TextSpan(
                      text: " has been added to the current selection list.",
                      style: TextStyle(color: Colors.white),
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
      }
    } catch (e) {
      debugPrint("Error: $e");
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
          setState(() => assignedFiles = List.from(orderedFiles));
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Play order updated"),
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
                availableFiles.clear();
                assignedFiles.clear();
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
                availableFiles.clear();
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
                  onChanged: (v) =>
                      setState(() => fileType = v!),
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
                  onChanged: (v) =>
                      setState(() => fileType = v!),
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
    final filteredFiles = availableFiles.where((f) {
      final type = f['file_type']?.toString().toLowerCase() ?? '';
      final name = f['file_name']?.toString().toLowerCase() ?? '';
      final format = f['file_format']?.toString().toLowerCase() ?? '';
      if (fileType == null) return false;

      if (fileType == 'images') {
        // Images: standard image types only
        return type.contains('image') ||
            type == 'png' ||
            type == 'jpg' ||
            type == 'jpeg' ||
            type == 'webp' ||
            name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp') ||
            format.contains('image');
      } else {
        // Videos: include standard video types AND live/vinci types.
        // The server stores live-enabled videos as file_type="vinci" or "live".
        final isStandardVideo =
            type.contains('video') ||
            type == 'mp4' ||
            type == 'avi' ||
            type == 'mov' ||
            type == 'mkv' ||
            type == 'webm' ||
            name.endsWith('.mp4') ||
            name.endsWith('.avi') ||
            name.endsWith('.mov') ||
            name.endsWith('.mkv') ||
            name.endsWith('.webm') ||
            format.contains('video');

        // Live videos toggled ON in File Upload get type "vinci" or "live".
        final isLiveVideo =
            type == 'vinci' ||
            type == 'live' ||
            type.contains('vinci') ||
            type.contains('live');

        return isStandardVideo || isLiveVideo;
      }
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
              Expanded(
                flex: 5,
                child: Text("File Name", style: _headerStyle()),
              ),
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
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoadingAvailableFiles)
                const LinearProgressIndicator()
              else if (filteredFiles.isEmpty)
                const Padding(
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
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredFiles.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final file = filteredFiles[i];
                    final fileId = int.tryParse(file['id'].toString()) ?? 0;
                    final bool isVideo = _isFileVideo(file);

                    if (!_availableFileControllers.containsKey(fileId)) {
                      // ── FIX #3: video-specific fields (file_duration,
                      // video_720p) may arrive as JSON null rather than a
                      // missing key, so we guard against null before .toString().
                      final rawDurationVal =
                          file['file_duration'] ?? file['duration'];
                      final rawDurationStr =
                          (rawDurationVal != null &&
                              rawDurationVal.toString() != 'null')
                          ? rawDurationVal.toString()
                          : '30';
                      final rawSecs =
                          double.tryParse(rawDurationStr)?.toInt() ?? 30;
                      _rawFileDurations[fileId] = rawSecs;
                      _availableFileControllers[fileId] = TextEditingController(
                        text: _formatSeconds(rawSecs),
                      );
                    }
                    final controller = _availableFileControllers[fileId]!;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 15,
                      ),
                      color: null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: isVideo ? 140 : 75,
                                    height: 75,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _buildFilePreview(file),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 28),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  file['user_filename'] ??
                                      file['file_name'] ??
                                      '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: ElevatedButton(
                                    onPressed: () => _assignFile(
                                      fileId,
                                      controller.text,
                                      file['user_filename'] ??
                                          file['file_name'] ??
                                          'File',
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
                                    child: const Text(
                                      "Add",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ], // end inner Row children
                          ), // end inner Row
                        ], // end Column children
                      ), // end Column
                    ); // end Container
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isFileVideo(dynamic file) {
    if (file == null) return false;
    String fileName = file['file_name'] ?? '';
    String userFileName = file['user_filename'] ?? '';
    String fType = file['file_type']?.toString().toLowerCase() ?? '';
    String fFormat = file['file_format']?.toString().toLowerCase() ?? '';
    String lowerName = fileName.toLowerCase();
    String lowerUser = userFileName.toLowerCase();

    return lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.webm') ||
        lowerUser.endsWith('.mp4') ||
        lowerUser.endsWith('.avi') ||
        lowerUser.endsWith('.mov') ||
        lowerUser.endsWith('.mkv') ||
        lowerUser.endsWith('.webm') ||
        fType.contains('video') ||
        fType == 'mp4' ||
        fType == 'avi' ||
        fType == 'mov' ||
        fType == 'mkv' ||
        fType == 'webm' ||
        fType == 'vinci' ||
        fType == 'live' ||
        fType.contains('vinci') ||
        fType.contains('live') ||
        fFormat.contains('video');
  }

  Widget _buildFilePreview(dynamic file) {
    String fileName = file['file_name'] ?? '';
    String userFileName = file['user_filename'] ?? '';
    bool isVideo = _isFileVideo(file);

    // Build URL: only encode the filename part, not the whole URL
    final encodedName = Uri.encodeFull(fileName);
    final fileUrl = '$_baseUrl/uploads/$encodedName';

    if (isVideo) {
      return VideoThumbnail(
        url: fileUrl,
        title: userFileName.isNotEmpty ? userFileName : fileName,
      );
    } else {
      return WebCompatImage(
        url: fileUrl,
        fit: BoxFit.cover,
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
                  final availableFile = availableFiles.firstWhere(
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
                availableFiles = [];
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
                      final availableFile = availableFiles.firstWhere(
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
                      setState(() => assignedFiles = orderedList);
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
