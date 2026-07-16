import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

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

  int? _sortColumnIndex;
  bool _sortAscending = true;

  void _applySort() {
    if (_sortColumnIndex == 0) {
      filteredList.sort((a, b) {
        final aVal = (a['category_name']?.toString() ?? "").toLowerCase();
        final bVal = (b['category_name']?.toString() ?? "").toLowerCase();
        return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
      });
    } else {
      // Default: sort by id descending (newest at the top)
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
    fetchCategories(); // Load data immediately
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
  Future<void> fetchCategories() async {
    setState(() => isLoading = true);
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
        setState(() {
          if (decoded is Map) {
            categoryList = decoded['data'] ?? decoded['category_list'] ?? [];
          } else if (decoded is List) {
            categoryList = decoded;
          }
          filteredList = List.from(categoryList);
          _applySort();
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Connection Error: $e");
      setState(() => isLoading = false);
    }
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
        body: jsonEncode(
          isUpdate
              ? {"api_key": _apiKey, "id": editingId, "category_name": name}
              : {"api_key": _apiKey, "category_name": name},
        ),
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
  Future<void> toggleStatus(dynamic id, dynamic currentStatus) async {
    try {
      final int newStatus = (currentStatus == 1 || currentStatus == "1")
          ? 0
          : 1;
      final response = await http.post(
        Uri.parse('$_baseUrl/categoryStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "category_id": id,
          "status": newStatus,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        fetchCategories();
      }
    } catch (e) {
      debugPrint("Toggle Error: $e");
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
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Add Department" : "Edit Department",
      subtitle: "Manage organizational units and categories",
      icon: editingId == null
          ? Icons.add_business_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.4,
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
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter the Department Name'
                      : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
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
                    text: "Department List",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _clearForm();
                      _showDepartmentDialog();
                    },
                    icon: const Icon(Icons.add_business_rounded, size: 20),
                    label: const Text(
                      "ADD DEPARTMENT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // List Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20.0),
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
                  child: _buildTableCard(),
                ),
              ),
            ],
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
    return Column(
      children: [
        _buildListHeader(),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: (categoryList.isNotEmpty && filteredList.isEmpty)
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
                          "No matching departments found",
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
                      ],
                    ),
                  )
                : Column(
                    children: [
                      if (isLoading)
                        const LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          color: Colors.blue,
                        ),
                      Expanded(
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
                                    headingRowHeight: 45,
                                    headingRowColor: WidgetStateProperty.all(
                                      Colors.blue.shade50,
                                    ),
                                    border: TableBorder.all(
                                      color: Colors.grey.shade100,
                                    ),
                                    columns: _getColumns(),
                                    rows: _getCurrentPageRows(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _buildTableFooter(),
      ],
    );
  }

  List<DataColumn> _getColumns() {
    final titles = ['Department', 'Edit', 'Action', 'Delete'];
    return List.generate(titles.length, (index) {
      final isSortable = index == 0;
      return DataColumn(
        label: Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  titles[index],
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSortable) ...[
                const SizedBox(width: 4),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sortColumnIndex = index;
                          _sortAscending = true;
                          _applySort();
                        });
                      },
                      child: Align(
                        heightFactor: 0.4,
                        child: Icon(
                          Icons.arrow_drop_up,
                          size: 18,
                          color: _sortColumnIndex == index && _sortAscending
                              ? Colors.blue
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sortColumnIndex = index;
                          _sortAscending = false;
                          _applySort();
                        });
                      },
                      child: Align(
                        heightFactor: 0.4,
                        child: Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: _sortColumnIndex == index && !_sortAscending
                              ? Colors.blue
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  List<DataRow> _getCurrentPageRows() {
    int rowsPerPage = int.parse(entriesValue);
    int start = currentPage * rowsPerPage;
    int end = (start + rowsPerPage < filteredList.length)
        ? (start + rowsPerPage)
        : filteredList.length;

    if (start >= filteredList.length && filteredList.isNotEmpty) {
      currentPage = (filteredList.length / rowsPerPage).floor();
      start = currentPage * rowsPerPage;
      end = filteredList.length;
    }

    return filteredList
        .sublist(start, end)
        .map((item) => _getRow(item))
        .toList();
  }

  DataRow _getRow(dynamic item) {
    return DataRow(
      cells: [
        DataCell(
          Text(
            item['category_name']?.toString() ?? "-",
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
            onPressed: () => loadForEdit(item['id']),
            hoverColor: Colors.blueAccent.withOpacity(0.1),
          ),
        ),
        DataCell(
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: item['status'] == 1 || item['status'] == "1",
              activeColor: Colors.greenAccent,
              onChanged: (v) => toggleStatus(item['id'], item['status']),
            ),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
            onPressed: () => deleteCategory(item['id']),
            tooltip: "Delete",
          ),
        ),
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

  Widget _buildListHeader() {
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
                onChanged: (v) => setState(() {
                  entriesValue = v!;
                  currentPage = 0;
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
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Search Departments...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableFooter() {
    int rowsPerPage = int.parse(entriesValue);
    int totalPages = (filteredList.length / rowsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Total: ${filteredList.length} Departments",
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        // Use a single Row for all buttons to keep them tight together
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- PREV BUTTON ---
            GestureDetector(
              onTap: currentPage > 0
                  ? () => setState(() => currentPage--)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  // Removed right radius to connect to the next button
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    bottomLeft: Radius.circular(6),
                  ),
                  border: Border.all(
                    color: currentPage > 0
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  "Prev",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: currentPage > 0 ? Colors.blue.shade700 : Colors.grey,
                  ),
                ),
              ),
            ),

            // --- NUMBER BUTTONS ---
            // Using a Wrap or simple Row without margins
            ...List.generate(totalPages, (index) {
              if (totalPages > 7) {
                if (index != 0 &&
                    index != totalPages - 1 &&
                    (index < currentPage - 1 || index > currentPage + 1)) {
                  if (index == currentPage - 2 || index == currentPage + 2) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: const Text(
                        "...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }
              }
              return InkWell(
                onTap: () => setState(() => currentPage = index),
                child: Container(
                  // REMOVED MARGIN HERE to eliminate gaps
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: currentPage == index
                        ? Colors.blue.shade600
                        : Colors.white,
                    // Removed borderRadius to keep buttons flush against each other
                    border: Border.all(
                      color: currentPage == index
                          ? Colors.blue.shade600
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      fontSize: 12,
                      color: currentPage == index
                          ? Colors.white
                          : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),

            // --- NEXT BUTTON ---
            GestureDetector(
              onTap: currentPage < totalPages - 1
                  ? () => setState(() => currentPage++)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  // Removed left radius to connect to the previous button
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(
                    color: currentPage < totalPages - 1
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                  ),
                ),

                child: Text(
                  "Next",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: currentPage < totalPages - 1
                        ? Colors.blue.shade700
                        : Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
