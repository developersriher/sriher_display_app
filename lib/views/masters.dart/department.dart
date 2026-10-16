import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../api_config.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';

class DepartmentView extends StatefulWidget {
  const DepartmentView({super.key});

  @override
  State<DepartmentView> createState() => _DepartmentViewState();
}

class _DepartmentViewState extends State<DepartmentView> {
  // --- API CONFIGURATION ---
  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  // --- STATE MANAGEMENT ---
  List<dynamic> categoryList = [];
  List<dynamic> filteredList = [];
  bool isLoading = true;
  bool isSubmitting = false;
  String entriesValue = "10";
  int currentPage = 0;
  int? editingId;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _hScroll = ScrollController();

  int? _sortColumnIndex;
  bool _sortAscending = true;

  Future<void> _loadPersistedStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('category_status_overrides');
    } catch (_) {}
  }

  bool _isItemActive(dynamic data) {
    if (data == null || data is! Map) return false;
    final raw =
        data['status'] ??
        data['active_status'] ??
        data['Status'] ??
        data['is_active'];
    if (raw == null) return true;

    // Status 0 -> Active/ON
    // Status 1 -> Inactive/OFF
    if (raw == 0 || raw == false || raw == '0') return true;
    if (raw == 1 || raw == true || raw == '1') return false;

    final str = raw.toString().trim().toLowerCase();
    if (str == '0' || str == 'active' || str == 'on') {
      return true;
    }
    if (str == '1' || str == 'inactive' || str == 'off') {
      return false;
    }
    return false;
  }

  int _validateStatus(dynamic rawStatus) {
    if (rawStatus == null) return 0;
    if (rawStatus is int) return rawStatus == 0 ? 0 : 1;
    if (rawStatus is bool) return rawStatus ? 0 : 1;
    final str = rawStatus.toString().trim().toLowerCase();
    if (str == '0' || str == 'active' || str == 'true') return 0;
    if (str == '1' || str == 'inactive' || str == 'false') return 1;
    final parsed = int.tryParse(str);
    if (parsed != null) return parsed == 0 ? 0 : 1;
    return 0; // default active (0)
  }

  void _applySort() {
    if (_sortColumnIndex == 0) {
      filteredList.sort((a, b) {
        final aVal = (a['category_name']?.toString() ?? "").toLowerCase();
        final bVal = (b['category_name']?.toString() ?? "").toLowerCase();
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    } else {
      // Default: sort by id descending (newest at the top, oldest in last)
      filteredList.sort((a, b) {
        final aId = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        final bId = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return bId.compareTo(aId);
      });
    }
  }

  // --- CONTROLLERS ---
  final TextEditingController _departmentNameController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPersistedStatuses().then((_) {
      if (mounted) fetchCategories();
    });
  }

  @override
  void dispose() {
    _departmentNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // --- API INTEGRATIONS (THE 5 COMMANDS) ---
  // ──────────────────────────────────────────────────────────────────────────

  // 1. FETCH LIST (categoryview)
  Future<void> fetchCategories({bool showLoading = true}) async {
    if (showLoading && categoryList.isEmpty) {
      setState(() => isLoading = true);
    }
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/categoryview'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (!mounted) return;
        final List<dynamic> raw = decoded is Map
            ? (decoded['data'] ?? decoded['category_list'] ?? [])
            : (decoded is List ? decoded : []);
        final List<dynamic> parsed = raw.map((c) {
          if (c is Map) {
            final map = Map<String, dynamic>.from(c);
            final int statusVal =
                _validateStatus(map['status'] ?? map['active_status']);
            map['status'] = statusVal;
            map['active_status'] = statusVal;
            return map;
          }
          return c;
        }).toList();

        setState(() {
          categoryList = parsed;
          final query = _searchController.text.trim().toLowerCase();
          if (query.isNotEmpty) {
            filteredList = categoryList
                .where(
                  (item) => (item['category_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(query),
                )
                .toList();
          } else {
            filteredList = List.from(categoryList);
          }
          _applySort();
          isLoading = false;
        });
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Connection Error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchDepartmentList({bool showLoading = true}) async {
    await fetchCategories(showLoading: showLoading);
  }

  // 2 & 4. INSERT OR UPDATE (insertCategoryview / categoryUpdateview)
  Future<void> handleFormSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final String name = _departmentNameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar("Department Name is required!");
      return;
    }

    final bool isUpdate = editingId != null;
    setState(() => isSubmitting = true);

    try {
      final String name = _departmentNameController.text.trim();
      final Map<String, dynamic> body = isUpdate
          ? {"api_key": _apiKey, "id": editingId, "category_name": name}
          : {"api_key": _apiKey, "category_name": name};
      if (isUpdate) {
        final existing = categoryList.firstWhere(
          (c) => (c['id'] ?? c['category_id'])?.toString() == editingId.toString(),
          orElse: () => null,
        );
        if (existing != null && existing is Map) {
          body["status"] = _validateStatus(existing['status'] ?? existing['active_status']);
        }
      }
      final response = await http.post(
        Uri.parse(
          isUpdate
              ? '$_baseUrl/categoryUpdateview'
              : '$_baseUrl/insertCategoryview',
        ),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
        _showSnackBar(
          isUpdate ? "Department Updated!" : "Department Submitted!",
        );
        _clearForm();
        fetchCategories(); // Refresh table immediately
      } else {
        _showSnackBar("Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Submit failed: $e");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // 3. EDIT (categoryEditview)
  Future<void> loadForEdit(dynamic id) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/categoryEditview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "id": int.tryParse(id.toString()) ?? id,
        }),
      );

      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body);
        final dynamic data = resBody['data'] ?? resBody['category_data'];

        if (!mounted) return;

        // Handle if data is a list or a map
        dynamic category;
        if (data is List && data.isNotEmpty) {
          category = data[0];
        } else if (data is Map) {
          category = data;
        }

        // Additional fallback: search in categoryList if API response is empty or missing name
        if (category == null ||
            (category['category_name'] == null && category['name'] == null)) {
          category = categoryList.firstWhere(
            (item) => item['id']?.toString() == id.toString(),
            orElse: () => null,
          );
        }

        if (category != null) {
          setState(() {
            editingId = int.parse(id.toString());
            _departmentNameController.text =
                category['category_name']?.toString() ??
                category['name']?.toString() ??
                "";
          });
          _showDepartmentDialog();
        } else {
          _showSnackBar("Could not find department details");
        }
      } else {
        _showSnackBar("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error loading data: $e");
    }
  }

  // 5. TOGGLE STATUS (categoryStatusUpdateview)
  Future<void> toggleStatus(dynamic department) async {
    final int? categoryId = int.tryParse(
      (department['id'] ?? department['category_id'] ?? department['ID'])
              ?.toString() ??
          '',
    );
    if (categoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid department ID."),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Status mapping: 0 = Active (green switch), 1 = Inactive (grey switch)
    final int currentStatus =
        int.tryParse(department['status']?.toString() ?? '0') ?? 0;
    final int targetStatus = currentStatus == 0 ? 1 : 0;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Confirm Action",
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Text(
            currentStatus == 0
                ? "Do you want to set this item as inactive?"
                : "Do you want to set this item as active?",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final response = await http
          .post(
            Uri.parse('${getBaseUrl()}/categoryStatusUpdateview'),
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
            },
            body: jsonEncode({
              "api_key": _apiKey,
              "category_id": categoryId,
              "status": targetStatus,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          if (department is Map) {
            department['status'] = targetStatus;
            department['active_status'] = targetStatus;
            department['Status'] = targetStatus;
          }
          final cIdx = categoryList.indexWhere(
            (c) =>
                (c['id'] ?? c['category_id'])?.toString() ==
                categoryId.toString(),
          );
          if (cIdx != -1 && categoryList[cIdx] is Map) {
            categoryList[cIdx]['status'] = targetStatus;
            categoryList[cIdx]['active_status'] = targetStatus;
          }
          final fIdx = filteredList.indexWhere(
            (c) =>
                (c['id'] ?? c['category_id'])?.toString() ==
                categoryId.toString(),
          );
          if (fIdx != -1 && filteredList[fIdx] is Map) {
            filteredList[fIdx]['status'] = targetStatus;
            filteredList[fIdx]['active_status'] = targetStatus;
          }
        });

        await fetchDepartmentList(showLoading: false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Status updated successfully."),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update status (${response.statusCode})."),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Toggle Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Connection error: $e"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 6. DELETE (deleteCategoryview)
  Future<void> deleteCategory(dynamic id) async {
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
              "Are you sure you want to delete this department? This action cannot be undone.",
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

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/deleteCategoryview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id}),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        _showSnackBar("Department deleted successfully!");
        fetchCategories();
      } else {
        if (!mounted) return;
        _showSnackBar("Failed to delete (${response.statusCode})");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Delete error: $e");
    }
  }

  void _clearForm() {
    setState(() {
      editingId = null;
      _departmentNameController.clear();
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      filteredList = categoryList
          .where(
            (item) => item['category_name'].toString().toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      _applySort();
    });
  }

  void _showDepartmentDialog() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Add Department" : "Edit Department",
      titleStyle: TextStyle(
        fontSize: isMobile ? 18 : 22,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      subtitle: "Manage organizational units and categories",
      subtitleStyle: TextStyle(
        fontSize: 12,
        color: Colors.white.withOpacity(0.85),
      ),
      icon: editingId == null
          ? Icons.add_business_rounded
          : Icons.edit_note_rounded,
      width: isMobile
          ? MediaQuery.of(context).size.width * 0.85
          : 500,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
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
                  controller: _departmentNameController,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Please enter the Department Name';
                    final clean = v.trim().toLowerCase();
                    final exists = categoryList.any((c) {
                      final name =
                          (c['category_name'] ??
                                  c['categoryName'] ??
                                  c['name'] ??
                                  '')
                              .toString()
                              .trim()
                              .toLowerCase();
                      final id = c['id'] ?? c['ID'];
                      if (editingId != null &&
                          id?.toString() == editingId?.toString())
                        return false;
                      return name == clean;
                    });
                    if (exists) return 'This department already exists.';
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    errorStyle: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    hintText: 'Enter Department Name',
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
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
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
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _clearForm();
            Navigator.pop(context);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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
              : () {
                  if (_formKey.currentState!.validate()) {
                    handleFormSubmit();
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
                  editingId == null ? "Submit" : "Update",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
        ),
      ],
    );
  }
  // ──────────────────────────────────────────────────────────────────────────
  // --- UI COMPONENTS ---
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTabletOrMobile = screenWidth < 950;

    final int rowsPerPage = int.tryParse(entriesValue) ?? 10;
    final int totalRows = filteredList.length;
    final int totalPages = (totalRows / rowsPerPage).ceil().clamp(1, 9999);
    final int safePage = currentPage.clamp(0, totalPages - 1);
    final int start = safePage * rowsPerPage;
    final int end = (start + rowsPerPage).clamp(0, totalRows);
    final int currentItemCount = totalRows == 0 ? 1 : (end - start);

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
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 10.0 : 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;
                  final heading = const AnimatedHeading(
                    text: "Department List",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  );

                  return isNarrow
                      ? SizedBox(
                          width: double.infinity,
                          child: Center(child: heading),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            heading,
                            _buildAddDepartmentButton(isNarrow),
                          ],
                        );
                },
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              _buildTableCard(),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SelectionArea(
        child: Scrollbar(
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: bodyContent,
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white54, width: 1.2),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Department Name *",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _departmentNameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter Department Name',
              hintStyle: const TextStyle(color: Colors.white54),
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              filled: true,
              fillColor: Colors.white10,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (editingId != null)
                TextButton(
                  onPressed: _clearForm,
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ElevatedButton(
                onPressed: handleFormSubmit,
                child: Text(editingId == null ? "Submit" : "Update"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard() {
    final int rowsPerPage = int.tryParse(entriesValue) ?? 10;
    final int totalRows = filteredList.length;
    final int totalPages = (totalRows / rowsPerPage).ceil().clamp(1, 9999);
    // Clamp currentPage safely (read-only in build path)
    final int safePage = currentPage.clamp(0, totalPages - 1);
    final int start = safePage * rowsPerPage;
    final int end = (start + rowsPerPage).clamp(0, totalRows);
    final pagedData = filteredList.sublist(start, end);

    return Column(
      children: [
        _buildListHeader(),
        const SizedBox(height: 16),
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : Container(
                width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 1.0,
                      ),
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
                        // Table Header Row
                        Container(
                          height: 45,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
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
                              Expanded(
                                flex: 5,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 12.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          "DEPARTMENT",
                                          style: TextStyle(
                                            color: Color.fromRGBO(
                                              33,
                                              150,
                                              243,
                                              1,
                                            ),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        const SizedBox(width: 4),
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _sortColumnIndex = 0;
                                                  _sortAscending = true;
                                                  _applySort();
                                                });
                                              },
                                              child: Align(
                                                heightFactor: 0.4,
                                                child: Icon(
                                                  Icons.arrow_drop_up,
                                                  size: 18,
                                                  color:
                                                      _sortColumnIndex == 0 &&
                                                          _sortAscending
                                                      ? Colors.blue
                                                      : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _sortColumnIndex = 0;
                                                  _sortAscending = false;
                                                  _applySort();
                                                });
                                              },
                                              child: Align(
                                                heightFactor: 0.4,
                                                child: Icon(
                                                  Icons.arrow_drop_down,
                                                  size: 18,
                                                  color:
                                                      _sortColumnIndex == 0 &&
                                                          !_sortAscending
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
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: const Text(
                                    "EDIT",
                                    style: TextStyle(
                                      color: Color.fromRGBO(33, 150, 243, 1),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 16.0),
                                    child: const Text(
                                      "ACTION",
                                      style: TextStyle(
                                        color: Color.fromRGBO(33, 150, 243, 1),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (pagedData.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 36.0),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 36,
                                  color: Colors.blue.shade200,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "No matching departments found",
                                  style: TextStyle(
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Try a different search term",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...pagedData.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final department = item;
                            final sNo = start + index + 1;
                            return Container(
                              height: 48,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 12.0),
                                        child: Text(
                                          sNo.toString(),
                                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 12.0),
                                        child: Text(
                                          item['category_name']?.toString() ??
                                              "-",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                          size: 18,
                                        ),
                                        onPressed: () =>
                                            loadForEdit(item['id']),
                                        hoverColor: Colors.blueAccent
                                            .withOpacity(0.1),
                                        tooltip: "Edit",
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
                                        child: Transform.scale(
                                          scale: 0.7,
                                          child: Switch(
                                            value: (department['status']?.toString() == '0'),
                                            activeThumbColor: Colors.green,
                                            activeTrackColor: Colors.green.shade200,
                                            inactiveThumbColor: Colors.grey,
                                            inactiveTrackColor: Colors.grey.shade300,
                                            trackOutlineColor:
                                                WidgetStateProperty.resolveWith<
                                                  Color?
                                                >((_) => Colors.transparent),
                                            thumbColor:
                                                WidgetStateProperty.resolveWith<
                                                  Color
                                                >((states) {
                                                  if (states.contains(
                                                    WidgetState.selected,
                                                  )) {
                                                    return Colors.green;
                                                  }
                                                  return Colors.grey;
                                                }),
                                            trackColor:
                                                WidgetStateProperty.resolveWith<
                                                  Color
                                                >((states) {
                                                  if (states.contains(
                                                    WidgetState.selected,
                                                  )) {
                                                    return Colors
                                                        .green
                                                        .shade200;
                                                  }
                                                  return Colors.grey.shade300;
                                                }),
                                            onChanged: (bool newVal) =>
                                                toggleStatus(department),
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
                  ),
        SizedBox(height: MediaQuery.of(context).size.width < 950 ? 4 : 16),
        _buildTableFooter(),
      ],
    );
  }

  Widget _buildSetexttionLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _buildAddDepartmentButton(bool isNarrow) {
    return ElevatedButton.icon(
      onPressed: () {
        _clearForm();
        _showDepartmentDialog();
      },
      icon: Icon(Icons.add_business_rounded, size: isNarrow ? 14 : 20),
      style: isNarrow
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(80, 32),
            )
          : null,
      label: Text(
        "ADD DEPARTMENT",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isNarrow ? 10 : 12,
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

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
                items: ["10", "25", "50", "100"]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() {
                  entriesValue = v!;
                  currentPage = 0;
                }),
              ),
            ),
            if (!isNarrow) ...[
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
          constraints: BoxConstraints(maxWidth: isNarrow ? 180 : 250),
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search Departments...',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
        );

        return isNarrow
            ? SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildAddDepartmentButton(isNarrow),
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
      },
    );
  }

  Widget _buildTableFooter() {
    final limit = int.tryParse(entriesValue) ?? 10;
    final total = filteredList.length;
    final totalPages = (total / limit).ceil().clamp(1, 9999);
    final safePage = currentPage.clamp(0, totalPages - 1);
    final start = total == 0 ? 0 : safePage * limit + 1;
    final end = (safePage * limit + limit).clamp(0, total);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final paginationText = Text(
          "Showing $start to $end of $total entries",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.black54,
          ),
        );
        final paginationControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPageBtn(
              "Previous",
              enabled: currentPage > 0,
              onTap: () => setState(() => currentPage--),
            ),
            ..._buildPageNumberButtons(totalPages),
            _buildPageBtn(
              "Next",
              enabled: currentPage < totalPages - 1,
              onTap: () => setState(() => currentPage++),
            ),
          ],
        );

        return isNarrow
            ? SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    paginationText,
                    const SizedBox(height: 10),
                    paginationControls,
                  ],
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [paginationText, paginationControls],
              );
      },
    );
  }

  List<Widget> _buildPageNumberButtons(int totalPages) {
    final visibleCount = totalPages.clamp(1, 3);
    int windowStart = currentPage - 1; // try to place currentPage in middle
    if (windowStart < 0) windowStart = 0;
    if (windowStart + visibleCount - 1 >= totalPages) {
      windowStart = totalPages - visibleCount;
    }
    List<Widget> widgets = [];
    for (int i = windowStart; i < windowStart + visibleCount; i++) {
      final idx = i; // capture for closure
      widgets.add(
        _buildPageBtn(
          "${idx + 1}",
          active: currentPage == idx,
          onTap: () => setState(() => currentPage = idx),
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
          color: active
              ? Colors.blue
              : (enabled ? Colors.white : Colors.grey.shade50),
          border: Border.all(
            color: active ? Colors.blue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? Colors.white
                : (enabled ? Colors.black87 : Colors.black26),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(24),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
