import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../api_config.dart';
import '../../widgets/web_compat_image.dart';
import '../../widgets/video_thumbnail.dart';

/// Tracks a single in-flight background upload.
class _UploadTask {
  final String tempId;
  double progress; // 0.0 → 1.0
  bool hasError;
  String errorMessage;

  _UploadTask({
    required this.tempId,
    this.progress = 0.0,
    this.hasError = false,
    this.errorMessage = '',
  });
}

/**
 * FileUploadView - Master Module
 * * This screen manages the complete Digital Signage File Repository.
 * Features:
 * - Dynamic Department/Category selection
 * - Multipart File Upload (Image/Video)
 * - Real-time Repository Sync (Sorted Latest First)
 * - ID-based Status Toggling and Deletion
 * - Image Preview (Passport size) in Table
 */
class FileUploadView extends StatefulWidget {
  const FileUploadView({super.key});

  @override
  State<FileUploadView> createState() => _FileUploadViewState();
}

class _FileUploadViewState extends State<FileUploadView> {
  // ──────────────────────────────────────────────────────────────────────────
  // API CONFIGURATION & CREDENTIALS
  // ──────────────────────────────────────────────────────────────────────────
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  String get _baseUrl => getBaseUrl();

  // ──────────────────────────────────────────────────────────────────────────
  List<dynamic> fileList = [];
  List<dynamic> _deptList = []; // loaded from /categoryview
  bool isLoading = true;
  bool isSubmitting = false;

  // Tracks IDs whose status toggle API call is currently in-flight.
  // Prevents double-tap flicker and race conditions.
  final Set<String> _pendingToggle = {};

  // Tracks in-flight background uploads keyed by their temp row ID.
  // Each entry holds live progress (0.0–1.0) and error state.
  final Map<String, _UploadTask> _uploadTasks = {};

  // A stable key for ScaffoldMessenger so snackbars can be shown safely
  // even after the dialog/route that triggered the upload has been popped.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Table Pagination & Search
  String entriesValue = "10";
  int currentPage = 1;
  int? editingId;
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Sorting
  int _sortColumnIndex = 0;
  bool _sortAscending = false;

  // Form Selections
  String _selectedType = "Permanent";
  String? _selectedDeptId;
  String? _selectedFileName;
  PlatformFile? _selectedFile;
  String searchQuery = "";
  bool _showDateError = false;
  // Controls when validation errors appear: disabled until Submit is clicked
  AutovalidateMode _dialogAutoValidate = AutovalidateMode.disabled;

