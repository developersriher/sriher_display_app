import '../../api_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Privilege definitions
// Each entry: { id: menuId, name: display, type: subId }
// The API expects "previliges": ["menuId,subId", ...]
// ──────────────────────────────────────────────────────────────────────────────
class _Priv {
  final String id; // "menuId,subId"  e.g. "1,1"
  final String name; // display label
  const _Priv(this.id, this.name);
}

const List<_Priv> _allPrivileges = [
  _Priv("1,1", "Dashboard"),
  _Priv("2,1", "Add User"),
  _Priv("3,1", "Role"),
  _Priv("3,2", "Device Master"),
  _Priv("3,3", "Department"),
  _Priv("3,4", "Location"),
  _Priv("3,5", "Mapping"),
  _Priv("4,1", "File Upload"),
  _Priv("5,1", "Create Template"),
  _Priv("5,2", "Default Template"),
  _Priv("5,3", "Select Template"),
  _Priv("6,1", "Schedule Allocate"),
  _Priv("6,2", "Assign Device"),
  _Priv("6,3", "Schedule List"),
  _Priv("6,4", "Specific Ranges"),
  _Priv("6,5", "Copy and Wipe Off"),
];

class RoleView extends StatefulWidget {
  const RoleView({super.key});

  @override
  State<RoleView> createState() => _RoleViewState();
}

