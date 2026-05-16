import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../api_config.dart';

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

  // Table Pagination & Search
  String entriesValue = "10";
  int currentPage = 1;
  int? editingId;
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
        _showSnackBar("Department '$name' created.");
        _newDeptController.clear();
        await fetchDepartments();
      }
    } catch (e) {
      _showSnackBar("Failed to create department.");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 1: FETCH FILES (GET /fileview)
  // ──────────────────────────────────────────────────────────────────────────
 Future<void> fetchFilesFromServer() async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fileview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        final data = decoded['data'] ?? [];

        // ← DEBUG: print first item keys and values
        if (data.isNotEmpty) {
          debugPrint("=== FILEVIEW FIRST ITEM KEYS: ${data[0].keys.toList()}");
          debugPrint("=== FILEVIEW FIRST ITEM: ${data[0]}");
        }

        setState(() {
          fileList = data;
        });
      }
    } catch (e) {
      _showSnackBar("Connectivity Error: Unable to sync with repository.");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
  // ──────────────────────────────────────────────────────────────────────────
  // API 2: INSERT FILE (POST /insertFileview) — plain JSON POST
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> insertFileAction() async {
    if (!_formKey.currentState!.validate() || _selectedFile == null) {
      if (_selectedFile == null) {
        _showSnackBar("Please pick a file to upload.");
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => isSubmitting = true);
    // DISMISS IMMEDIATELY TO AVOID LATENCY
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/insertFileview'),
      );
      request.fields['api_key'] = _apiKey;
      request.fields['category_id'] = _selectedDeptId!;
      request.fields['name'] = _nameController.text.trim();
      request.fields['desc'] = _descController.text.trim();
      request.fields['group5'] = _selectedType == "Short Term"
          ? "Temporary"
          : _selectedType;
      request.fields['file_duration'] = '25';

      if (_selectedType == "Short Term") {
        // Short Term / Temporary → send both from and to dates
        request.fields['valid_from_date'] = _fromDateController.text;
        request.fields['valid_upto_date'] = _toDateController.text;
        request.fields['from_date'] = _fromDateController.text;
        request.fields['to_date'] = _toDateController.text;
        request.fields['valid_from'] = _fromDateController.text;
        request.fields['valid_upto'] = _toDateController.text;
      } else {
        // Permanent → send today's date as valid_from, no valid_upto
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        request.fields['valid_from_date'] = today;
        request.fields['from_date'] = today;
        request.fields['valid_from'] = today;
      }

      String filename = _selectedFile!.name;
      String extension = filename.split('.').last.toLowerCase();
      MediaType? contentType;

      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        contentType = MediaType(
          'image',
          extension == 'jpg' ? 'jpeg' : extension,
        );
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(extension)) {
        contentType = MediaType('video', extension);
      }

      if (_selectedFile!.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _selectedFile!.bytes!,
            filename: filename,
            contentType: contentType,
          ),
        );
      } else if (_selectedFile!.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            _selectedFile!.path!,
            filename: filename,
            contentType: contentType,
          ),
        );
      }

      // REMOVED: Moved to start for zero latency
      // if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint("Insert response [${response.statusCode}]: ${response.body}");

      if (response.statusCode == 200) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text("File uploaded successfully."),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _resetForm();
        await fetchFilesFromServer(); // Refresh immediately
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Upload Error: ${response.statusCode}"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Insert failed: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
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
          _dialogAutoValidate = AutovalidateMode.disabled; // Reset validation mode
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
    final messenger = ScaffoldMessenger.of(context);
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Record updated successfully."),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _resetForm();
        fetchFilesFromServer();
      }
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Update Error."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 5: STATUS TOGGLE (POST /fileStatusUpdateview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> toggleFileStatus(dynamic id, dynamic currentStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final int newStatus = (currentStatus == 1 || currentStatus == "1")
          ? 0
          : 1;
      final response = await http.post(
        Uri.parse('$_baseUrl/fileStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id, "status": newStatus}),
      );
      if (response.statusCode == 200) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 1 ? "File activated." : "File deactivated.",
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await fetchFilesFromServer();
      }
    } catch (e) {
      debugPrint("Status Shift Error: $e");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 6: DELETE RECORD (POST /deleteFileview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> deleteFileAction(dynamic id) async {
    final messenger = ScaffoldMessenger.of(context);

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
        messenger.showSnackBar(
          const SnackBar(
            content: Text("File deleted successfully."),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Sync with server to be safe, but UI is already updated
        fetchFilesFromServer();
      } else {
        // Rollback if failed
        if (deletedItem != null && deletedIndex != -1) {
          setState(() {
            fileList.insert(deletedIndex, deletedItem);
          });
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Delete failed."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Rollback if error
      if (deletedItem != null && deletedIndex != -1) {
        setState(() {
          fileList.insert(deletedIndex, deletedItem);
        });
      }
      _showSnackBar("Delete Protocol Failed.");
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _selectedFileName = result.files.first.name;
      });
    }
  }

  void _showSnackBar(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  List<dynamic> get _filteredList {
    String query = _searchController.text.toLowerCase();
    List<dynamic> sorted = List.from(fileList);
    // Descending Sort (Latest First)
    sorted.sort(
      (a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(
        int.tryParse(a['id'].toString()) ?? 0,
      ),
    );

    if (query.isEmpty) return sorted;
    return sorted.where((item) {
      final fileName = (item['user_filename'] ?? '').toString().toLowerCase();
      final desc = (item['description'] ?? '').toString().toLowerCase();
      return fileName.contains(query) || desc.contains(query);
    }).toList();
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
      maxWidth: 340,
      builder: (ctx, setPopupState) {
        return Form(
          key: dialogFormKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.center, // ← changed from start
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
                        padding: const EdgeInsets.only(
                          bottom: 20,
                        ), // ← pushes down to align with dropdown
                        child: InkWell(
                          onTap: _showAddDepartmentPopup,
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
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
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: "From Date",
                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    suffixIcon: const Icon(Icons.calendar_today_rounded, size: 15),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: "To Date",
                    hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    suffixIcon: const Icon(Icons.calendar_today_rounded, size: 15),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    return Scaffold(
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
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13.0,
              ),
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
                    _buildCol('ID'),
                    _buildCol('IMG/VID'),
                    _buildCol('FILE NAME'),
                    _buildCol('DESCRIPTION'),
                    _buildCol('TYPE'),
                    _buildCol('VALID FROM'),
                    _buildCol('VALID UPTO'),
                    _buildCol('STATUS'),
                    _buildCol('DELETE'),
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

  DataRow _getRow(dynamic item) {
    // ← DEBUG: print every item to see exact field names
    debugPrint("=== ROW ITEM: $item");
    
    return DataRow(
      cells: [
        DataCell(
          Text(
            item['id']?.toString() ?? "-",
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Container(
            width: 60,
            height: 60,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              color: Colors.grey.shade100,
            ),
            child: (item['file_name'] != null &&
                    item['file_name'].toString().trim().isNotEmpty)
                ? (['mp4', 'mov', 'avi', 'mkv'].contains(
                        item['file_name']
                            .toString()
                            .split('.')
                            .last
                            .toLowerCase(),
                      ))
                    ? const Icon(
                        Icons.movie,
                        size: 24,
                        color: Colors.blueGrey,
                      )
                    : Image.network(
                        "$_baseUrl/uploads/${item['file_name']}",
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.broken_image,
                          size: 20,
                          color: Colors.grey,
                        ),
                      )
                : const Icon(Icons.image, size: 20, color: Colors.grey),
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
          Text(
            () {
              final t = (item['type'] ?? item['group5'] ?? '-').toString();
              if (t == 'Short Term' || t == 'Temporary') return 'Temporary';
              return t;
            }(),
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
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
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: item['file_status'] == 1 || item['file_status'] == "1",
              activeColor: Colors.green,
              onChanged: (v) =>
                  toggleFileStatus(item['id'], item['file_status']),
            ),
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
    return TextFormField(
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
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
        ),
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        helperText: ' ', // Reserve space so errors don't cause layout jump
        alignLabelWithHint: true,
      ),
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

  DataColumn _buildCol(String label) {
    return DataColumn(
      label: Text(
        label,
        style: TextStyle(
          color: Colors.blue.shade800,
          fontWeight: FontWeight.bold,
          fontSize: 11,
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
        SizedBox(
          width: 250,
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
      ],
    );
  }

  Widget _buildTableFooter(List<dynamic> paged) {
    int total = _filteredList.length;
    int maxPages = (total / int.parse(entriesValue)).ceil();
    if (maxPages == 0) maxPages = 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing ${paged.length} of $total records",
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
              onTap: () => setState(() => currentPage--),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                "Page $currentPage of $maxPages",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            _buildNavBtn(
              "Next",
              enabled: currentPage < maxPages,
              onTap: () => setState(() => currentPage++),
            ),
          ],
        ),
      ],
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
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w500,
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
