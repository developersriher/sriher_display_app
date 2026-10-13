import 'dart:ui';
import '../../api_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  final ScrollController _hScroll = ScrollController();

  final Map<int, int> _statusOverrides = {};

  @override
  void initState() {
    super.initState();
    _loadPersistedStatuses();
    fetchUserList();
  }

  Future<void> _loadPersistedStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('user_status_overrides');
      if (str != null) {
        final decoded = jsonDecode(str) as Map<String, dynamic>;
        setState(() {
          decoded.forEach((k, v) {
            final id = int.tryParse(k);
            final val = int.tryParse(v.toString());
            if (id != null && val != null) {
              _statusOverrides[id] = val;
            }
          });
        });
      }
    } catch (_) {}
  }

  Future<void> _persistStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringKeyMap = _statusOverrides.map((k, v) => MapEntry(k.toString(), v));
      await prefs.setString('user_status_overrides', jsonEncode(stringKeyMap));
    } catch (_) {}
  }

  bool _isUserActive(dynamic user) {
    if (user is! Map) return true;
    final rawId = user['id'] ?? user['ID'];
    final id = int.tryParse(rawId?.toString() ?? '') ?? int.tryParse(user['user_id']?.toString() ?? '');
    if (id != null && _statusOverrides.containsKey(id)) {
      return _statusOverrides[id] == 0;
    }
    final raw = user['status'] ?? user['Status'] ?? user['active_status'];
    final statusInt = int.tryParse(raw?.toString() ?? '0') ?? 0;
    return statusInt == 0;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  // ──────────────────────────── API CALLS ────────────────────────────────────

  Future<void> fetchUserList({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() => isLoading = true);
    }
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
        // Explicitly unwrap {"data": {"users": [...], "roles": [...]}}
        final outerData = (res is Map && res.containsKey('data')) ? res['data'] : res;
        final rawUsers = (outerData is Map && outerData.containsKey('users'))
            ? outerData['users']
            : (outerData is Map && outerData.containsKey('data'))
                ? outerData['data']
                : (res is Map && res.containsKey('users'))
                    ? res['users']
                    : [];
        final List<dynamic> parsedUsers = (rawUsers as List).map((u) {
          if (u is Map) {
            final map = Map<String, dynamic>.from(u);
            final rawId = map['id'] ?? map['ID'];
            final id = int.tryParse(rawId?.toString() ?? '') ?? int.tryParse(map['user_id']?.toString() ?? '');
            if (id != null && _statusOverrides.containsKey(id)) {
              map['status'] = _statusOverrides[id];
              map['Status'] = _statusOverrides[id];
            } else {
              final raw = map['status'] ?? map['Status'];
              if (raw != null) {
                map['status'] = int.tryParse(raw.toString()) ?? 0;
                map['Status'] = map['status'];
              }
            }
            return map;
          }
          return u;
        }).toList();
        final rawRoles = (outerData is Map ? outerData['roles'] : (res is Map ? res['roles'] : null)) ?? [];
        if (!mounted) return;
        setState(() {
          allUsers = parsedUsers;
          allRoles = rawRoles is List ? rawRoles : [];
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
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
    if (isUpdating) {
      body["id"] = editId;
      final existing = allUsers.firstWhere(
        (u) => (u['id'] ?? u['ID'])?.toString() == editId.toString(),
        orElse: () => null,
      );
      if (existing != null && existing is Map) {
        body["status"] = int.tryParse(existing['status']?.toString() ?? '0') ?? 0;
      }
    } else {
      body["status"] = 0;
    }

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

  Future<void> toggleStatus(dynamic idOrUser, [dynamic currentStatus]) async {
    try {
      dynamic id;
      dynamic rawStatus;

      if (idOrUser is Map) {
        id = idOrUser['id'] ?? idOrUser['ID'] ?? idOrUser['user_id'];
        rawStatus = idOrUser['status'] ?? idOrUser['Status'] ?? currentStatus;
      } else {
        id = idOrUser;
        rawStatus = currentStatus;
      }

      // Active = 0, Inactive = 1 for users
      final int parsedStatus = int.tryParse(rawStatus?.toString() ?? '0') ?? 0;
      final int newStatusVal = (parsedStatus == 0) ? 1 : 0;

      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text("Confirm Action", textAlign: TextAlign.center),
            content: Text(
              newStatusVal == 0
                  ? "Do you want to set this item as active?"
                  : "Do you want to set this item as inactive?",
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

      final int userId = int.tryParse(id?.toString() ?? '0') ?? 0;

      // Find the full user record so we can mirror _handleSubmit's payload exactly
      final userItem = allUsers.firstWhere(
        (u) => (u['id'] ?? u['ID'])?.toString() == id?.toString(),
        orElse: () => null,
      );

      // Mirror the exact payload structure that the working Edit Modal uses
      // (see _handleSubmit / regUpdateview). All required fields must be present.
      final Map<String, dynamic> body = {
        "api_key": _apiKey,
        "id": userId,
        "user_id": userItem is Map ? (userItem['user_id']?.toString() ?? '') : '',
        "user_name": userItem is Map ? (userItem['user_name']?.toString() ?? '') : '',
        "role_id": userItem is Map ? (userItem['role_id']?.toString() ?? '') : '',
        "status": newStatusVal,
      };
      // Include other optional fields the server may reference
      if (userItem is Map && userItem['user_email'] != null) {
        body['user_email'] = userItem['user_email'];
      }

      // Send update ONLY to the update endpoint — NOT to the fetch endpoint
      final response = await http.post(
        Uri.parse('${getBaseUrl()}/regUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Validate backend response body for actual success
        bool backendSuccess = false;
        String backendMsg = '';
        try {
          final resJson = jsonDecode(response.body);
          if (resJson is Map) {
            backendSuccess = resJson['status'] == true ||
                resJson['status'] == 'true' ||
                (resJson['message']?.toString().toLowerCase().contains('success') ?? false) ||
                resJson['success'] == true;
            backendMsg = resJson['message']?.toString() ?? '';
          }
          // If backend doesn't include a status/message field, treat HTTP 200 as success
          if (!backendSuccess && backendMsg.isEmpty) {
            backendSuccess = true;
          }
        } catch (_) {
          // If body isn't JSON, treat HTTP 200 as success
          backendSuccess = true;
        }

        if (backendSuccess) {
          // Update local state ONLY after server confirms
          setState(() {
            _statusOverrides[userId] = newStatusVal;
            final idx = allUsers.indexWhere((u) => (u['id'] ?? u['ID'])?.toString() == id?.toString());
            if (idx != -1) {
              allUsers[idx]['status'] = newStatusVal;
              allUsers[idx]['Status'] = newStatusVal;
            }
          });
          await _persistStatuses();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newStatusVal == 0
                  ? "User has been successfully activated."
                  : "User has been successfully deactivated."),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          fetchUserList(showLoading: false);
        } else {
          // Backend returned 200 but indicated failure
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(backendMsg.isNotEmpty
                  ? "Update failed: $backendMsg"
                  : "Update failed. Please try again."),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // HTTP error
        String errorMsg = 'Server error (${response.statusCode})';
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson['message'] != null) {
            errorMsg = errJson['message'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Toggle Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Connection failed: $e"),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> deleteUser(dynamic user) async {
    final id = int.tryParse(user['id']?.toString() ?? '');
    if (id == null) return;
    _statusOverrides.remove(id);
    await _persistStatuses();

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
              "id": id,
              "status": 1,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _showSnack("User deleted successfully.");
        // Don't re-fetch — the server marks status:1 but still returns the user.
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
        // Default sort: by DB id ascending
        final intA = aVal.startsWith('temp_')
            ? 999999999
            : (int.tryParse(aVal) ?? 0);
        final intB = bVal.startsWith('temp_')
            ? 999999999
            : (int.tryParse(bVal) ?? 0);
        return intA.compareTo(intB);
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
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13.0,
                              ),
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
    // ── Header row ────────────────────────────────────────────────────────────
    final header = Container(
      height: 52,
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
          // USER ID – flex 2, left
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'USER ID',
                      style: TextStyle(
                        color: Color.fromRGBO(33, 150, 243, 1),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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
                            child: Icon(Icons.arrow_drop_up, size: 14,
                              color: _sortColumnIndex == 0 && _sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 0;
                            _sortAscending = false;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(Icons.arrow_drop_down, size: 14,
                              color: _sortColumnIndex == 0 && !_sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // USER NAME – flex 3, left
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'USER NAME',
                      style: TextStyle(
                        color: Color.fromRGBO(33, 150, 243, 1),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 1;
                            _sortAscending = true;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(Icons.arrow_drop_up, size: 14,
                              color: _sortColumnIndex == 1 && _sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 1;
                            _sortAscending = false;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(Icons.arrow_drop_down, size: 14,
                              color: _sortColumnIndex == 1 && !_sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ROLE – flex 2, left
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ROLE',
                      style: TextStyle(
                        color: Color.fromRGBO(33, 150, 243, 1),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 2;
                            _sortAscending = true;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(Icons.arrow_drop_up, size: 14,
                              color: _sortColumnIndex == 2 && _sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _sortColumnIndex = 2;
                            _sortAscending = false;
                          }),
                          child: Align(
                            heightFactor: 0.5,
                            child: Icon(Icons.arrow_drop_down, size: 14,
                              color: _sortColumnIndex == 2 && !_sortAscending ? Colors.blue : const Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // EDIT – flex 1, center
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
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
          // ACTION – flex 1, right
          Expanded(
            flex: 1,
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

    Widget buildRows() {
      if (isLoading) {
        return const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (allUsers.isNotEmpty && pagedUsers.isEmpty) {
        return SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 48, color: Colors.blue.shade200),
                const SizedBox(height: 12),
                Text('No matching users found',
                  style: TextStyle(color: Colors.blue.shade900, fontSize: 16.0, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Try a different search term',
                  style: TextStyle(color: Colors.grey, fontSize: 13.0)),
              ],
            ),
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: pagedUsers.asMap().entries.map((entry) {
          final index = entry.key;
          final u = entry.value;
          final sNo = ((currentPage - 1) * (int.tryParse(entriesValue) ?? 10)) + index + 1;
          final roleName = allRoles.firstWhere(
            (r) => r['id']?.toString() == u['role_id']?.toString(),
            orElse: () => {'role_name': 'User'},
          )['role_name'] ?? 'User';
          final isActive = _isUserActive(u);
          return Container(
            height: 52,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1.0),
              ),
            ),
            child: Row(
              children: [
                // S.NO – flex 1
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Text(
                        sNo.toString(),
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                // USER ID – flex 2
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Text(
                        u['user_id']?.toString() ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                // USER NAME – flex 3
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        u['user_name']?.toString() ?? '-',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                // ROLE – flex 2
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          roleName.toString(),
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                // EDIT – flex 1, center
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.center,
                    child: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                      onPressed: () => loadForEdit(u),
                      tooltip: 'Edit',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ),
                // ACTION – flex 1, right
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          // Active = 0 (green/on), Inactive = 1 (grey/off)
                          value: (int.tryParse(u['status']?.toString() ?? '0') ?? 0) == 0,
                          activeColor: Colors.green,
                          onChanged: (v) => toggleStatus(u),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
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
                children: [header, buildRows()],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListHeader({bool isMobile = false, Widget? addUserBtn}) {
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
            items: [
              "10",
              "25",
              "50",
              "100",
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
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
          onChanged: (v) => setState(() {
            searchQuery = v;
            currentPage = 1;
          }),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Search ID or Name...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
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
      },
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
              children: [showingText, const SizedBox(height: 10), pagination],
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
  bool _isPasswordObscured = true;

  bool get _isEditing => widget.editId != null;

  @override
  void initState() {
    super.initState();
    _userIdCtrl = TextEditingController(text: widget.initUserId);
    _userNameCtrl = TextEditingController(text: widget.initUserName);
    _passCtrl = TextEditingController(text: _isEditing ? '' : widget.initPassword);

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

    String finalPassword = _passCtrl.text.trim();
    if (_isEditing && finalPassword.isEmpty) {
      finalPassword = '';
    }

    await widget.onSubmit(
      editId: widget.editId,
      userId: _userIdCtrl.text.trim(),
      userName: _userNameCtrl.text.trim(),
      password: finalPassword,
      roleId: _selectedRoleId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? screenWidth * 0.95 : 550,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header background: Gradient matching department.dart StylishDialog with top-left and top-right rounded corners
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: isMobile ? 14 : 18,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    // Header content: White user icon inside a translucent box (Colors.white.withOpacity(0.2))
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isEditing
                            ? Icons.manage_accounts_rounded
                            : Icons.person_add_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Bold white title, and white subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isEditing ? "Edit User" : "Add User",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "Provide system credentials and role",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action: Include a white close IconButton (Icons.close) at top-right to close the modal
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                      tooltip: "Close",
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // ── Form fields ──
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                            if (v == null || v.trim().isEmpty)
                              return 'Please enter the User ID';
                            final clean = v.trim().toLowerCase();
                            final exists = widget.allUsers.any((u) {
                              final uid = (u['user_id'] ?? u['userId'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              final id = u['id'] ?? u['ID'];
                              if (widget.editId != null &&
                                  id?.toString() == widget.editId?.toString())
                                return false;
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
                            obscureText: _isPasswordObscured,
                            enabled: true,
                            readOnly: false,
                            maxLength: 20,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                            ),
                            decoration: _deco(_isEditing ? 'Enter new password' : 'Enter Password').copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordObscured
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() => _isPasswordObscured = !_isPasswordObscured);
                                  setLocal(() {});
                                },
                              ),
                            ),
                            validator: (v) {
                              if (!_isEditing && (v == null || v.trim().isEmpty))
                                return 'Please enter the Password';
                              if (v != null && v.trim().isNotEmpty && v.trim().length < 6)
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
