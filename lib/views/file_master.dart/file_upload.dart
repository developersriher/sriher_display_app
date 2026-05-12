import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';

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
  final String _baseUrl = "https://display.sriher.com";

  // ──────────────────────────────────────────────────────────────────────────
  List<dynamic> fileList = [];
  List<dynamic> _deptList = []; // loaded from /categoryview
  bool isLoading = true;
  bool isSubmitting = false;

  // Table Pagination & Search
  String entriesValue = "10";
  int currentPage = 1;
  int? editingId;

  // Form Selections
  String _selectedType = "Permanent";
  String? _selectedDeptId;
  String? _selectedFileName;
  PlatformFile? _selectedFile;
  String searchQuery = "";

  // ──────────────────────────────────────────────────────────────────────────
  // TEXT CONTROLLERS
  // ──────────────────────────────────────────────────────────────────────────
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

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
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 0: FETCH DEPARTMENTS from /categoryview
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> fetchDepartments() async {
    try {
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
        setState(() {
          fileList = decoded['data'] ?? [];
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
    if (_selectedDeptId == null || _nameController.text.trim().isEmpty || _selectedFile == null) {
      _showSnackBar("Please select a Department, enter a File Name, and pick a File.");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/insertFileview'));
      request.fields['api_key'] = _apiKey;
      request.fields['category_id'] = _selectedDeptId!;
      request.fields['name'] = _nameController.text.trim();
      request.fields['desc'] = _descController.text.trim();
      request.fields['group5'] = _selectedType;
      request.fields['file_duration'] = '25';

      String filename = _selectedFile!.name;
      String extension = filename.split('.').last.toLowerCase();
      MediaType? contentType;
      
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        contentType = MediaType('image', extension == 'jpg' ? 'jpeg' : extension);
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(extension)) {
        contentType = MediaType('video', extension);
      }

      if (_selectedFile!.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          _selectedFile!.bytes!, 
          filename: filename,
          contentType: contentType,
        ));
      } else if (_selectedFile!.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file', 
          _selectedFile!.path!,
          filename: filename,
          contentType: contentType,
        ));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint("Insert response [${response.statusCode}]: ${response.body}");

      if (response.statusCode == 200) {
        _showSnackBar("File saved successfully.");
        _resetForm();
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      } else {
        _showSnackBar("Server error ${response.statusCode}: ${response.body}");
      }
      // Always refresh so latest entry shows at top
      await fetchFilesFromServer();
    } catch (e) {
      _showSnackBar("Insert failed: $e");
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
          // group5 is the type field used by insert/update APIs
          _selectedType =
              data['group5']?.toString() ??
              data['type']?.toString() ??
              'Permanent';
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
      final response = await http.post(
        Uri.parse('$_baseUrl/fileUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "id": editingId,
          "category_id": _selectedDeptId,
          "name": _nameController.text.trim(),
          "desc": _descController.text.trim(),
          "group5": _selectedType,
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar("Record metadata updated successfully.");
        _resetForm();
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        fetchFilesFromServer();
      }
    } catch (e) {
      _showSnackBar("Update Error.");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 5: STATUS TOGGLE (POST /fileStatusUpdateview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> toggleFileStatus(dynamic id, dynamic currentStatus) async {
    try {
      final int newStatus = (currentStatus == 1 || currentStatus == "1")
          ? 0
          : 1;
      final response = await http.post(
        Uri.parse('$_baseUrl/fileStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id, "status": newStatus}),
      );
      if (response.statusCode == 200) fetchFilesFromServer();
    } catch (e) {
      debugPrint("Status Shift Error: $e");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API 6: DELETE RECORD (POST /deleteFileview)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> deleteFileAction(dynamic id) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/deleteFileview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id}),
      );
      if (response.statusCode == 200) {
        _showSnackBar("Record purged from repository.");
        fetchFilesFromServer();
      }
    } catch (e) {
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
    });
    _nameController.clear();
    _descController.clear();
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
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Upload File" : "Edit File",
      subtitle: "Add or manage media assets for display",
      icon: editingId == null
          ? Icons.cloud_upload_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.6,
      builder: (context, setDialogState) =>
          _buildFormCardInDialog(setDialogState),
    );
  }

  Widget _buildFormCardInDialog(StateSetter setDialogState) {
    return Column(
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
                  DropdownButtonFormField<String>(
                    value: _selectedDeptId,
                    hint: const Text(
                      "Select Department Name",
                      style: TextStyle(color: Colors.black45),
                    ),
                    dropdownColor: Colors.white,
                    menuMaxHeight: 200,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.blue.shade400,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                    items: _deptList.map<DropdownMenuItem<String>>((dept) {
                      return DropdownMenuItem<String>(
                        value: dept['id']?.toString(),
                        child: Text(
                          dept['category_name']?.toString() ?? '-',
                          style: const TextStyle(color: Colors.black87),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setDialogState(() => _selectedDeptId = val),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade100,
                          foregroundColor: Colors.blue.shade900,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        onPressed: () async {
                          await _pickFile();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.upload_file),
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
                  _buildTextField("Enter reference name", _nameController),
                  const SizedBox(height: 20),
                  _buildTextField("Short description", _descController),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        Row(
          children: [
            const Text(
              "Type: ",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Radio<String>(
              value: "Permanent",
              groupValue: _selectedType,
              activeColor: Colors.blue,
              onChanged: (v) => setDialogState(() => _selectedType = v!),
            ),
            const Text("Permanent", style: TextStyle(color: Colors.black87)),
            const SizedBox(width: 10),
            Radio<String>(
              value: "Short Term",
              groupValue: _selectedType,
              activeColor: Colors.blue,
              onChanged: (v) => setDialogState(() => _selectedType = v!),
            ),
            const Text("Short Term", style: TextStyle(color: Colors.black87)),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  _resetForm();
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : (editingId == null ? insertFileAction : updateFileAction),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        editingId == null ? "Save Asset" : "Update Asset",
                        style: const TextStyle(fontWeight: FontWeight.w900),
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
      body: Padding(
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
                  onPressed: _showUploadDialog,
                  icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                  label: const Text(
                    "UPLOAD FILE",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
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
                  _buildCol('EDIT'),
                  _buildCol('DELETE'),
                ],
                rows: data.map((item) => _getRow(item)).toList(),
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

  DataRow _getRow(dynamic item) {
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
                    item['file_name'].toString().split('.').last.toLowerCase()))
                    ? const Icon(Icons.movie, size: 24, color: Colors.blueGrey)
                    : Image.network(
                        "$_baseUrl/uploads/${item['file_name']}",
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(
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
            item['type'] ?? "-",
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            item['valid_from_date'] ?? "-",
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            item['valid_upto_date'] ?? "-",
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
            icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
            onPressed: () => editFileDetails(item['id']),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
            onPressed: () => deleteFileAction(item['id']),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Colors.black54),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
        ),
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
              width: 70,
              height: 35,
              child: DropdownButtonFormField<String>(
                value: entriesValue,
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
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
                items: ["10", "25", "50"]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() {
                  entriesValue = v!;
                  currentPage = 1;
                }),
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
}
