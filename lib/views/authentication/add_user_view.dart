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
  String searchQuery = "";

  // Form State
  int? editingDatabaseId;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String? selectedRoleId;

  @override
  void initState() {
    super.initState();
    fetchUserList();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
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
            Uri.parse('https://display.sriher.com/Registerview'),
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

    try {
      final response = await http
          .post(
            Uri.parse('https://display.sriher.com/regEditview'),
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

        editingDatabaseId = id;
        _userIdController.text =
            u['user_id']?.toString() ?? user['user_id']?.toString() ?? '';
        _userNameController.text =
            u['user_name']?.toString() ?? user['user_name']?.toString() ?? '';
        _passwordController.text = '';
        selectedRoleId =
            u['role_id']?.toString() ?? user['role_id']?.toString();

        _showFormDialog();
      }
    } catch (e) {
      editingDatabaseId = id;
      _userIdController.text = user['user_id']?.toString() ?? '';
      _userNameController.text = user['user_name']?.toString() ?? '';
      selectedRoleId = user['role_id']?.toString();
      _showFormDialog();
    }
  }

  Future<void> handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    final bool isUpdating = editingDatabaseId != null;
    final url = isUpdating
        ? 'https://display.sriher.com/regUpdateview'
        : 'https://display.sriher.com/insertRegisterview';

    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "user_id": _userIdController.text.trim(),
      "user_name": _userNameController.text.trim(),
      "user_password": _passwordController.text.trim(),
      "role_id": selectedRoleId ?? "1",
    };
    if (isUpdating) body["id"] = editingDatabaseId;

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _showSnack(
          isUpdating
              ? "User updated successfully!"
              : "User added successfully!",
        );
        _resetForm();
        await fetchUserList();
      } else {
        _showSnack(
          "Server error (${response.statusCode}). Try again.",
          isError: true,
        );
      }
    } catch (e) {
      _showSnack("Connection failed. Check network.", isError: true);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
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
            Uri.parse('https://display.sriher.com/regUpdateview'),
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

  void _resetForm() {
    setState(() {
      editingDatabaseId = null;
      _userIdController.clear();
      _userNameController.clear();
      _passwordController.clear();
      selectedRoleId = null;
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint("Snackbar error: $e");
    }
  }

  void _showFormDialog() {
    StylishDialog.show(
      context: context,
      title: editingDatabaseId == null ? "Add User" : "Edit User",
      subtitle: "Provide system credentials and role",
      icon: editingDatabaseId == null
          ? Icons.person_add_rounded
          : Icons.edit_note_rounded,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          return Form(
            key: _formKey,
            child: Column(
              children: [
                _buildUserIdInput(),
                const SizedBox(height: 20),
                _buildInput(
                  "User Name",
                  _userNameController,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? "Enter user name" : null,
                ),
                const SizedBox(height: 20),
                _buildInput(
                  "Password",
                  _passwordController,
                  isPass: true,
                  validator: (v) {
                    if (editingDatabaseId != null) return null;
                    if (v == null || v.trim().isEmpty) return "Enter password";
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: selectedRoleId,
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
                      horizontal: 10,
                      vertical: 12,
                    ),
                    hintText: "Select Role",
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  items: allRoles.map((r) {
                    return DropdownMenuItem<String>(
                      value: r['id']?.toString() ?? '',
                      child: Text(r['role_name']?.toString() ?? ''),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedRoleId = v);
                    setState(() => selectedRoleId = v);
                  },
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            _resetForm();
            Navigator.pop(context);
          },
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
        StatefulBuilder(
          builder: (context, setBtnState) {
            return ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (_formKey.currentState!.validate()) {
                        Navigator.pop(context); // Close immediately
                        await handleSubmit();
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
                      editingDatabaseId == null ? "Submit" : "Update",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }

  // ──────────────────────────── BUILD ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final int limit = int.tryParse(entriesValue) ?? 10;
    final List<dynamic> filtered = searchQuery.isEmpty
        ? allUsers
        : allUsers.where((u) {
            final q = searchQuery.toLowerCase();
            return (u['user_id']?.toString().toLowerCase().contains(q) ??
                    false) ||
                (u['user_name']?.toString().toLowerCase().contains(q) ?? false);
          }).toList();
    final List<dynamic> pagedUsers = filtered.take(limit).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SelectionArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const AnimatedHeading(
                  text: "User List",
                  style: TextStyle(  color: Color.fromARGB(255, 64, 164, 246),  fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _resetForm(); // clear any leftover edit state
                    _showFormDialog();
                  },
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                  label: const Text(
                    "ADD USER",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      37,
                      37,
                      37,
                    ).withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildListHeader(),
                  const SizedBox(height: 20),
                  _buildTableContainer(pagedUsers),
                  const SizedBox(height: 20),
                  _buildPagination(pagedUsers.length, filtered.length),
                ],
              ),
            ),
          ],
        ),
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
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: isLoading
          ? const SizedBox(
              height: 400,
              child: Center(child: CircularProgressIndicator()),
            )
          : pagedUsers.isEmpty
          ? const SizedBox(
              height: 400,
              child: Center(
                child: Text("No users found.", style: TextStyle(fontSize: 16)),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      columnSpacing: 24,
                      headingRowHeight: 52,
                      dataRowMaxHeight: 56,
                      headingRowColor: WidgetStateProperty.all(
                          Colors.blue.shade50,
                      ),
                      showCheckboxColumn: false,
                      border: TableBorder.all(color: Colors.grey.shade100),
                      columns: _buildColumns(),
                      rows: pagedUsers.map((u) => _buildRow(u)).toList(),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ── User ID field with up/down stepper ──────────────────────────────────
  Widget _buildUserIdInput() {
    return TextFormField(
      controller: _userIdController,
      keyboardType: TextInputType.number,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? "Enter user id" : null,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF475569),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: "User ID",
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
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
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        // Up / Down stepper arrows
        suffixIcon: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 22,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.black54,
                ),
                onPressed: () {
                  final current =
                      int.tryParse(_userIdController.text.trim()) ?? 0;
                  _userIdController.text = (current + 1).toString();
                  _userIdController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _userIdController.text.length),
                  );
                },
              ),
            ),
            SizedBox(
              width: 28,
              height: 22,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black54,
                ),
                onPressed: () {
                  final current =
                      int.tryParse(_userIdController.text.trim()) ?? 0;
                  _userIdController.text = (current - 1).toString();
                  _userIdController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _userIdController.text.length),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Generic text input ────────────────────────────────────────────────────
Widget _buildInput(
    String hint,
    TextEditingController c, {
    bool isPass = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      obscureText: isPass,
      validator: validator,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF475569),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 13,
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
            color: Color(0xFFEF4444),
            width: 1.2,
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
    );
  }

  Widget _buildRoleDrop() {
    return SearchableDropdown<String>(
      value: selectedRoleId,
      hint: "Select Role",
      items: allRoles.map((r) {
        return SearchableDropdownItem<String>(
          value: r['id'].toString(),
          label: r['role_name'] ?? '',
        );
      }).toList(),
      onChanged: (v) => setState(() => selectedRoleId = v),
    );
  }

  List<DataColumn> _buildColumns() {
    return ["USER ID", "USER NAME", "ROLE", "EDIT", "ACTION"]
        .map(
          (c) => DataColumn(
            label: Text(
              c,
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        )
        .toList();
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
            tooltip: "Edit User",
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

  Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text("Show ", style: TextStyle(fontSize: 14)),
            // STYLED ENTRIES BOX
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
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      entriesValue = v;
                    });
                  }
                },
              ),
            ),
            const Text(" entries", style: TextStyle(fontSize: 14)),
          ],
        ),
       SizedBox(
          width: 250,
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => searchQuery = v),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: "Search ID or Name...",
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(Icons.search, size: 16),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(int showing, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing 1 to $showing of $total entries",
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        Row(
          children: [
            _buildPageBtn("Previous", enabled: false),
            _buildPageBtn("1", active: true),
            _buildPageBtn("Next", enabled: true),
          ],
        ),
      ],
    );
  }

  Widget _buildPageBtn(String t, {bool active = false, bool enabled = true}) {
    return Container(
      margin: EdgeInsets.zero,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? Colors.blue : Colors.white,
          foregroundColor: active ? Colors.white : Colors.black87,
          elevation: 0,
          side: BorderSide(color: active ? Colors.blue : Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: enabled ? () {} : null,
        child: Text(
          t,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
