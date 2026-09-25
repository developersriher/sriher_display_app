import '../../api_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

class AddUserView extends StatefulWidget {
  const AddUserView({super.key});

  @override
  State<AddUserView> createState() => _AddUserViewState();
}

class _AddUserViewState extends State<AddUserView> {
  static const String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  List<dynamic> allUsers = [];
  List<dynamic> allRoles = [];
  bool isLoading = true;
  bool isSubmitting = false;
  String entriesValue = "10";
  int currentPage = 1;
  String searchQuery = "";

  // Sorting State
  int _sortColumnIndex = -1;
  bool _sortAscending = false;

  // Table search controller (NOT form)
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchUserList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ──────────────────────────── API CALLS ────────────────────────────────────

  Future<void> fetchUserList() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await http
          .post(
            Uri.parse('${getBaseUrl()}/Registerview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final payload = res is Map && res.containsKey('data')
            ? res['data']
            : res;
        setState(() {
          allUsers = (payload['users'] ?? payload['data'] ?? []) as List;
          allRoles = (payload['roles'] ?? []) as List;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnack("Failed to load users. Check connection.", isError: true);
    }
  }

  Future<void> loadForEdit(dynamic user) async {
    final id = int.tryParse(user['id']?.toString() ?? '');
    if (id == null) return;

    // Prefill data from table row immediately, then refresh from API
    String userId = user['user_id']?.toString() ?? '';
    String userName = user['user_name']?.toString() ?? '';
    String password = user['user_password']?.toString() ?? '';
    String? roleId = user['role_id']?.toString();

    try {
      final response = await http
          .post(
            Uri.parse('${getBaseUrl()}/regEditview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey, "id": id}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final payload = res is Map && res.containsKey('data')
            ? res['data']
            : res;
        final u = (payload is List && payload.isNotEmpty)
            ? payload[0]
            : payload;
        userId = u['user_id']?.toString() ?? userId;
        userName = u['user_name']?.toString() ?? userName;
        password = u['user_password']?.toString() ?? password;
        roleId = u['role_id']?.toString() ?? roleId;
      }
    } catch (_) {}

    if (!mounted) return;
    _openFormDialog(
      editId: id,
      initUserId: userId,
      initUserName: userName,
      initPassword: password,
      initRoleId: roleId,
    );
  }

  Future<void> _handleSubmit({
    required int? editId,
    required String userId,
    required String userName,
    required String password,
    required String? roleId,
  }) async {
    final bool isUpdating = editId != null;
    final url = isUpdating
        ? '${getBaseUrl()}/regUpdateview'
        : '${getBaseUrl()}/insertRegisterview';

    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "user_id": userId,
      "user_name": userName,
      "role_id": roleId!, // always validated non-null before calling
    };
    if (password.isNotEmpty) body["user_password"] = password;
    if (isUpdating) body["id"] = editId;

    // Optimistic update — insert at top immediately
    if (!isUpdating) {
      setState(() {
        allUsers.insert(0, {
          'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
          'user_id': userId,
          'user_name': userName,
          'role_id': roleId,
          'status': 0,
        });
      });
    } else {
      setState(() {
        final idx = allUsers.indexWhere(
          (u) => u['id']?.toString() == editId.toString(),
        );
        if (idx != -1) {
          allUsers[idx] = {
            ...allUsers[idx],
            'user_id': userId,
            'user_name': userName,
            'role_id': roleId,
          };
        }
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        _showSnack(isUpdating ? "User updated!" : "User added!");
      } else {
        _showSnack("Server error (${response.statusCode}).", isError: true);
      }
    } catch (e) {
      _showSnack("Connection failed.", isError: true);
    }
    fetchUserList();
  }

  Future<void> toggleStatus(dynamic user, bool newStatus) async {
    final id = int.tryParse(user['id']?.toString() ?? '');
    if (id == null) return;

    setState(() {
      final idx = allUsers.indexWhere(
        (u) => u['id']?.toString() == user['id']?.toString(),
      );
      if (idx != -1)
        allUsers[idx] = {...allUsers[idx], 'status': newStatus ? 1 : 0};
    });

    try {
      await http
          .post(
            Uri.parse('${getBaseUrl()}/regUpdateview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "device_id": id,
              "status": newStatus ? 1 : 0,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      setState(() {
        final idx = allUsers.indexWhere(
          (u) => u['id']?.toString() == user['id']?.toString(),
        );
        if (idx != -1)
          allUsers[idx] = {...allUsers[idx], 'status': newStatus ? 0 : 1};
      });
      _showSnack("Failed to update status.", isError: true);
    }
  }

  Future<void> deleteUser(dynamic user) async {
    final id = int.tryParse(user['id']?.toString() ?? '');
    if (id == null) return;

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
              "Are you sure you want to delete this user? This action cannot be undone.",
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

    // Save index and item for potential rollback
    final deletedIndex = allUsers.indexWhere(
      (u) => u['id']?.toString() == user['id']?.toString(),
    );
    final deletedItem = deletedIndex != -1 ? allUsers[deletedIndex] : null;

    if (deletedIndex != -1) {
      setState(() {
        allUsers.removeAt(deletedIndex);
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse('${getBaseUrl()}/regUpdateview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "device_id": id,
              "status": 0,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _showSnack("User deleted successfully.");
        // Don't re-fetch — the server marks status:0 but still returns the user.
        // The row is already removed optimistically above.
      } else {
        // Rollback on failure
        if (deletedItem != null && deletedIndex != -1) {
          setState(() {
            allUsers.insert(deletedIndex, deletedItem);
          });
        }
        _showSnack("Failed to delete user.", isError: true);
      }
    } catch (e) {
      // Rollback on network error
      if (deletedItem != null && deletedIndex != -1) {
        setState(() {
          allUsers.insert(deletedIndex, deletedItem);
        });
      }
      _showSnack("Failed to delete user.", isError: true);
    }
  }

  void _openFormDialog({
    int? editId,
    String initUserId = '',
    String initUserName = '',
    String initPassword = '',
    String? initRoleId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(
        editId: editId,
        initUserId: initUserId,
        initUserName: initUserName,
        initPassword: initPassword,
        initRoleId: initRoleId,
        allRoles: allRoles,
        allUsers: allUsers,
        onSubmit: _handleSubmit,
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError
              ? Colors.red.shade700
              : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint("Snackbar error: $e");
    }
  }

  // ──────────────────────────── BUILD ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final int limit = int.tryParse(entriesValue) ?? 10;
    List<dynamic> filtered = searchQuery.isEmpty
        ? List.from(allUsers)
        : allUsers.where((u) {
            final q = searchQuery.toLowerCase();
            return (u['user_id']?.toString().toLowerCase().contains(q) ??
                    false) ||
                (u['user_name']?.toString().toLowerCase().contains(q) ?? false);
          }).toList();

    filtered.sort((a, b) {
      String aVal = "";
      String bVal = "";

      switch (_sortColumnIndex) {
        case 0:
          aVal = a['user_id']?.toString() ?? "";
          bVal = b['user_id']?.toString() ?? "";
          break;
        case 1:
          aVal = a['user_name']?.toString() ?? "";
          bVal = b['user_name']?.toString() ?? "";
          break;
        case 2:
          final rA =
              allRoles.firstWhere(
                (r) => r['id']?.toString() == a['role_id']?.toString(),
                orElse: () => {'role_name': 'User'},
              )['role_name'] ??
              'User';
          final rB =
              allRoles.firstWhere(
                (r) => r['id']?.toString() == b['role_id']?.toString(),
                orElse: () => {'role_name': 'User'},
              )['role_name'] ??
              'User';
          aVal = rA.toString();
          bVal = rB.toString();
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
      } else if (_sortColumnIndex == -1) {
        // Default sort: by DB id descending, placing temp_ optimistic rows at top
        final intA = aVal.startsWith('temp_')
            ? 999999999
            : (int.tryParse(aVal) ?? 0);
        final intB = bVal.startsWith('temp_')
            ? 999999999
            : (int.tryParse(bVal) ?? 0);
        return intB.compareTo(intA);
      }
      return _sortAscending
          ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
          : bVal.toLowerCase().compareTo(aVal.toLowerCase());
    });

    int totalFiltered = filtered.length;
    int start = (currentPage - 1) * limit;
    if (start >= totalFiltered && totalFiltered > 0) {
      currentPage = (totalFiltered / limit).ceil();
      if (currentPage < 1) currentPage = 1;
      start = (currentPage - 1) * limit;
    }
    int end = start + limit;
    if (end > totalFiltered) end = totalFiltered;

    final List<dynamic> pagedUsers = filtered.sublist(start, end);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final heading = const AnimatedHeading(
      text: "User List",
      style: TextStyle(
        color: Color.fromARGB(255, 33, 150, 243),
        fontWeight: FontWeight.bold,
        fontSize: 22,
      ),
    );

    final addUserBtn = ElevatedButton.icon(
      onPressed: () => _openFormDialog(),
      icon: Icon(Icons.person_add_alt_1, size: isMobile ? 14 : 20),
      style: isMobile
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(80, 32),
            )
          : null,
      label: Text(
        "ADD USER",
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
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 10.0 : 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Responsive heading row ──
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 600;
                  return isNarrow
                      ? SizedBox(
                          width: double.infinity,
                          child: Center(child: heading),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [heading, addUserBtn],
                        );
                },
              ),
              const SizedBox(height: 20),
              _buildListHeader(isMobile: isMobile, addUserBtn: addUserBtn),
              const SizedBox(height: 20),
              isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : (allUsers.isNotEmpty && pagedUsers.isEmpty)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 48,
                                    color: Colors.blue.shade200),
                                const SizedBox(height: 12),
                                Text(
                                  "No matching users found",
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
                                      color: Colors.grey, fontSize: 13.0),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildTableContainer(pagedUsers),
              const SizedBox(height: 16),
              _buildPagination(
                pagedUsers.length,
                filtered.length,
                isMobile: isMobile,
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SelectionArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: bodyContent,
        ),
      ),
    );
  }

  // ──────────────────────────── UI COMPONENTS ────────────────────────────────

  Widget _buildTableContainer(List<dynamic> pagedUsers) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: isLoading
          ? const SizedBox(
              height: 400,
              child: Center(child: CircularProgressIndicator()),
            )
          : (allUsers.isNotEmpty && pagedUsers.isEmpty)
          ? SizedBox(
              height: 400,
              child: Center(
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
                      "No matching users found",
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
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final double minWidth = constraints.maxWidth > 700
                    ? constraints.maxWidth
                    : 700;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth),
                    child: DataTable(
                      columnSpacing: 24,
                      headingRowHeight: 52,
                      dataRowMaxHeight: 56,
                      headingRowColor: WidgetStateProperty.all(
                        Colors.blue.shade50,
                      ),
                      showCheckboxColumn: false,
                      dividerThickness: 0.0,
                      columns: _buildColumns(),
                      rows: pagedUsers.map((u) => _buildRow(u)).toList(),
                    ),
                  ),
                );
              },
            ),
    );
  }

  List<DataColumn> _buildColumns() {
    return [
      _buildSortableColumn("USER ID", 0),
      _buildSortableColumn("USER NAME", 1),
      _buildSortableColumn("ROLE", 2),
      _buildSortableColumn("EDIT", -1),
      _buildSortableColumn("ACTION", -1),
    ];
  }

  DataColumn _buildSortableColumn(String label, int columnIndex) {
    return DataColumn(
      label: InkWell(
        onTap: columnIndex < 0
            ? null
            : () {
                setState(() {
                  if (_sortColumnIndex == columnIndex) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = true;
                  }
                });
              },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color.fromRGBO(33, 150, 243, 1),
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (columnIndex >= 0) ...[
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
                      color: _sortColumnIndex == columnIndex && _sortAscending
                          ? Colors.blue
                          : Colors.grey.withOpacity(0.5),
                    ),
                  ),
                  Align(
                    heightFactor: 0.4,
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: _sortColumnIndex == columnIndex && !_sortAscending
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

  DataRow _buildRow(dynamic u) {
    final roleName =
        allRoles.firstWhere(
          (r) => r['id']?.toString() == u['role_id']?.toString(),
          orElse: () => {'role_name': 'User'},
        )['role_name'] ??
        'User';

    final isActive = (u['status'] == 1 || u['status'] == '1');

    return DataRow(
      cells: [
        DataCell(
          Text(
            u['user_id']?.toString() ?? "-",
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        DataCell(Text(u['user_name']?.toString() ?? "-")),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              roleName.toString(),
              style: TextStyle(
                color: Colors.blue.shade800,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
            onPressed: () => loadForEdit(u),
            tooltip: "Edit",
          ),
        ),
        DataCell(
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: isActive,
              activeColor: Colors.green,
              onChanged: (v) => toggleStatus(u, v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader({bool isMobile = false, Widget? addUserBtn}) {
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
        height: 38,
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() {
            searchQuery = v;
            currentPage = 1;
          }),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Search ID or Name...',
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
    );

    return isMobile
        ? SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (addUserBtn != null) addUserBtn,
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

  Widget _buildPagination(int showing, int total, {bool isMobile = false}) {
    if (total == 0) return const SizedBox.shrink();

    int limit = int.tryParse(entriesValue) ?? 10;
    int maxPages = (total / limit).ceil();
    if (maxPages == 0) maxPages = 1;

    final start = (currentPage - 1) * limit + 1;
    final end = (start + showing - 1).clamp(0, total);

    final showingText = Text(
      "Showing $start to $end of $total entries",
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
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
        ..._buildPageNumberButtons(maxPages),
        _buildPageBtn(
          "Next",
          enabled: currentPage < maxPages,
          onTap: () => setState(() => currentPage++),
        ),
      ],
    );

    return isMobile
        ? SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                showingText,
                const SizedBox(height: 10),
                pagination,
              ],
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [showingText, pagination],
          );
  }

  List<Widget> _buildPageNumberButtons(int totalPages) {
    // Strict max-3 sliding window (1-indexed currentPage).
    // Shows exactly min(3, totalPages) consecutive page buttons — no ellipsis.
    final visibleCount = totalPages.clamp(1, 3);
    int windowStart = currentPage - 1; // try to center on currentPage
    if (windowStart < 1) windowStart = 1;
    if (windowStart + visibleCount - 1 > totalPages) {
      windowStart = totalPages - visibleCount + 1;
    }
    List<Widget> widgets = [];
    for (int i = windowStart; i < windowStart + visibleCount; i++) {
      final pageNum = i;
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

// ─────────────────────────────────────────────────────────────────────────────
// Self-contained dialog — owns ALL its own local state. No shared controllers.
// ─────────────────────────────────────────────────────────────────────────────
class _UserFormDialog extends StatefulWidget {
  final int? editId;
  final String initUserId;
  final String initUserName;
  final String initPassword;
  final String? initRoleId;
  final List<dynamic> allRoles;
  final List<dynamic> allUsers;
  final Future<void> Function({
    required int? editId,
    required String userId,
    required String userName,
    required String password,
    required String? roleId,
  })
  onSubmit;

  const _UserFormDialog({
    this.editId,
    this.initUserId = '',
    this.initUserName = '',
    this.initPassword = '',
    this.initRoleId,
    required this.allRoles,
    required this.allUsers,
    required this.onSubmit,
  });

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userIdCtrl;
  late final TextEditingController _userNameCtrl;
  late final TextEditingController _passCtrl;
  String? _selectedRoleId;
  bool _submitting = false;
  bool _obscurePass = true;

  bool get _isEditing => widget.editId != null;

  @override
  void initState() {
    super.initState();
    _userIdCtrl = TextEditingController(text: widget.initUserId);
    _userNameCtrl = TextEditingController(text: widget.initUserName);
    _passCtrl = TextEditingController(text: widget.initPassword);

    // Only set selectedRoleId if initRoleId actually exists in the roles list.
    // If it doesn't match (e.g. deleted role or ID mismatch), leave null so
    // the user is forced to select a valid role before submitting.
    final roleExists = widget.allRoles.any(
      (r) => r['id']?.toString() == widget.initRoleId,
    );
    _selectedRoleId = roleExists ? widget.initRoleId : null;
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _userNameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Explicit guard — validator may not catch all cases with SearchableDropdown
    if (_selectedRoleId == null || _selectedRoleId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Role'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop();
    await widget.onSubmit(
      editId: widget.editId,
      userId: _userIdCtrl.text.trim(),
      userName: _userNameCtrl.text.trim(),
      password: _passCtrl.text.trim(),
      roleId: _selectedRoleId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Blue gradient header — matches StylishDialog exactly ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _isEditing
                            ? Icons.edit_note_rounded
                            : Icons.person_add_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Edit User' : 'Add User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Text(
                            'Provide system credentials and role',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── Form fields ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // User ID
                        _label('User ID'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _userIdCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: 10,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                          decoration: _deco('Enter User ID'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Please enter the User ID';
                            final clean = v.trim().toLowerCase();
                            final exists = widget.allUsers.any((u) {
                              final uid = (u['user_id'] ?? u['userId'] ?? '').toString().trim().toLowerCase();
                              final id = u['id'] ?? u['ID'];
                              if (widget.editId != null && id?.toString() == widget.editId?.toString()) return false;
                              return uid == clean;
                            });
                            if (exists) return 'This user id already exists.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // User Name
                        _label('User Name'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _userNameCtrl,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z\s]'),
                            ),
                          ],
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                          decoration: _deco('Enter User Name'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter the User Name'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        _label('Password'),
                        const SizedBox(height: 6),
                        StatefulBuilder(
                          builder: (_, setLocal) => TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            maxLength: 20,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                            ),
                            decoration:
                                _deco(
                                  _isEditing
                                      ? 'Leave blank to keep current'
                                      : 'Enter Password',
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePass
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    onPressed: () => setLocal(
                                      () => _obscurePass = !_obscurePass,
                                    ),
                                  ),
                                ),
                            validator: (v) {
                              if (_isEditing && (v == null || v.trim().isEmpty))
                                return null;
                              if (v == null || v.trim().isEmpty)
                                return 'Please enter the Password';
                              if (v.trim().length < 6)
                                return 'Minimum 6 characters';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Role
                        _label('Role'),
                        const SizedBox(height: 6),
                        SearchableDropdown<String>(
                          value: _selectedRoleId,
                          hint: 'Select Role',
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          items: widget.allRoles.map((r) {
                            return SearchableDropdownItem<String>(
                              value: r['id']?.toString() ?? '',
                              label: r['role_name']?.toString() ?? '',
                            );
                          }).toList(),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Please select the Role'
                              : null,
                          onChanged: (v) => setState(() => _selectedRoleId = v),
                        ),
                        const SizedBox(height: 28),

                        // Action buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
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
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _submitting ? null : _submit,
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
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isEditing ? 'Update' : 'Submit',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Color(0xFF334155),
    ),
  );

  InputDecoration _deco(String hint) => InputDecoration(
    errorStyle: const TextStyle(
      color: Colors.red,
      fontWeight: FontWeight.bold,
      fontSize: 12,
    ),
    hintText: hint,
    counterText: '',
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    isDense: true,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}