  // ──────────────────────────────────────────────────────────────────────────
  // TEXT CONTROLLERS
  // ──────────────────────────────────────────────────────────────────────────
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final GlobalKey<FormState> _deptFormKey = GlobalKey<FormState>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _newDeptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _searchController.addListener(() {
      if (mounted) setState(() => currentPage = 1);
    });
  }

  Future<void> _initializeData() async {
    await fetchDepartments(); // load departments first
    await fetchFilesFromServer();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    _newDeptController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 0: FETCH DEPARTMENTS from /categoryview
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> fetchDepartments() async {
    try {
      // 1. DISMISS DIALOG IMMEDIATELY
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      final response = await http.post(
        Uri.parse('$_baseUrl/categoryview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted)
          setState(() {
            _deptList = decoded['data'] ?? decoded['category_list'] ?? [];
          });
      }
    } catch (e) {
      debugPrint("Dept fetch error: $e");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 0.1: INSERT DEPARTMENT (POST /insertCategoryview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> insertDepartmentAction() async {
    final name = _newDeptController.text.trim();
    if (name.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/insertCategoryview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "category_name": name}),
      );
      if (response.statusCode == 200) {
        _showSnackBar("Department '$name' created.", isSuccess: true);
        _newDeptController.clear();
        await fetchDepartments();
      }
    } catch (e) {
      _showSnackBar("Failed to create department.", isError: true);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 1: FETCH FILES (POST /fileview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> fetchFilesFromServer() async {
    if (mounted) setState(() => isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/fileview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        if ((decoded['status']?.toString() ?? '') == 'Success') {
          final List<dynamic> data = decoded['data'] ?? [];
          if (mounted) {
            setState(() {
              // Keep any in-flight upload rows pinned at the top;
              // replace only real (non-temp) server rows.
              final inFlight = fileList
                  .where(
                    (e) =>
                        e['_isUploading'] == true || e['_uploadError'] != null,
                  )
                  .toList();
              fileList = [...inFlight, ...data];
            });
          }
        }
      }
    } catch (e) {
      debugPrint("fetchFilesFromServer error: $e");
      _showSnackBar("Connectivity Error: Unable to sync with repository.");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Silent background refresh after a successful upload.
  /// Does NOT set isLoading=true so the table stays stable.
  /// Merges newly-arrived server rows at the top without wiping in-flight rows.
  Future<void> _silentRefresh({String? targetFileNameToSetLive}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/fileview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        if ((decoded['status']?.toString() ?? '') == 'Success') {
          final List<dynamic> freshData = decoded['data'] ?? [];
          if (mounted) {
            setState(() {
              // Keep any rows that are still uploading or errored;
              // replace everything else with fresh server data.
              final inFlight = fileList
                  .where(
                    (e) =>
                        e['_isUploading'] == true || e['_uploadError'] != null,
                  )
                  .toList();
              fileList = [...inFlight, ...freshData];
            });

            if (targetFileNameToSetLive != null) {
              final matchedFile = freshData.firstWhere(
                (f) => f['file_name']?.toString() == targetFileNameToSetLive,
                orElse: () => null,
              );
              if (matchedFile != null) {
                final matchedId = matchedFile['id'];
                final currentStatus =
                    matchedFile['status'] ?? matchedFile['file_status'] ?? 0;
                if (currentStatus == 0 || currentStatus == "0") {
                  // Set it to live (1) at the start itself
                  toggleFileStatus(matchedId, 0);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_silentRefresh error: $e');
      // Silent — do not show any snackbar on background refresh failure.
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 2: INSERT FILE — instant dialog dismiss + background streaming upload
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> insertFileAction() async {
    if (!_formKey.currentState!.validate() || _selectedFile == null) {
      if (_selectedFile == null) _showSnackBar("Please pick a file to upload.");
      return;
    }
    if (!mounted) return;

    // Snapshot all form values BEFORE the dialog is popped.
    final String uploadName = _nameController.text.trim();
    final String uploadDesc = _descController.text.trim();
    final String uploadCatId = _selectedDeptId!;
    final String uploadType = _selectedType;
    final String uploadFromDate = _fromDateController.text;
    final String uploadToDate = _toDateController.text;
    final PlatformFile uploadFile = _selectedFile!;
    final String filename = uploadFile.name;
    final String extension = filename.split('.').last.toLowerCase();
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Unique key for this upload session
    final String tempId = 'upload_${DateTime.now().millisecondsSinceEpoch}';

    // ── STEP 1: Dismiss dialog immediately (before any await) ──
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    if (mounted) _resetForm();

    // ── STEP 2: Insert optimistic "uploading" row at top of table ──
    final Map<String, dynamic> optimisticRow = {
      'id': tempId,
      '_isUploading': true,
      'user_filename': uploadName,
      'description': uploadDesc,
      'category_id': uploadCatId,
      'file_name': filename,
      'file_type': extension,
      'file_status': 0,
      'status': 0,
      'type': uploadType == 'Short Term' ? 'Temporary' : uploadType,
      'valid_from_date': uploadType == 'Short Term' ? uploadFromDate : today,
      'valid_upto_date': uploadType == 'Short Term' ? uploadToDate : null,
    };

    if (mounted) {
      setState(() {
        fileList = [optimisticRow, ...fileList];
        _uploadTasks[tempId] = _UploadTask(tempId: tempId);
      });
    }

    // ── STEP 3: Fire-and-forget background upload ──
    _runBackgroundUpload(
      tempId: tempId,
      uploadName: uploadName,
      uploadDesc: uploadDesc,
      uploadCatId: uploadCatId,
      uploadType: uploadType,
      uploadFromDate: uploadFromDate,
      uploadToDate: uploadToDate,
      uploadFile: uploadFile,
      filename: filename,
      extension: extension,
      today: today,
    );
  }

  /// Runs the actual multipart upload in the background.
  /// Updates [_uploadTasks[tempId].progress] as bytes are sent,
  /// then promotes the optimistic row to live-green on success.
  Future<void> _runBackgroundUpload({
    required String tempId,
    required String uploadName,
    required String uploadDesc,
    required String uploadCatId,
    required String uploadType,
    required String uploadFromDate,
    required String uploadToDate,
    required PlatformFile uploadFile,
    required String filename,
    required String extension,
    required String today,
  }) async {
    // Resolve MIME type
    MediaType contentType;
    if (['jpg', 'jpeg'].contains(extension)) {
      contentType = MediaType('image', 'jpeg');
    } else if (extension == 'png') {
      contentType = MediaType('image', 'png');
    } else if (extension == 'gif') {
      contentType = MediaType('image', 'gif');
    } else if (extension == 'webp') {
      contentType = MediaType('image', 'webp');
    } else if (extension == 'mp4') {
      contentType = MediaType('video', 'mp4');
    } else if (extension == 'mov') {
      contentType = MediaType('video', 'quicktime');
    } else if (extension == 'avi') {
      contentType = MediaType('video', 'x-msvideo');
    } else if (extension == 'mkv') {
      contentType = MediaType('video', 'x-matroska');
    } else {
      contentType = MediaType('application', 'octet-stream');
    }

    void _markError(String msg) {
      // Guard against calling setState on a defunct/unmounted widget
      // (can happen with long video uploads if user navigates away)
      if (!mounted) {
        debugPrint('_markError skipped (not mounted): $msg');
        return;
      }
      try {
        setState(() {
          _uploadTasks[tempId]
            ?..hasError = true
            ..errorMessage = msg;
          // Mark the row itself as errored so _getRow can show red UI
          final idx = fileList.indexWhere((e) => e['id']?.toString() == tempId);
          if (idx != -1) {
            fileList[idx] = Map<String, dynamic>.from(fileList[idx])
              ..['_uploadError'] = msg;
          }
        });
        _showSnackBar('Upload failed: $msg', isError: true);
      } catch (e) {
        debugPrint('_markError setState failed: $e');
      }
    }

    final client = http.Client();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/insertFileview'),
      );

      request.fields['api_key'] = _apiKey;
      request.fields['category_id'] = uploadCatId;
      request.fields['name'] = uploadName;
      request.fields['desc'] = uploadDesc;
      request.fields['group5'] = uploadType == 'Short Term'
          ? 'Temporary'
          : uploadType;
      request.fields['file_duration'] = '25';

      if (uploadType == 'Short Term') {
        request.fields['valid_from_date'] = uploadFromDate;
        request.fields['valid_upto_date'] = uploadToDate;
        request.fields['from_date'] = uploadFromDate;
        request.fields['to_date'] = uploadToDate;
        request.fields['valid_from'] = uploadFromDate;
        request.fields['valid_upto'] = uploadToDate;
      } else {
        request.fields['valid_from_date'] = today;
        request.fields['from_date'] = today;
        request.fields['valid_from'] = today;
      }

      if (uploadFile.bytes != null && uploadFile.bytes!.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            uploadFile.bytes!,
            filename: filename,
            contentType: contentType,
          ),
        );
      } else if (uploadFile.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            uploadFile.path!,
            filename: filename,
            contentType: contentType,
          ),
        );
      } else {
        _markError('No file data available.');
        return;
      }

      // ── Send the request and collect the response ──
      // Note: the http package does not expose per-chunk upload progress;
      // the progress indicator stays indeterminate (null value) while uploading.
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(minutes: 15));

      final List<int> responseBytes = [];
      await for (final chunk in streamedResponse.stream) {
        responseBytes.addAll(chunk);
      }

      // Use utf8.decode for safe multi-byte character handling in JSON
      final String responseBody = utf8.decode(
        responseBytes,
        allowMalformed: true,
      );

      debugPrint(
        'Insert response [${streamedResponse.statusCode}]: $responseBody',
      );

      if (streamedResponse.statusCode == 200) {
        Map<String, dynamic> body = {};
        try {
          body = jsonDecode(responseBody) as Map<String, dynamic>;
        } catch (jsonErr) {
          debugPrint('JSON parse error: $jsonErr  raw: $responseBody');
          _markError('Server returned invalid JSON.');
          return;
        }

        // ── Determine success: the server may return the status in two places:
        //   1. Top-level:    {"status": "Success", ...}
        //   2. Inside data:  {"data": {"status": "uploaded", ...}}
        // Both are treated as success.
        final String topStatus = (body['status']?.toString() ?? '')
            .toLowerCase();
        final dynamic dataObj = body['data'];
        final String dataStatus = (dataObj is Map)
            ? (dataObj['status']?.toString() ?? '').toLowerCase()
            : '';

        final bool isSuccess =
            topStatus == 'success' ||
            topStatus == 'uploaded' ||
            dataStatus == 'success' ||
            dataStatus == 'uploaded';

        if (isSuccess) {
          // ── STEP 1: Promote the temp row to a green "completed" state INSTANTLY
          //    so the user sees it turn green immediately, not disappear suddenly.
          if (mounted) {
            try {
              setState(() {
                final idx = fileList.indexWhere(
                  (e) => e['id']?.toString() == tempId,
                );
                if (idx != -1) {
                  fileList[idx] = Map<String, dynamic>.from(fileList[idx])
                    ..['_isUploading'] = false
                    ..['_uploadError'] = null
                    ..['file_status'] = 1
                    ..['status'] = 1;
                }
                _uploadTasks.remove(tempId);
              });
            } catch (e) {
              debugPrint('setState after upload failed: $e');
            }
          }

          // ── STEP 2: Show success snackbar immediately ──
          final isVideo = [
            'mp4',
            'mov',
            'avi',
            'mkv',
            'webm',
          ].contains(extension.toLowerCase());
          final mediaType = isVideo ? 'Video' : 'Image';
          _showSnackBar('✅ $mediaType uploaded successfully!', isSuccess: true);

          // ── STEP 3: Silent background refresh — replaces temp row with the
          //    real server row (with actual ID) without showing a loading spinner.
          String? serverFileName;
          if (dataObj is Map && dataObj['original_path'] != null) {
            final String pathStr = dataObj['original_path'].toString();
            serverFileName = pathStr.split('/').last;
          }
          _silentRefresh(
            targetFileNameToSetLive: isVideo ? serverFileName : null,
          );
        } else {
          _markError(
            body['Message']?.toString() ??
                body['message']?.toString() ??
                (dataObj is Map ? dataObj['message']?.toString() : null) ??
                'Upload failed.',
          );
        }
      } else {
        final hint = streamedResponse.statusCode == 413
            ? ' (file too large)'
            : '';
        _markError('HTTP ${streamedResponse.statusCode}$hint');
      }
    } catch (e) {
      debugPrint('_runBackgroundUpload error: $e');
      _markError(e.toString());
    } finally {
      client.close();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 3: EDIT FETCH (POST /fileEditview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> editFileDetails(dynamic id) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fileEditview'),
        headers: {"Content-Type": "application/json"},
        // Send id as integer, not string
        body: jsonEncode({"api_key": _apiKey, "id": int.parse(id.toString())}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // Normalize: data could be a Map or a single-item List
        dynamic raw = decoded['data'];
        if (raw is List && raw.isNotEmpty) raw = raw.first;
        if (raw == null) {
          _showSnackBar("No data returned for this record.");
          return;
        }
        final Map<String, dynamic> data = Map<String, dynamic>.from(raw);

        setState(() {
          editingId = int.parse(id.toString());
          // user_filename → name field
          _nameController.text =
              data['user_filename']?.toString() ??
              data['name']?.toString() ??
              '';
          // description field
          _descController.text = data['description']?.toString() ?? '';
          // category_id dropdown
          _selectedDeptId = data['category_id']?.toString();
          // API returns "Temporary" but radio button uses "Short Term"; map accordingly
          final rawType =
              data['type']?.toString() ??
              data['group5']?.toString() ??
              'Permanent';
          _selectedType = (rawType == 'Temporary') ? 'Short Term' : 'Permanent';
          // Date fields — API keys confirmed as valid_from_date / valid_upto_date
          _fromDateController.text = data['valid_from_date']?.toString() ?? '';
          _toDateController.text = data['valid_upto_date']?.toString() ?? '';
          _dialogAutoValidate =
              AutovalidateMode.disabled; // Reset validation mode
        });

        // Open the edit dialog after state is set
        if (mounted) _showUploadDialog();
      } else {
        _showSnackBar(
          "Server error ${response.statusCode}: Unable to fetch record.",
        );
      }
    } catch (e) {
      debugPrint("editFileDetails error: $e");
      _showSnackBar("Could not load record. Please try again.");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 4: UPDATE FILE (POST /fileUpdateview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> updateFileAction() async {
    setState(() => isSubmitting = true);
    try {
      if (!_formKey.currentState!.validate()) return;
      final response = await http.post(
        Uri.parse('$_baseUrl/fileUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "id": editingId,
          "category_id": _selectedDeptId,
          "name": _nameController.text.trim(),
          "desc": _descController.text.trim(),
          "group5": _selectedType == "Short Term" ? "Temporary" : _selectedType,
          if (_selectedType == "Short Term") ...{
            "valid_from_date": _fromDateController.text,
            "valid_upto_date": _toDateController.text,
            "from_date": _fromDateController.text,
            "to_date": _toDateController.text,
            "valid_from": _fromDateController.text,
            "valid_upto": _toDateController.text,
          },
        }),
      );

      if (response.statusCode == 200) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        _showSnackBar("Record updated successfully.", isSuccess: true);
        _resetForm();
        fetchFilesFromServer();
      }
    } catch (e) {
      _showSnackBar("Update Error.", isError: true);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 5: STATUS TOGGLE (POST /fileStatusUpdateview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> toggleFileStatus(dynamic id, dynamic currentStatus) async {
    final String rowKey = id?.toString() ?? '';

    // Guard: ignore rapid double-taps while API call is in-flight
    if (_pendingToggle.contains(rowKey)) return;

    final int newStatus = (currentStatus == 1 || currentStatus == "1") ? 0 : 1;
    final idx = fileList.indexWhere((e) => e['id']?.toString() == rowKey);

    // ── STEP 1: Optimistic UI update — flip the switch immediately ──
    if (mounted) {
      setState(() {
        _pendingToggle.add(rowKey);
        if (idx != -1) {
          // Update both field names the server might use
          fileList[idx] = Map<String, dynamic>.from(fileList[idx])
            ..['status'] = newStatus
            ..['file_status'] = newStatus;
        }
      });
    }

    try {
      // ── STEP 2: Hit the server ──
      final response = await http
          .post(
            Uri.parse('$_baseUrl/fileStatusUpdateview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "id": id,
              "status": newStatus,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // ── STEP 3a: Success — keep optimistic state, show feedback ──
        // Do NOT call fetchFilesFromServer() here: that round-trip can return
        // stale cached data and overwrite our optimistic state (race condition).
        _showSnackBar(
          newStatus == 1
              ? "✅ File activated — now live on all displays."
              : "⏸ File deactivated — removed from live stream.",
        );
      } else {
        // ── STEP 3b: Server rejected — rollback ──
        debugPrint('toggleFileStatus: server returned ${response.statusCode}');
        if (idx != -1 && mounted) {
          setState(() {
            fileList[idx] = Map<String, dynamic>.from(fileList[idx])
              ..['status'] = currentStatus
              ..['file_status'] = currentStatus;
          });
        }
        _showSnackBar("Status update failed (${response.statusCode}).");
      }
    } catch (e) {
      // ── STEP 3c: Network error — rollback ──
      debugPrint('toggleFileStatus error: $e');
      if (idx != -1 && mounted) {
        setState(() {
          fileList[idx] = Map<String, dynamic>.from(fileList[idx])
            ..['status'] = currentStatus
            ..['file_status'] = currentStatus;
        });
      }
      _showSnackBar("Network error — status not changed.");
    } finally {
      // ── STEP 4: Always release the pending lock ──
      if (mounted) setState(() => _pendingToggle.remove(rowKey));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 6: DELETE RECORD (POST /deleteFileview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> deleteFileAction(dynamic id) async {
    final confirm = await StylishDialog.show<bool>(
      context: context,
      title: "Delete Confirmation",
      icon: Icons.delete_forever_rounded,
      maxWidth: 400,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to delete this file? This action cannot be undone.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Delete",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    // Capture the item to restore if delete fails
    final deletedItem = fileList.firstWhere(
      (item) => item['id']?.toString() == id.toString(),
      orElse: () => null,
    );
    final deletedIndex = fileList.indexWhere(
      (item) => item['id']?.toString() == id.toString(),
    );

    // 1. IMMEDIATE UI FEEDBACK: Remove from local list
    if (deletedIndex != -1) {
      setState(() {
        fileList.removeAt(deletedIndex);
      });
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/deleteFileview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id}),
      );
      if (response.statusCode == 200) {
        _showSnackBar("File deleted successfully.", isSuccess: true);
        // Sync with server to be safe, but UI is already updated
        fetchFilesFromServer();
      } else {
        // Rollback if failed
        if (deletedItem != null && deletedIndex != -1) {
          setState(() {
            fileList.insert(deletedIndex, deletedItem);
          });
        }
        _showSnackBar("Delete failed.", isError: true);
      }
    } catch (e) {
      // Rollback if error
      if (deletedItem != null && deletedIndex != -1) {
        setState(() {
          fileList.insert(deletedIndex, deletedItem);
        });
      }
      _showSnackBar("Delete Protocol Failed.", isError: true);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS & DATA LOGIC
  // ──────────────────────────────────────────────────────────────────────────

  void _resetForm() {
    setState(() {
      editingId = null;
      _selectedDeptId = null;
      _selectedType = "Permanent";
      _selectedFileName = null;
      _selectedFile = null;
      _showDateError = false;
      _dialogAutoValidate =
          AutovalidateMode.disabled; // reset for next dialog open
    });
    _nameController.clear();
    _descController.clear();
    _fromDateController.clear();
    _toDateController.clear();
  }

  Future<void> _pickFile() async {
    // withData: true ensures bytes are loaded on web; path is used on mobile.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'mp4',
        'mov',
        'avi',
        'mkv',
      ],
      allowMultiple: false,
      withData: true, // Always load bytes (critical for web)
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _selectedFileName = result.files.first.name;
      });
    }
  }

  void _showSnackBar(String m, {bool isSuccess = false, bool isError = false}) {
    // Use the stable messenger key so snackbars work even when the dialog
    // that triggered the action has already been disposed/popped.
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (isSuccess)
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 18,
                )
              else if (isError)
                const Icon(Icons.error_outline, color: Colors.white, size: 18)
              else
                const Icon(Icons.info_outline, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
            ],
          ),
          backgroundColor: isSuccess
              ? const Color(0xFF16A34A)
              : isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF1E40AF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
          duration: Duration(seconds: isError ? 6 : 4),
        ),
      );
  }

  List<dynamic> get _filteredList {
    String query = _searchController.text.toLowerCase();
    // Pin uploading rows (string tempId like "upload_...") and old negative-int
    // optimistic rows to the top; sort real server rows descending by ID.
    final uploading = fileList
        .where(
          (e) =>
              e['_isUploading'] == true ||
              e['_uploadError'] != null ||
              (int.tryParse(e['id'].toString()) ?? 0) < 0,
        )
        .toList();
    final real = fileList
        .where(
          (e) =>
              e['_isUploading'] != true &&
              e['_uploadError'] == null &&
              (int.tryParse(e['id'].toString()) ?? 0) >= 0,
        )
        .toList();

    real.sort(
      (a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(
        int.tryParse(a['id'].toString()) ?? 0,
      ),
    );
    List<dynamic> sorted = [...uploading, ...real];

    if (query.isNotEmpty) {
      sorted = sorted.where((item) {
        final fileName = (item['user_filename'] ?? '').toString().toLowerCase();
        final desc = (item['description'] ?? '').toString().toLowerCase();
        return fileName.contains(query) || desc.contains(query);
      }).toList();
    }

    // Do not sort the uploading records, sort only the real records part
    List<dynamic> finalReal = sorted
        .where((e) => e['_isUploading'] != true && e['_uploadError'] == null)
        .toList();
    List<dynamic> finalUploading = sorted
        .where((e) => e['_isUploading'] == true || e['_uploadError'] != null)
        .toList();

    finalReal.sort((a, b) {
      String aVal = "";
      String bVal = "";

      switch (_sortColumnIndex) {
        case 2:
          aVal = a['user_filename']?.toString() ?? a['name']?.toString() ?? "";
          bVal = b['user_filename']?.toString() ?? b['name']?.toString() ?? "";
          break;
        case 3:
          aVal = a['description']?.toString() ?? "";
          bVal = b['description']?.toString() ?? "";
          break;
        case 4:
          aVal = a['type']?.toString() ?? a['group5']?.toString() ?? "";
          bVal = b['type']?.toString() ?? b['group5']?.toString() ?? "";
          break;
        case 5:
          aVal = a['valid_from_date']?.toString() ?? "";
          bVal = b['valid_from_date']?.toString() ?? "";
          break;
        case 6:
          aVal = a['valid_upto_date']?.toString() ?? "";
          bVal = b['valid_upto_date']?.toString() ?? "";
          break;
        default:
          aVal = a['id']?.toString() ?? "";
          bVal = b['id']?.toString() ?? "";
          break;
      }

      if (_sortColumnIndex == 0) {
        final intA = int.tryParse(aVal) ?? 0;
        final intB = int.tryParse(bVal) ?? 0;
        return _sortAscending ? intA.compareTo(intB) : intB.compareTo(intA);
      }
      return _sortAscending
          ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
          : bVal.toLowerCase().compareTo(aVal.toLowerCase());
    });

    return [...finalUploading, ...finalReal];
  }

  List<dynamic> get _pagedList {
    final filtered = _filteredList;
    final int perPage = int.tryParse(entriesValue) ?? 10;
    int start = (currentPage - 1) * perPage;
    if (start >= filtered.length) return [];
    return filtered.sublist(start, (start + perPage).clamp(0, filtered.length));
  }

  // ─── POPUP DIALOG FOR UPLOAD ───────────────────────────────────────────
  void _showUploadDialog() {
    _formKey = GlobalKey<FormState>();
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Upload File" : "Edit File",
      subtitle: "Add or manage media assets for display",
      icon: editingId == null
          ? Icons.cloud_upload_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.6,
      builder: (context, setDialogState) => Form(
        key: _formKey,
        // Validation only starts after the user clicks Submit
        autovalidateMode: _dialogAutoValidate,
        child: _buildFormCardInDialog(setDialogState),
      ),
    );
  }

  void _showAddDepartmentPopup() {
    final GlobalKey<FormState> dialogFormKey = GlobalKey<FormState>();
    StylishDialog.show(
      context: context,
      title: "Create Department",
      subtitle: "Define a new category for file organization",
      icon: Icons.add_business_rounded,
      maxWidth: 400,
      builder: (ctx, setPopupState) {
        return Form(
          key: dialogFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Category name",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _newDeptController,
                onChanged: (val) => setPopupState(() {}),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please enter the category name'
                    : null,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                decoration: InputDecoration(
                  helperText: ' ', // Reserve space
                  hintText: "Enter the category name",
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              if (_newDeptController.text.trim().isNotEmpty &&
                  _deptList.any(
                    (d) =>
                        d['category_name']?.toString().toLowerCase() ==
                        _newDeptController.text.trim().toLowerCase(),
                  ))
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    "Already exists",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (dialogFormKey.currentState!.validate()) {
                        if (!_deptList.any(
                          (d) =>
                              d['category_name']?.toString().toLowerCase() ==
                              _newDeptController.text.trim().toLowerCase(),
                        )) {
                          insertDepartmentAction();
                          Navigator.pop(ctx);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 24,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
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

  Widget _buildFormCardInDialog(StateSetter setDialogState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    "Department name",
                    style: TextStyle(
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
                        child: SearchableDropdown<String>(
                          value: _selectedDeptId,
                          hint: "Select Department Name",
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Please select the Department Name'
                              : null,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          helperText: ' ',
                          items: _deptList.map((dept) {
                            return SearchableDropdownItem<String>(
                              value: dept['id']?.toString() ?? '',
                              label: dept['category_name']?.toString() ?? '-',
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setDialogState(() => _selectedDeptId = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Material(
                             color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _showAddDepartmentPopup,
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment
                        .center, // Keeps everything perfectly aligned
                    children: [
                      // 1. Added the Label Text on the left
                      const Text(
                        "Selected File: ",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(
                            0xFF0F172A,
                          ), // Matching your dashboard dark theme
                        ),
                      ),
                      const SizedBox(width: 8), // Small gap before the button

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade100,
                          foregroundColor: Colors.blue.shade900,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.zero, // Keeping your sharp edges
                          ),
                        ),
                        onPressed: () async {
                          await _pickFile();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text("Choose File"),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedFileName ?? "No file selected",
                          style: TextStyle(
                            color: _selectedFileName != null
                                ? Colors.black87
                                : Colors.grey,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 30),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // "Enter file name" is now strictly a hint inside the box
                  _buildTextField(
                    "Enter file name",
                    _nameController,
                    onChanged: (val) => setDialogState(() {}),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please enter the file name'
                        : null,
                  ),

                  // Validation message logic
                  if (_nameController.text.trim().isNotEmpty &&
                      fileList.any(
                        (f) =>
                            f['user_filename']?.toString().toLowerCase() ==
                                _nameController.text.trim().toLowerCase() &&
                            f['id']?.toString() != editingId?.toString(),
                      ))
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        "Already exists",
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(
                    height: 20,
                  ), // Adjusted from 30 to 20 for a tighter look
                  // "Description" is now strictly a hint inside the box
                  _buildTextField(
                    "Enter the description",
                    _descController,
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Please enter the description'
                        : null,
                  ),

                  const SizedBox(height: 5),
                ],
              ),
            ),
          ],
        ),
        // Radio buttons + compact date fields in the SAME row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              "Type: ",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontSize: 13,
              ),
            ),
            Radio<String>(
              value: "Permanent",
              groupValue: _selectedType,
              activeColor: Colors.blue,
              onChanged: (v) => setDialogState(() {
                _selectedType = v!;
                _showDateError = false;
              }),
            ),
            const Text(
              "Permanent",
              style: TextStyle(color: Colors.black87, fontSize: 13),
            ),
            const SizedBox(width: 10),
            Radio<String>(
              value: "Short Term",
              groupValue: _selectedType,
              activeColor: Colors.blue,
              onChanged: (v) => setDialogState(() {
                _selectedType = v!;
                _showDateError = false;
              }),
            ),
            const Text(
              "Short Term",
              style: TextStyle(color: Colors.black87, fontSize: 13),
            ),
            const Spacer(),
            // Compact date fields on the right — only visible for Short Term
            if (_selectedType == "Short Term") ...[
              SizedBox(
                width: 150,
                height: 36,
                child: TextFormField(
                  controller: _fromDateController,
                  readOnly: true,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    hintText: "From Date",
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: const Icon(
                      Icons.calendar_today_rounded,
                      size: 15,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF334155),
                        width: 1.6,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      _fromDateController.text =
                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                      setDialogState(() => _showDateError = false);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                height: 36,
                child: TextFormField(
                  controller: _toDateController,
                  readOnly: true,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    hintText: "To Date",
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: const Icon(
                      Icons.calendar_today_rounded,
                      size: 15,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF334155),
                        width: 1.6,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      _toDateController.text =
                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                      setDialogState(() => _showDateError = false);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 5),
        if (_showDateError &&
            _selectedType == "Short Term" &&
            (_fromDateController.text.isEmpty ||
                _toDateController.text.isEmpty))
          const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: Text(
              "Both dates are required for Short Term files.",
              style: TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context), // ← ctx → context
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
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
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () {
                      // Switch to onUserInteraction so errors clear as user types
                      setDialogState(() {
                        _dialogAutoValidate =
                            AutovalidateMode.onUserInteraction;
                      });
                      if (_formKey.currentState!.validate()) {
                        if (_selectedType == "Short Term") {
                          if (_fromDateController.text.isEmpty ||
                              _toDateController.text.isEmpty) {
                            setDialogState(() => _showDateError = true);
                            return;
                          }
                        }
                        if (editingId == null) {
                          insertFileAction();
                        } else {
                          updateFileAction();
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 24,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      editingId == null ? "Submit" : "Update",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ScaffoldMessenger with a stable key ensures snackbars can be shown
    // safely from async callbacks even after dialogs have been popped.
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AnimatedHeading(
                      text: "Uploaded Files List",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        _resetForm();
                        _showUploadDialog();
                      },
                      icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                      label: const Text(
                        "UPLOAD FILE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Repository List Card
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildTableCard(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCard() {
    final paged = _pagedList;
    return Column(
      children: [
        _buildTableHeader(),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildDataTable(paged),
          ),
        ),
        const SizedBox(height: 16),
        _buildTableFooter(paged),
      ],
    );
  }

  Widget _buildDataTable(List<dynamic> data) {
    if (fileList.isNotEmpty && data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 60),
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.blue.shade200,
            ),
            const SizedBox(height: 12),
            Text(
              "No matching files found",
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Try a different search term",
              style: TextStyle(color: Colors.grey, fontSize: 13.0),
            ),
            const SizedBox(height: 60),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return SelectionArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowHeight: 45,
                  dataRowMaxHeight: 75,
                  headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                  border: TableBorder.all(color: Colors.grey.shade100),
                  columns: [
                    _buildCol('ID', 0),
                    _buildCol('IMG/VID', -1),
                    _buildCol('FILE NAME', 2),
                    _buildCol('DESCRIPTION', 3),
                    _buildCol('TYPE', 4),
                    _buildCol('VALID FROM', 5),
                    _buildCol('VALID UPTO', 6),
                    _buildCol('STATUS', -1),
                    _buildCol('DELETE', -1),
                  ],
                  rows: data.map((item) => _getRow(item)).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WIDGET HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  String _formatDate(dynamic d, dynamic type, {bool isFromDate = true}) {
    String typeStr = type?.toString().trim() ?? "";

    // ── Permanent files ──
    if (typeStr == "Permanent" || typeStr == "Permanent File") {
      if (isFromDate) {
        String s = d?.toString().trim() ?? "";
        if (s.isNotEmpty &&
            !s.startsWith("1900") &&
            !s.startsWith("1970") &&
            !s.startsWith("0000")) {
          if (s.contains(" ")) return s.split(" ")[0];
          return s;
        }
        return DateFormat('yyyy-MM-dd').format(DateTime.now());
      } else {
        return "-";
      }
    }

    // ── Temporary / Short Term files ──
    // Show the actual stored date; only suppress truly invalid sentinel values
    if (d == null || d.toString().trim().isEmpty) return "-";
    String s = d.toString().trim();
    // Suppress DB sentinel / epoch-zero placeholders
    if (s == "1900-01-01" || s.startsWith("0000")) return "-";
    // Handle "YYYY-MM-DD HH:MM:SS" → take just the date part
    if (s.contains(" ")) return s.split(" ")[0];
    return s;
  }

  // Returns true if the file_name is a video file
  bool _isVideoFile(String? fileName) {
    if (fileName == null || fileName.isEmpty) return false;
    return [
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
    ].contains(fileName.split('.').last.toLowerCase());
  }

  DataRow _getRow(dynamic item) {
    final String tempId = item['id']?.toString() ?? '';
    final bool isUploading = item['_isUploading'] == true;
    final bool hasError = item['_uploadError'] != null;
    final _UploadTask? task = _uploadTasks[tempId];
    final double progress = task?.progress ?? 0.0;

    final String? fileNameForCheck =
        item['file_name']?.toString() ?? item['user_filename']?.toString();
    final String fileTypeForCheck =
        item['file_type']?.toString().toLowerCase() ?? '';
    final bool isVideo =
        _isVideoFile(fileNameForCheck) ||
        [
          'mp4',
          'mov',
          'avi',
          'mkv',
          'webm',
          'vinci',
          'live',
        ].contains(fileTypeForCheck);

    // ── Uploading row: show progress bar instead of normal content ──
    if (isUploading || hasError) {
      final String errorMsg = item['_uploadError']?.toString() ?? '';
      return DataRow(
        color: WidgetStateProperty.all(
          hasError ? Colors.red.shade50 : Colors.blue.shade50,
        ),
        cells: [
          // ID cell — shows status text
          DataCell(
            Text(
              hasError ? 'Error' : 'Uploading…',
              style: TextStyle(
                color: hasError ? Colors.red : Colors.blue.shade700,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // IMG/VID cell — spinner or error icon
          DataCell(
            Container(
              width: isVideo ? 100 : 60,
              height: 60,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: hasError ? Colors.red.shade200 : Colors.blue.shade200,
                ),
                color: hasError ? Colors.red.shade50 : Colors.blue.shade50,
              ),
              child: hasError
                  ? const Icon(Icons.error_outline, color: Colors.red, size: 24)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            backgroundColor: Colors.blue.shade100,
                            color: Colors.blue.shade600,
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          // Filename
          DataCell(
            Text(
              item['user_filename'] ?? '-',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Description
          DataCell(
            Text(
              item['description'] ?? '-',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          // Type
          DataCell(
            Text(
              item['type'] ?? '-',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          // Valid From
          DataCell(
            Text(
              item['valid_from_date'] ?? '-',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          // Valid Upto
          DataCell(
            Text(
              item['valid_upto_date'] ?? '-',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          // Status — progress % or error
          DataCell(
            hasError
                ? Tooltip(
                    message: errorMsg,
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                  )
                : Text(
                    progress > 0
                        ? '${(progress * 100).toStringAsFixed(0)}%'
                        : 'Queued',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          // Delete — disabled while uploading, enabled on error
          DataCell(
            hasError
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        fileList.removeWhere(
                          (e) => e['id']?.toString() == tempId,
                        );
                        _uploadTasks.remove(tempId);
                      });
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }

    // ── Normal row ──────────────────────────────────────────────────────────
    final String? fileName = item['file_name']?.toString().trim();
    // Image URL: https://display.sriher.com/uploads/{file_name}
    final String imageUrl = '$_baseUrl/uploads/$fileName';

    return DataRow(
      cells: [
        DataCell(
          Text(
            item['id']?.toString() ?? '-',
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: isVideo ? 100 : 60,
              height: 60,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.grey.shade100,
              ),
              child: fileName != null && fileName.isNotEmpty
                  ? isVideo
                        // ── Video: show first-frame thumbnail ──
                        ? VideoThumbnail(
                            url: imageUrl,
                            title:
                                item['user_filename'] ??
                                item['file_name'] ??
                                'Video Preview',
                          )
                        // ── Image: load thumbnail via WebCompatImage (CORS-safe for Chrome) ──
                        : WebCompatImage(url: imageUrl, fit: BoxFit.cover)
                  : const Icon(
                      Icons.image_not_supported_rounded,
                      size: 22,
                      color: Colors.grey,
                    ),
            ),
          ),
        ),
        DataCell(
          Text(
            item['user_filename'] ?? "-",
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            item['description'] ?? "-",
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Text(() {
            final t = (item['type'] ?? item['group5'] ?? '-').toString();
            if (t == 'Short Term' || t == 'Temporary') return 'Temporary';
            return t;
          }(), style: const TextStyle(color: Colors.black87, fontSize: 12)),
        ),
        DataCell(
          Text(
            _formatDate(
              item['valid_from_date'] ??
                  item['from_date'] ??
                  item['valid_from'] ??
                  item['validfrom'] ??
                  item['date_from'],
              item['type'] ?? item['group5'],
              isFromDate: true,
            ),
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            _formatDate(
              item['valid_upto_date'] ??
                  item['to_date'] ??
                  item['valid_upto'] ??
                  item['upto_date'] ??
                  item['valid_to'] ??
                  item['date_to'] ??
                  item['validupto'],
              item['type'] ?? item['group5'],
              isFromDate: false,
            ),
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Builder(
            builder: (context) {
              final String rowKey = item['id']?.toString() ?? '';
              final bool isPending = _pendingToggle.contains(rowKey);
              final bool isActive =
                  item['file_status'] == 1 ||
                  item['file_status'] == "1" ||
                  item['status'] == 1 ||
                  item['status'] == "1";
              return SizedBox(
                width: 46,
                height: 28,
                child: isPending
                    // While API call is in-flight show a tiny spinner
                    ? Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        ),
                      )
                    : Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: isActive,
                          activeColor: Colors.green,
                          inactiveThumbColor: Colors.grey.shade400,
                          inactiveTrackColor: Colors.grey.shade300,
                          onChanged: (_) => toggleFileStatus(
                            item['id'],
                            item['file_status'] ?? item['status'],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => deleteFileAction(item['id']),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String hint,
    TextEditingController ctrl, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    String label = hint;
    if (label.toLowerCase().startsWith('enter the ')) {
      label = label.substring(10);
    } else if (label.toLowerCase().startsWith('enter ')) {
      label = label.substring(6);
    }
    if (label.isNotEmpty) {
      label = label[0].toUpperCase() + label.substring(1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
        ),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          onChanged: onChanged,
          validator: validator,
          // No field-level autovalidateMode — inherits from the parent Form
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            labelText: null,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFCBD5E1),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF334155),
                width: 1.6,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            helperText: ' ', // Reserve space so errors don't cause layout jump
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildNavBtn(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? Colors.blue.shade50 : Colors.grey.shade50,
        foregroundColor: enabled ? Colors.blue.shade800 : Colors.black26,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: enabled ? Colors.blue.shade100 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  DataColumn _buildCol(String label, int colIndex) {
    return DataColumn(
      label: InkWell(
        onTap: colIndex < 0
            ? null
            : () {
                setState(() {
                  if (_sortColumnIndex == colIndex) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortColumnIndex = colIndex;
                    _sortAscending = true;
                  }
                  currentPage = 1;
                });
              },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (colIndex >= 0) ...[
              const SizedBox(width: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    heightFactor: 0.4,
                    child: Icon(
                      Icons.arrow_drop_up,
                      size: 18,
                      color: _sortColumnIndex == colIndex && _sortAscending
                          ? Colors.blue
                          : Colors.grey.withOpacity(0.5),
                    ),
                  ),
                  Align(
                    heightFactor: 0.4,
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: _sortColumnIndex == colIndex && !_sortAscending
                          ? Colors.blue
                          : Colors.grey.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              "Show ",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            SizedBox(
              width: 75,
              height: 35,
              child: DropdownButtonFormField<String>(
                value: entriesValue,
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
                      entriesValue = v;
                      currentPage = 1;
                    });
                  }
                },
              ),
            ),
            const Text(
              " entries",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() {
                  searchQuery = v;
                  currentPage = 1;
                }),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: "Search files...",
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableFooter(List<dynamic> paged) {
    int total = _filteredList.length;
    int maxPages = (total / int.parse(entriesValue)).ceil();
    if (maxPages == 0) maxPages = 1;

    // Calculate current block of 4 pages
    int currentBlock = ((currentPage - 1) ~/ 4);
    int startPage = currentBlock * 4 + 1;
    int endPage = (startPage + 3) > maxPages ? maxPages : (startPage + 3);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing ${paged.length} out of $total entries",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.black54,
          ),
        ),
        Row(
          children: [
            _buildNavBtn(
              "Previous",
              enabled: currentPage > 1,
              onTap: () => setState(() {
                currentPage--;
              }),
            ),
            for (int i = startPage; i <= endPage; i++)
              _buildPageBtn(
                i.toString(),
                active: i == currentPage,
                onTap: () => setState(() => currentPage = i),
              ),
            _buildNavBtn(
              "Next",
              enabled: currentPage < maxPages,
              onTap: () => setState(() {
                currentPage++;
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPageBtn(String t, {bool active = false, VoidCallback? onTap}) {
    return Container(
      margin: EdgeInsets.zero,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? Colors.blue : Colors.white,
          foregroundColor: active ? Colors.white : Colors.black87,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          t,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller,
    BuildContext context, {
    VoidCallback? onDatePicked,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: true,
          validator: validator,
          // No field-level autovalidateMode — inherits from the parent Form.
          // This prevents the red error from firing while the date picker is open.
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            hintText: "YYYY-MM-DD",
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
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
              horizontal: 10,
              vertical: 10,
            ),
            helperText: ' ', // Reserve space so errors don't cause layout jump
          ),
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
            );
            if (picked != null) {
              controller.text =
                  "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
              if (onDatePicked != null) onDatePicked();
            }
          },
        ),
      ],
    );
  }
}
