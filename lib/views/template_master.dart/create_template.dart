import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

/**
 * CreateTemplateView Master Module
 * * This module handles the administrative lifecycle of digital templates.
 * Headings: TEMPLATE NAME, EDIT, ACTION (Delete/Status Toggle).
 * Key Fix: Maps 'temp_name' from the backend API response to the table.
 */
class CreateTemplateView extends StatefulWidget {
  const CreateTemplateView({super.key});

  @override
  State<CreateTemplateView> createState() => _CreateTemplateViewState();
}

class _CreateTemplateViewState extends State<CreateTemplateView> {
  // ─── API CONFIGURATION ───────────────────────────────────────────────────
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  String get _baseUrl => getBaseUrl();

  // ─── STATE PROPERTIES ────────────────────────────────────────────────────
  List<dynamic> templateList = [];
  bool isLoading = true;
  bool isSubmitting = false;
  int? editingId; // Track if we are updating an existing record
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Table Configuration
  String entriesValue = "10";
  int currentPage = 1;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  
  // Sorting State
  int _sortColumnIndex = -1;
  bool _sortAscending = false;

  // Form Controller
  final TextEditingController _templateNameController = TextEditingController();

  // ─── LIFECYCLE ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initializeData();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
          currentPage = 1;
        });
      }
    });
  }

  Future<void> _initializeData() async {
    await fetchTemplatesFromServer();
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // API INTEGRATION SERVICES
  // ─────────────────────────────────────────────────────────────────────────

  // API 1: FETCH DATA (Mapping temp_name correctly)
  Future<void> fetchTemplatesFromServer() async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> data = decoded['data'] ?? [];

        // Sorting: Latest IDs first
        data.sort(
          (a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(
            int.tryParse(a['id'].toString()) ?? 0,
          ),
        );

        setState(() {
          templateList = data;
          isLoading = false;
        });
      }
    } catch (e) {
      _showSnackBar("Fetch Error: Connection to cloud repository failed.");
      setState(() => isLoading = false);
    }
  }

  // API 2: INSERT DATA
  Future<void> insertTemplateAction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);
    // DISMISS NOW HANDLED IN BUTTON PRESS

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/insertNew_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "template_name": _templateNameController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar("Template submitted successfully.");
        _templateNameController.clear();
        await fetchTemplatesFromServer();
      }
    } catch (e) {
      _showSnackBar("Insertion Protocol Failed.");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // EDIT: Load data directly from the table row item (no API call needed)
  void loadTemplateForEdit(dynamic item) {
    setState(() {
      editingId = int.tryParse(item['id'].toString());
      _templateNameController.text =
          item['temp_name'] ?? item['template_name'] ?? "";
    });
    _showTemplateDialog();
  }

  // API 4: UPDATE DATA
  Future<void> updateTemplateAction() async {
    if (editingId == null || !_formKey.currentState!.validate()) return;
    setState(() => isSubmitting = true);
    // DISMISS NOW HANDLED IN BUTTON PRESS

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "id": editingId,
          "template_name": _templateNameController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar("Template updated successfully.");
        _templateNameController.clear();
        setState(() => editingId = null);
        await fetchTemplatesFromServer();
      }
    } catch (e) {
      _showSnackBar("Update execution failed.");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // API 5: STATUS UPDATE (optimistic local update — no full refetch to avoid blink)
  Future<void> toggleStatus(dynamic id, dynamic current) async {
    final int next = (current == 1) ? 0 : 1;
    final int idx = templateList.indexWhere(
      (item) => item['id'].toString() == id.toString(),
    );
    if (idx == -1) return;

    // Optimistically update the local list immediately (no blink)
    setState(() {
      templateList[idx] = Map<String, dynamic>.from(templateList[idx])
        ..['status'] = next;
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id, "status": next}),
      );
      if (response.statusCode != 200) {
        // Revert on failure
        setState(() {
          templateList[idx] = Map<String, dynamic>.from(templateList[idx])
            ..['status'] = current;
        });
        _showSnackBar("Status update failed. Reverted.");
      }
    } catch (e) {
      // Revert on error
      setState(() {
        templateList[idx] = Map<String, dynamic>.from(templateList[idx])
          ..['status'] = current;
      });
      debugPrint("Status toggle fail: $e");
    }
  }

  // API 6: DELETE
  Future<void> deleteTemplateAction(dynamic id) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/deleteNew_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id}),
      );
      if (response.statusCode == 200) {
        _showSnackBar("Template removed from system.");
        fetchTemplatesFromServer();
      }
    } catch (e) {
      _showSnackBar("Deletion protocol failed.");
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  void _showSnackBar(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<dynamic> get _filteredList {
    List<dynamic> filtered = List.from(templateList);
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        return (item['temp_name'] ?? '').toString().toLowerCase().contains(
          _searchQuery,
        );
      }).toList();
    }
    
    filtered.sort((a, b) {
      String aVal = "";
      String bVal = "";
      
      switch (_sortColumnIndex) {
        case 0:
          aVal = a['temp_name']?.toString() ?? a['template_name']?.toString() ?? "";
          bVal = b['temp_name']?.toString() ?? b['template_name']?.toString() ?? "";
          break;
        default:
          aVal = a['id']?.toString() ?? "";
          bVal = b['id']?.toString() ?? "";
          break;
      }
      
      if (_sortColumnIndex == -1) {
        int idA = int.tryParse(aVal) ?? 0;
        int idB = int.tryParse(bVal) ?? 0;
        return _sortAscending ? idA.compareTo(idB) : idB.compareTo(idA);
      }
      
      return _sortAscending
          ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
          : bVal.toLowerCase().compareTo(aVal.toLowerCase());
    });
    return filtered;
  }

  List<dynamic> get _pagedList {
    final per = int.tryParse(entriesValue) ?? 10;
    final filtered = _filteredList;
    final start = (currentPage - 1) * per;
    if (start >= filtered.length) return [];
    return filtered.sublist(start, (start + per).clamp(0, filtered.length));
  }

  // ─── POPUP DIALOG FOR TEMPLATE ───────────────────────────────────────────
 void _showTemplateDialog() {
   StylishDialog.show(
  context: context,
  title: editingId == null ? "Create New Template" : "Edit Template",
  subtitle: "Define the template layout",
  subtitleStyle: const TextStyle(
    fontSize: 12,
    color: Color(0xFFCBD5E1),
  ),
  icon: editingId == null
      ? Icons.dashboard_customize_rounded
      : Icons.edit_note_rounded,
  width: 430,
  child: Form(
    key: _formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Column(
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
          controller: _templateNameController,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter the template name';
            if (!RegExp(r'^[a-zA-Z0-9\s\-_]+$').hasMatch(v.trim())) {
              return 'Only letters, numbers, and basic special chars allowed';
            }
            return null;
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter the template name',
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.shade400,
                width: 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Color(0xFF0F172A),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red, width: 1.0),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
          ),
        ),
      ],
    ),
    ),
    actions: [
        TextButton(
          onPressed: () {
            setState(() {
              editingId = null;
              _templateNameController.clear();
            });
            Navigator.pop(context);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
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
            onPressed: isSubmitting
              ? null
              : () async {
                  if (_formKey.currentState!.validate()) {
                    Navigator.pop(context);
                    if (editingId == null) {
                      await insertTemplateAction();
                    } else {
                      await updateTemplateAction();
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  editingId == null ? 'Submit' : 'Update',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
        ),
      ],
    );
  }
  // ─── UI BUILDER ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SelectionArea(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const AnimatedHeading(
                  text: "Templates List",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      editingId = null;
                      _templateNameController.clear();
                    });
                    _showTemplateDialog();
                  },
                  icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
                  label: const Text(
                    "CREATE TEMPLATE",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

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
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildListHeader(),
                    const SizedBox(height: 15),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : (templateList.isNotEmpty && _filteredList.isEmpty)
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_off_rounded,
                                          size: 48,
                                          color: Colors.blue.shade200,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          "No matching templates found",
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
                                      ],
                                    ),
                                  )
                                : _buildDataTable(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildPaginationControls(),
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

  Widget _buildDataTable() {
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
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                border: TableBorder.all(color: Colors.grey.shade100),
                columns: [
                  _buildCol('TEMPLATE NAME', 0),
                  _buildCol('EDIT', -1),
                  _buildCol('ACTION', -1),
                ],
                rows: _pagedList.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          item['temp_name'] ?? "-",
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => loadTemplateForEdit(item),
                          hoverColor: Colors.blue.withOpacity(0.1),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            Transform.scale(
                              scale: 0.7,
                              child: Switch(
                                value: item['status'] == 1,
                                activeColor: Colors.green,
                                onChanged: (v) =>
                                    toggleStatus(item['id'], item['status']),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  DataColumn _buildCol(String label, int colIndex) {
    return DataColumn(
      label: InkWell(
        onTap: colIndex < 0 ? null : () {
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
                  fontSize: 12,
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

 Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              "Show ",
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.bold,
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
                onChanged: (v) => setState(() {
                  entriesValue = v!;
                  currentPage = 1;
                }),
              ),
            ),
            const Text(
              " entries",
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(
          width: 250,
          height: 40,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.black87, fontSize: 12),
            decoration: InputDecoration(
              hintText: "Search templates...",
              hintStyle: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
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

  Widget _buildPaginationControls() {
    int total = _filteredList.length;
    int totalPages = (total / int.parse(entriesValue)).ceil();
    if (totalPages == 0) totalPages = 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing ${_pagedList.length} of $total records",
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
        Row(
          children: [
            _buildPageBtn(
              "Previous",
              enabled: currentPage > 1,
              onTap: () => setState(() => currentPage--),
            ),
            ..._buildPageNumberButtons(totalPages),
            _buildPageBtn(
              "Next",
              enabled: currentPage < totalPages,
              onTap: () => setState(() => currentPage++),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildPageNumberButtons(int totalPages) {
    List<Widget> widgets = [];
    if (totalPages <= 1) {
      return [_buildPageBtn("1", enabled: false, onTap: () {}, isActive: true)];
    }
    for (int i = 1; i <= totalPages; i++) {
      if (i == 1 ||
          i == totalPages ||
          (i >= currentPage - 1 && i <= currentPage + 1)) {
        widgets.add(
          _buildPageBtn(
            "$i",
            enabled: true,
            onTap: () => setState(() => currentPage = i),
            isActive: currentPage == i,
          ),
        );
      } else if (i == currentPage - 2 || i == currentPage + 2) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              "...",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildPageBtn(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label.length > 2 ? 12 : 8,
            vertical: 8,
          ),
          constraints: const BoxConstraints(minWidth: 34),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.blue
                : (enabled ? Colors.white : Colors.grey.shade50),
            border: Border.all(
              color: isActive ? Colors.blue : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.zero,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : (enabled ? Colors.black87 : Colors.black26),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
