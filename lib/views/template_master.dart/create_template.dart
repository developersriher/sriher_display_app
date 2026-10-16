import 'dart:ui';
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
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

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
    _hScroll.dispose();
    _vScroll.dispose();
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
        data.sort((a, b) {
          final aId = int.tryParse((a is Map ? (a['id'] ?? a['ID']) : null)?.toString() ?? '0') ?? 0;
          final bId = int.tryParse((b is Map ? (b['id'] ?? b['ID']) : null)?.toString() ?? '0') ?? 0;
          return bId.compareTo(aId);
        });

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
        setState(() {
          currentPage = 1;
          _sortColumnIndex = -1;
          _sortAscending = false;
        });
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

  bool _isItemActive(dynamic item) {
    if (item == null) return true;
    final raw = (item is Map)
        ? (item['status'] ?? item['active_status'] ?? 0)
        : item;
    if (raw == null) return true;
    if (raw == 0 || raw == false) return true;
    if (raw == 1 || raw == true) return false;
    final str = raw.toString().trim().toLowerCase();
    if (str == '0' ||
        str == 'active' ||
        str == 'true' ||
        str == 'enabled' ||
        str == 'on')
      return true;
    if (str == '1' ||
        str == 'inactive' ||
        str == 'false' ||
        str == 'disabled' ||
        str == 'off')
      return false;
    final intVal = int.tryParse(str);
    if (intVal != null) return intVal == 0;
    return true;
  }

  // API 5: STATUS UPDATE
  Future<void> toggleStatus(dynamic itemOrId, [dynamic currentStatus]) async {
    Map<String, dynamic> itemMap = {};
    dynamic id = itemOrId;
    if (itemOrId is Map) {
      itemMap = Map<String, dynamic>.from(itemOrId);
      id = itemMap['id'];
    }

    final int idx = templateList.indexWhere(
      (item) => item['id'].toString() == id.toString(),
    );
    if (idx != -1 && itemMap.isEmpty) {
      itemMap = Map<String, dynamic>.from(templateList[idx]);
    }

    final bool currentlyActive = _isItemActive(
      itemMap.isNotEmpty ? itemMap : currentStatus,
    );
    final int nextStatus = currentlyActive ? 1 : 0;
    final dynamic oldStatus =
        itemMap['status'] ?? currentStatus ?? (currentlyActive ? 0 : 1);

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirm Action", textAlign: TextAlign.center),
          content: Text(
            currentlyActive
                ? "Do you want to set this item as inactive?"
                : "Do you want to set this item as active?",
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    if (idx != -1) {
      setState(() {
        templateList[idx] = Map<String, dynamic>.from(templateList[idx])
          ..['status'] = nextStatus
          ..['active_status'] = nextStatus;
      });
    }

    try {
      final Map<String, dynamic> payload = Map<String, dynamic>.from(itemMap);
      payload['api_key'] = _apiKey;
      payload['id'] = id;
      payload['status'] = nextStatus;

      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextStatus == 0
                ? "Template has been successfully activated."
                : "Template has been successfully deactivated."),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        fetchTemplatesFromServer();
      } else {
        if (idx != -1 && mounted) {
          setState(() {
            templateList[idx] = Map<String, dynamic>.from(templateList[idx])
              ..['status'] = oldStatus
              ..['active_status'] = oldStatus;
          });
        }
        _showSnackBar("Status update failed (${response.statusCode}).");
      }
    } catch (e) {
      if (idx != -1 && mounted) {
        setState(() {
          templateList[idx] = Map<String, dynamic>.from(templateList[idx])
            ..['status'] = oldStatus
            ..['active_status'] = oldStatus;
        });
      }
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
          aVal =
              a['temp_name']?.toString() ??
              a['template_name']?.toString() ??
              "";
          bVal =
              b['temp_name']?.toString() ??
              b['template_name']?.toString() ??
              "";
          break;
        default:
          aVal = a['id']?.toString() ?? "";
          bVal = b['id']?.toString() ?? "";
          break;
      }

      if (_sortColumnIndex == -1) {
        int idA = int.tryParse((a is Map ? (a['id'] ?? a['ID']) : null)?.toString() ?? '0') ?? 0;
        int idB = int.tryParse((b is Map ? (b['id'] ?? b['ID']) : null)?.toString() ?? '0') ?? 0;
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Create New Template" : "Edit Template",
      titleStyle: TextStyle(
        fontSize: isMobile ? 15 : 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      subtitle: "Define the template layout",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      icon: editingId == null
          ? Icons.dashboard_customize_rounded
          : Icons.edit_note_rounded,
      width: isMobile ? screenWidth * 0.9 : 450,
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
                final clean = v.trim().toLowerCase();
                final exists = templateList.any((t) {
                  final name = (t['temp_name'] ?? t['template_name'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
                  final id = t['id'] ?? t['ID'];
                  if (editingId != null &&
                      id?.toString() == editingId?.toString())
                    return false;
                  return name == clean;
                });
                if (exists) return 'This template name already exists.';
                return null;
              },
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                errorStyle: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
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
                  borderSide: BorderSide(color: Color(0xFF0F172A), width: 1.5),
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
              borderRadius: BorderRadius.circular(8),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1000;

    final heading = const AnimatedHeading(
      text: "Templates List",
      style: TextStyle(
        color: Color.fromARGB(255, 33, 150, 243),
        fontWeight: FontWeight.bold,
        fontSize: 22,
      ),
    );

    final createBtn = ElevatedButton.icon(
      onPressed: () {
        setState(() {
          editingId = null;
          _templateNameController.clear();
        });
        _showTemplateDialog();
      },
      icon: Icon(Icons.dashboard_customize_rounded, size: isMobile ? 14 : 20),
      style: isMobile
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(80, 32),
            )
          : null,
      label: Text(
        "CREATE TEMPLATE",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isMobile ? 10 : 12,
        ),
      ),
    );

    final bodyContent = Padding(
      padding: EdgeInsets.all(isMobile ? 6.0 : 16.0),
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
        padding: EdgeInsets.all(isMobile ? 10.0 : 16.0),
        child: Column(
          mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // ── Responsive heading row ──
            isMobile
                ? Align(alignment: Alignment.center, child: heading)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [heading, createBtn],
                  ),
            const SizedBox(height: 20),
            _buildListHeader(isMobile: isMobile, createBtn: createBtn),
            const SizedBox(height: 15),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 300),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1.0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
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
            _buildPaginationControls(isMobile: isMobile),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SelectionArea(
        child: Scrollbar(
          controller: _vScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _vScroll,
            child: bodyContent,
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    // ── Table header ──────────────────────────────────────────────────────────
    final header = Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // S.NO – flex 1, left
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: const Text(
                  'S/NO',
                  style: TextStyle(
                    color: Color.fromRGBO(33, 150, 243, 1),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          // TEMPLATE NAME – flex 5, left
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TEMPLATE NAME',
                      style: TextStyle(
                        color: Color.fromRGBO(33, 150, 243, 1),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 0;
                            _sortAscending = true;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(
                              Icons.arrow_drop_up,
                              size: 14,
                              color: _sortColumnIndex == 0 && _sortAscending
                                  ? Colors.blue
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 0;
                            _sortAscending = false;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(
                              Icons.arrow_drop_down,
                              size: 14,
                              color: _sortColumnIndex == 0 && !_sortAscending
                                  ? Colors.blue
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // EDIT – flex 2, left
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                'EDIT',
                style: TextStyle(
                  color: Color.fromRGBO(33, 150, 243, 1),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          // ACTION – flex 2, right
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: const Text(
                  'ACTION',
                  style: TextStyle(
                    color: Color.fromRGBO(33, 150, 243, 1),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // ── Empty state ───────────────────────────────────────────────────────────
    if (_pagedList.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200, width: 1.0),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double minW = constraints.maxWidth > 1000 ? constraints.maxWidth : 1000.0;
          return Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minW, maxWidth: minW),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
          children: [
            header,
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36.0),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 36, color: Colors.blue.shade200),
                  const SizedBox(height: 8),
                  Text(
                    'No matching templates found',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Try a different search term',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  ],
                ),
              ),
            ],
                ),
              ),
            ),
          );
        },
      ),
    );
    }

    // ── Data rows ─────────────────────────────────────────────────────────────
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double minW = constraints.maxWidth > 1000 ? constraints.maxWidth : 1000.0;
          return Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minW, maxWidth: minW),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
        children: [
          header,
          ..._pagedList.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final sNo = ((currentPage - 1) * (int.tryParse(entriesValue) ?? 10)) + index + 1;
            return Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  // S.NO cell – flex 1
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Text(
                          sNo.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  // TEMPLATE NAME cell – flex 5
                  Expanded(
                    flex: 5,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          item['temp_name'] ?? '-',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  // EDIT cell – flex 2
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                        onPressed: () => loadTemplateForEdit(item),
                        tooltip: 'Edit',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ),
                  // ACTION cell – flex 2, right-aligned
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Transform.scale(
                          scale: 0.7,
                          child: Switch(
                            value: _isItemActive(item),
                            activeColor: Colors.green,
                            inactiveThumbColor: Colors.grey.shade400,
                            inactiveTrackColor: Colors.grey.shade300,
                            onChanged: (v) => toggleStatus(item),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListHeader({bool isMobile = false, Widget? createBtn}) {
    final showEntries = Row(
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
        const SizedBox(width: 6),
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
            items: [
              "10",
              "25",
              "50",
              "100",
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() {
              entriesValue = v!;
              currentPage = 1;
            }),
          ),
        ),
        if (!isMobile) ...[
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
    );

    final searchBox = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isMobile ? 180 : 250),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.black87, fontSize: 12),
          decoration: InputDecoration(
            hintText: "Search templates...",
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
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
    );

    return isMobile
        ? SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (createBtn != null) createBtn,
                const SizedBox(height: 10),
                showEntries,
                const SizedBox(height: 10),
                searchBox,
              ],
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [showEntries, searchBox],
          );
  }

  Widget _buildPaginationControls({bool isMobile = false}) {
    int total = _filteredList.length;
    int totalPages = (total / int.parse(entriesValue)).ceil();
    if (totalPages == 0) totalPages = 1;
    final int limit = int.parse(entriesValue);
    final int start = (currentPage - 1) * limit + 1;
    final int end = (start + _pagedList.length - 1).clamp(0, total);

    final showingText = Text(
      "Showing ${total == 0 ? 0 : start} to $end of $total entries",
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.black54,
      ),
    );

    final pagination = Row(
      mainAxisSize: MainAxisSize.min,
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
    );

    return isMobile
        ? SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [showingText, const SizedBox(height: 10), pagination],
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [showingText, pagination],
          );
  }

  /// Builds a strict sliding window of at most 3 page-number buttons.
  /// The window is centered around [currentPage] and slides automatically
  /// when the user clicks the last visible button (i.e., 3rd item).
  /// No ellipsis — the max visible count is always ≤ 3.
  List<Widget> _buildPageNumberButtons(int totalPages) {
    // ── Strict max-3 sliding window ─────────────────────────────────────────
    // The window always shows exactly min(3, totalPages) consecutive buttons.
    // It slides so that [currentPage] is always inside the window.
    // No ellipsis, no extra numbers — just 1–3 clean page-number boxes.
    final visibleCount = totalPages.clamp(1, 3); // never more than 3

    // Ideal window: center currentPage. Start = currentPage - 1 (0-based offset).
    int windowStart = currentPage - 1; // try to put currentPage in middle slot

    // Clamp so the window doesn't go below page 1
    if (windowStart < 1) windowStart = 1;
    // Clamp so the window doesn't exceed totalPages on the right
    if (windowStart + visibleCount - 1 > totalPages) {
      windowStart = totalPages - visibleCount + 1;
    }

    List<Widget> widgets = [];
    for (int i = windowStart; i < windowStart + visibleCount; i++) {
      final pageNum = i; // capture for closure
      widgets.add(
        _buildPageBtn(
          "$pageNum",
          enabled: true,
          onTap: () => setState(() => currentPage = pageNum),
          isActive: currentPage == pageNum,
        ),
      );
    }
    return widgets;
  }

  Widget _buildPageBtn(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
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
    );
  }
}