class _RoleViewState extends State<RoleView>
    with SingleTickerProviderStateMixin {
  static const String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  // ── list state ──
  List<dynamic> allRoles = [];
  bool isLoading = true;
  String entriesValue = "10";
  String searchQuery = "";
  int currentPage = 0;
  final TextEditingController _searchController = TextEditingController();

  // ── form state ──
  int? editingId; // null = create, non-null = update
  bool isFetchingDetails = false;
  bool isSubmitting = false;
  final _formKey = GlobalKey<FormState>();
  StateSetter? _dialogSetState;
  final TextEditingController _roleNameController = TextEditingController();
  final Set<String> _selectedPrivs = {}; // e.g. {"1,1", "3,2"}

  @override
  void initState() {
    super.initState();
    fetchRoles();
  }

  @override
  void dispose() {
    _roleNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ──────────────────────────── API CALLS ──────────────────────────────────

  /// GET /roleview — fetch all roles
  Future<void> fetchRoles() async {
    setState(() => isLoading = true);
    try {
      final res = await http
          .post(
            Uri.parse('${getBaseUrl()}/roleview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final payload = data is Map && data.containsKey('data')
            ? data['data']
            : data;
        if (!mounted) return;
        setState(() {
          allRoles =
              (payload is List
                      ? payload
                      : (payload['roles'] ?? payload['data'] ?? []))
                  as List;
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
        _showServiceUnavailable();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showServiceUnavailable();
    }
  }

  void _showServiceUnavailable() {
    if (!mounted) return;
    StylishDialog.show(
      context: context,
      title: "Service Unavailable",
      subtitle:
          "The backend server is currently unreachable or returned an error. Please try again later.",
      icon: Icons.cloud_off,
      maxWidth: 400,
      builder: (context, setPopupState) {
        return Center(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  /// POST /roleUpdateFormview — load a single role into the form for editing
  Future<void> loadForEdit(dynamic role) async {
    final id = int.tryParse(role['id']?.toString() ?? '');
    if (id == null) return;

    // 1. Initialize with local data immediately
    setState(() {
      editingId = id;
      _roleNameController.text = role['role_name']?.toString() ?? '';
      _selectedPrivs.clear();
      isFetchingDetails = true;
    });

    // 2. Open dialog immediately
    _showRoleDialog();

    // 3. Fetch full details (privileges) in the background
    try {
      final res = await http
          .post(
            Uri.parse('${getBaseUrl()}/roleUpdateFormview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey, "id": id}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final payload = data is Map && data.containsKey('data')
            ? data['data']
            : data;
        final r = (payload is List && payload.isNotEmpty)
            ? payload[0]
            : payload;

        final rawPrivs = r['previliges'] ?? r['privileges'] ?? [];
        final Set<String> privSet = {};
        if (rawPrivs is List) {
          for (final p in rawPrivs) {
            if (p is Map) {
              final mId = p['menu_id']?.toString() ?? p['menuId']?.toString();
              final sId =
                  p['sub_menu_id']?.toString() ??
                  p['subMenuId']?.toString() ??
                  p['sub_id']?.toString() ??
                  p['type']?.toString();
              if (mId != null && sId != null) {
                privSet.add("$mId,$sId");
              }
            } else {
              privSet.add(p.toString());
            }
          }
        } else if (rawPrivs is String && rawPrivs.isNotEmpty) {
          final parts = rawPrivs.split(',').map((s) => s.trim()).toList();
          if (parts.length > 1 && !parts[0].contains(',')) {
            for (int i = 0; i < parts.length - 1; i += 2) {
              privSet.add("${parts[i]},${parts[i + 1]}");
            }
          } else {
            privSet.addAll(parts);
          }
        }

        if (!mounted) return;
        
        // Update both main state and dialog state
        _selectedPrivs.clear();
        _selectedPrivs.addAll(privSet);
        
        if (mounted) {
          setState(() => isFetchingDetails = false);
          // Trigger dialog rebuild to show newly fetched privileges
          if (_dialogSetState != null) {
            _dialogSetState!(() {});
          }
        }
      } else {
        if (mounted) setState(() => isFetchingDetails = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => isFetchingDetails = false);
        if (_dialogSetState != null) {
          _dialogSetState!(() {});
        }
        _snack("Could not load full privileges.", isError: true);
      }
    }
  }

  Future<void> handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPrivs.isEmpty) {
      _snack("Select at least one privilege.", isError: true);
      return;
    }

    setState(() => isSubmitting = true);
    // DISMISS IMMEDIATELY
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);

    final bool isUpdate = editingId != null;
    final url = isUpdate
        ? '${getBaseUrl()}/updateRoleview'
        : '${getBaseUrl()}/createRoleview';

    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "role_name": _roleNameController.text.trim(),
      "previliges": _selectedPrivs.toList(),
    };
    if (isUpdate) body["id"] = editingId;

    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        if (!mounted) return;
        _snack(isUpdate ? "Role updated!" : "Role created!");
        _resetForm();
        fetchRoles();
      } else {
        if (!mounted) return;
        final resData = jsonDecode(res.body);
        final errorMsg = resData is Map
            ? (resData['message'] ?? resData['error'] ?? "Server error")
            : "Server error";
        _snack("$errorMsg (${res.statusCode}).", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack("Connection failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> deleteRole(dynamic role) async {
    final id = int.tryParse(role['id']?.toString() ?? '');
    if (id == null) return;

    final confirm = await StylishDialog.show<bool>(
      context: context,
      title: "DELETE ROLE",
      maxWidth: 400,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete \"${role['role_name']}\"? This action cannot be undone.",
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Delete Role",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
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
      final res = await http
          .post(
            Uri.parse('${getBaseUrl()}/deleteRoleview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey, "id": id}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        if (!mounted) return;
        _snack("Role deleted.");
        fetchRoles();
      } else {
        if (!mounted) return;
        _snack("Delete failed (${res.statusCode}).", isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      _snack("Connection failed.", isError: true);
    }
  }

  void _resetForm() {
    setState(() {
      editingId = null;
      _roleNameController.clear();
      _selectedPrivs.clear();
    });
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showRoleDialog() {
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Create Roles" : "Edit Role Details",
      subtitle: "Configure system permissions and access levels",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      icon: editingId == null ? Icons.add_moderator : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.6,
      builder: (context, setDialogState) {
        _dialogSetState = setDialogState;
        // Use the main set directly for perfect sync
        return _buildRoleFormDialog(setDialogState, _selectedPrivs);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int limit = int.parse(entriesValue);
    final filtered = searchQuery.isEmpty
        ? allRoles
        : allRoles
              .where(
                (r) => (r['role_name']?.toString().toLowerCase() ?? '')
                    .contains(searchQuery.toLowerCase()),
              )
              .toList();

    final int totalPages = (filtered.length / limit).ceil();
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    final int start = currentPage * limit;
    final int end = (start + limit > filtered.length)
        ? filtered.length
        : start + limit;
    final paged = (filtered.isEmpty || start >= filtered.length)
        ? []
        : filtered.sublist(start, end);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const AnimatedHeading(
                        text: "Roles List",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          _resetForm();
                          _showRoleDialog();
                        },
                        icon: const Icon(Icons.add_moderator, size: 20),
                        label: const Text(
                          "CREATE ROLES",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildListHeader(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : (allRoles.isNotEmpty && paged.isEmpty)
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
                                  "No matching roles found",
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
                        : _buildTableContainer(paged, filtered.length, limit),
                  ),
                  const SizedBox(height: 20),
                  _buildFooter(paged.length, filtered.length, limit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableContainer(
    List<dynamic> paged,
    int totalFiltered,
    int limit,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade100),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columnSpacing: 24,
                  headingRowHeight: 45,
                  dataRowMaxHeight: 56,
                  horizontalMargin: 20,
                  headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                  columns: [
                    _buildCol('#'),
                    _buildCol('Role'),
                    _buildCol('Edit'),
                    _buildCol('Action'),
                  ],
                  rows: paged
                      .asMap()
                      .entries
                      .map(
                        (e) =>
                            _buildRow(currentPage * limit + e.key + 1, e.value),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(int pagedCount, int totalCount, int limit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing ${totalCount == 0 ? 0 : currentPage * limit + 1} to ${currentPage * limit + pagedCount} of $totalCount entries",
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        _buildPagination(totalCount, limit),
      ],
    );
  }

  Widget _buildRoleFormDialog(
    StateSetter setDialogState,
    Set<String> localPrivs,
  ) {
    final bool allSelected = localPrivs.length == _allPrivileges.length;

    void _toggle(String id, bool? v) {
      setDialogState(() {
        if (v == true) {
          localPrivs.add(id);
        } else {
          localPrivs.remove(id);
        }
      });
    }

    void _toggleAll(bool? v) {
      setDialogState(() {
        if (v == true) {
          localPrivs.addAll(_allPrivileges.map((p) => p.id));
        } else {
          localPrivs.clear();
        }
      });
    }

    TableRow buildPrivRow(String section, List<_Priv> privs) {
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              section,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 0,
              runSpacing: 0,
              children: privs
                  .map(
                    (p) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: localPrivs.contains(p.id),
                          onChanged: (v) => _toggle(p.id, v),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeColor: const Color(0xFF0F172A),
                        ),
                        Text(p.name, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Role Name",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _roleNameController,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? "Please enter the Role Name"
                : null,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
            decoration: InputDecoration(
              hintText: 'Enter the Role Name',
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
          const SizedBox(height: 20),

          Row(
            children: [
              const Text(
                "Permissions",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.9,
                child: Checkbox(
                  value: allSelected,
                  onChanged: _toggleAll,
                  activeColor: const Color(0xFF0F172A),
                ),
              ),
              const Text("Select All", style: TextStyle(fontSize: 12)),
            ],
          ),
          const Divider(),

          SizedBox(
            height: 400,
            child: isFetchingDetails
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF0F172A)),
                        SizedBox(height: 16),
                        Text(
                          "Loading privileges...",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Table(
                      border: TableBorder.all(color: Colors.grey.shade200),
                      columnWidths: const {
                        0: FlexColumnWidth(1.2),
                        1: FlexColumnWidth(2.5),
                      },
                      children: [
                        buildPrivRow("Dashboard", [_allPrivileges[0]]),
                        buildPrivRow("Users", [_allPrivileges[1]]),
                        buildPrivRow("System", _allPrivileges.sublist(2, 7)),
                        buildPrivRow("Files", [_allPrivileges[7]]),
                        buildPrivRow("Templates", _allPrivileges.sublist(8, 11)),
                        buildPrivRow("Scheduling", _allPrivileges.sublist(11, 16)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _resetForm();
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Cancel",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              StatefulBuilder(
                builder: (context, setBtnState) {
                  return ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            setBtnState(() => {});
                            await handleSubmit();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            editingId == null ? "Submit" : "Update",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  );
                },
              ),
            ],
          ),
        ],
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

  DataRow _buildRow(int idx, dynamic role) {
    return DataRow(
      cells: [
        DataCell(
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text("$idx", style: const TextStyle(fontSize: 13)),
          ),
        ),
        DataCell(
          Text(
            role['role_name']?.toString() ?? "-",
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
            tooltip: "Edit",
            onPressed: () => loadForEdit(role),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            tooltip: "Delete",
            onPressed: () => deleteRole(role),
          ),
        ),
      ],
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
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF64748B),
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
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      entriesValue = v;
                      currentPage = 0;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              " entries",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() {
                  searchQuery = val;
                  currentPage = 0;
                }),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search roles...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
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
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(int totalCount, int limit) {
    int totalPages = (totalCount / limit).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pageBtn(
          "Prev",
          onTap: currentPage > 0 ? () => setState(() => currentPage--) : null,
          position: "first",
        ),
        ...List.generate(totalPages, (index) {
          if (totalPages > 5) {
            if (index != 0 &&
                index != totalPages - 1 &&
                (index < currentPage - 1 || index > currentPage + 1)) {
              if (index == currentPage - 2 || index == currentPage + 2) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text("..."),
                );
              }
              return const SizedBox.shrink();
            }
          }
          return _pageBtn(
            "${index + 1}",
            active: currentPage == index,
            onTap: () => setState(() => currentPage = index),
            position: index == 0
                ? "first"
                : (index == totalPages - 1 ? "last" : "middle"),
          );
        }),
        _pageBtn(
          "Next",
          onTap: currentPage < totalPages - 1
              ? () => setState(() => currentPage++)
              : null,
          position: "last",
        ),
      ],
    );
  }

  Widget _pageBtn(
    String label, {
    bool active = false,
    VoidCallback? onTap,
    String position = "middle",
  }) {
    BorderRadius borderRadius;
    if (position == "first") {
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(6),
        bottomLeft: Radius.circular(6),
      );
    } else if (position == "last") {
      borderRadius = const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      );
    } else {
      borderRadius = BorderRadius.zero;
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? Colors.blue : Colors.white,
        foregroundColor: active
            ? Colors.white
            : (onTap == null ? Colors.grey : Colors.black87),
        side: BorderSide(
          color: active ? Colors.blue : Colors.grey.shade300,
          width: 0.8,
        ),
        padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 12 : 8),
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        elevation: 0,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
