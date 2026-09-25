import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';

class DefaultTemplateView extends StatefulWidget {
  const DefaultTemplateView({super.key});

  @override
  State<DefaultTemplateView> createState() => _DefaultTemplateViewState();
}

class _DefaultTemplateViewState extends State<DefaultTemplateView> {
  // ──────────────────────────────────────────────────────────────────────────
  // CONFIGURATION
  // ──────────────────────────────────────────────────────────────────────────
  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  // Data Lists
  List<dynamic> _templateList = []; // For the Table
  List<dynamic> _deviceDropdownList = []; // From /deviceview
  List<dynamic> _templateDropdownList = []; // From /new_templateview

  // Form State
  String? _selectedDeviceId;
  String? _selectedCategoryId;
  int? _editingId;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSubmitting = false;

  // Table State
  String _entriesValue = "10";
  String _searchQuery = "";
  int _currentPage = 1;
  
  // Sort State
  int _sortColumnIndex = -1;
  bool _sortAscending = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await _fetchDropdownData();
      await _fetchTableData(showLoading: false);
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // API METHODS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _fetchDropdownData() async {
    try {
      // 1. Fetch Device Types
      final resDevice = await http.post(
        Uri.parse('$_baseUrl/deviceview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      // 2. Fetch Template Names
      final resTemplate = await http.post(
        Uri.parse('$_baseUrl/new_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (mounted) {
        setState(() {
          final devParsed = jsonDecode(resDevice.body)['data'];
          if (devParsed is Map) {
            _deviceDropdownList =
                devParsed['DeviceMasters'] ?? devParsed.values.first ?? [];
          } else if (devParsed is List) {
            _deviceDropdownList = devParsed;
          } else {
            _deviceDropdownList = [];
          }

          final tempParsed = jsonDecode(resTemplate.body)['data'];
          if (tempParsed is Map) {
            _templateDropdownList = tempParsed.values.first ?? [];
          } else if (tempParsed is List) {
            _templateDropdownList = tempParsed;
          } else {
            _templateDropdownList = [];
          }
        });
      }
    } catch (e) {
      _showSnackBar("Error loading dropdowns: $e");
    }
  }

  List<dynamic> _enrichTableData(List<dynamic> templates, List<dynamic> devices) {
    if (templates.isEmpty && devices.isEmpty) return [];

    final List<Map<String, dynamic>> enriched = [];
    final Set<String> processedDeviceIds = {};

    // 1. Process templates first and match with devices
    for (int i = 0; i < templates.length; i++) {
      final t = Map<String, dynamic>.from(templates[i] is Map ? templates[i] : {});
      final tId = t['id']?.toString() ?? '';
      final tName = (t['temp_name'] ?? t['template_name'] ?? '').toString().trim();

      String? devId = (t['device_id'] ?? t['device_ids'] ?? t['Device_id'])?.toString();
      Map<String, dynamic>? matchedDev;

      if (devId != null && devId.isNotEmpty) {
        matchedDev = devices.firstWhere(
          (d) => d['id']?.toString() == devId,
          orElse: () => null,
        );
      }

      if (matchedDev == null && tId.isNotEmpty) {
        matchedDev = devices.firstWhere(
          (d) => d['id']?.toString() == tId,
          orElse: () => null,
        );
      }

      if (matchedDev == null && tName.isNotEmpty) {
        matchedDev = devices.firstWhere(
          (d) {
            final dName = (d['device_name'] ?? d['device_code'] ?? d['type_of_device'] ?? '').toString().trim().toLowerCase();
            final tn = tName.toLowerCase();
            return dName.isNotEmpty && (dName == tn || dName.contains(tn) || tn.contains(dName));
          },
          orElse: () => null,
        );
      }

      if (matchedDev == null && i < devices.length) {
        matchedDev = devices[i] is Map ? devices[i] : null;
      }

      if (matchedDev != null) {
        t['device_id'] = matchedDev['id']?.toString();
        t['device_name'] = matchedDev['device_name'] ?? matchedDev['type_of_device'] ?? matchedDev['device_code'];
        t['type_of_device'] = matchedDev['type_of_device'] ?? matchedDev['device_name'];
        processedDeviceIds.add(matchedDev['id'].toString());
      }

      t['temp_id'] = tId;
      enriched.add(t);
    }

    // 2. Process any remaining unmatched devices
    for (int i = 0; i < devices.length; i++) {
      final d = Map<String, dynamic>.from(devices[i] is Map ? devices[i] : {});
      final dId = d['id']?.toString() ?? '';
      if (processedDeviceIds.contains(dId)) continue;

      final dName = (d['device_name'] ?? d['type_of_device'] ?? d['device_code'] ?? '').toString().trim();

      Map<String, dynamic>? matchedTemp = templates.firstWhere(
        (t) {
          final tName = (t['temp_name'] ?? t['template_name'] ?? '').toString().trim().toLowerCase();
          final dn = dName.toLowerCase();
          return tName.isNotEmpty && dn.isNotEmpty && (tName == dn || tName.contains(dn) || dn.contains(tName));
        },
        orElse: () => null,
      );

      if (matchedTemp != null) {
        d['temp_id'] = matchedTemp['id']?.toString();
        d['temp_name'] = matchedTemp['temp_name'] ?? matchedTemp['template_name'];
      } else if (i < templates.length) {
        final t = templates[i];
        d['temp_id'] = t['id']?.toString();
        d['temp_name'] = t['temp_name'] ?? t['template_name'];
      }

      d['device_id'] = dId;
      enriched.add(d);
    }

    return enriched;
  }

  Future<void> _fetchTableData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final resDevice = await http.post(
        Uri.parse('$_baseUrl/deviceview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      final resTemplate = await http.post(
        Uri.parse('$_baseUrl/new_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (mounted) {
        List<dynamic> devList = [];
        List<dynamic> tempList = [];

        if (resDevice.statusCode == 200) {
          final devParsed = jsonDecode(resDevice.body)['data'];
          if (devParsed is Map) {
            devList = devParsed['DeviceMasters'] ?? devParsed.values.first ?? [];
          } else if (devParsed is List) {
            devList = devParsed;
          }
        }

        if (resTemplate.statusCode == 200) {
          final tempParsed = jsonDecode(resTemplate.body)['data'];
          if (tempParsed is List) {
            tempList = tempParsed;
          } else if (tempParsed is Map) {
            tempList = tempParsed.values.first ?? [];
          }
        }

        setState(() {
          _deviceDropdownList = devList;
          _templateDropdownList = tempList;
          _templateList = _enrichTableData(tempList, devList);
        });
      }
    } catch (e) {
      _showSnackBar("Sync Error: $e");
    } finally {
      if (showLoading && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitAction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Convert selected device ID to a list of ints for the API
      final List<int> deviceIdInts = [];
      if (_selectedDeviceId != null && _selectedDeviceId!.isNotEmpty) {
        final parsed = int.tryParse(_selectedDeviceId!);
        if (parsed != null) deviceIdInts.add(parsed);
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/insert_default'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "device_id": deviceIdInts,
          "temp_id": _selectedCategoryId,
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar(
          _editingId == null ? "Submitted successfully" : "Updated successfully",
        );
        _resetForm();
        _fetchTableData();
      }
    } catch (e) {
      _showSnackBar("Action failed: $e");
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteItem(dynamic id) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/deleteNew_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id}),
      );
      if (response.statusCode == 200) {
        _showSnackBar("Item Deleted");
        _fetchTableData();
      }
    } catch (e) {
      _showSnackBar("Delete failed");
    }
  }

  Future<void> _toggleStatus(dynamic id, dynamic currentStatus) async {
    try {
      final int newStatus = (currentStatus == 1 || currentStatus == "1")
          ? 0
          : 1;
      await http.post(
        Uri.parse('$_baseUrl/new_templateStatusUpdateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": id, "status": newStatus}),
      );
      _fetchTableData();
    } catch (e) {
      debugPrint("Status error: $e");
    }
  }

  /// Parses device_id from a table row item into a list of string IDs.
  /// Handles: List [1,2,3], comma-separated "1,2,3", single int/string.
  List<String> _parseDeviceIds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return [];
    // Handle "[1, 2, 3]" string format
    final cleaned = str.replaceAll('[', '').replaceAll(']', '');
    return cleaned.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// Resolves a list of device IDs to their display names from _deviceDropdownList.
  String _resolveDeviceNames(List<String> ids) {
    if (ids.isEmpty) return "-";
    final names = <String>[];
    for (final id in ids) {
      final dev = _deviceDropdownList.firstWhere(
        (d) => d['id']?.toString() == id,
        orElse: () => null,
      );
      if (dev != null) {
        names.add((dev['device_name'] ?? dev['type_of_device'] ?? dev['device_code'] ?? dev['Device_name'] ?? id).toString());
      } else {
        names.add(id);
      }
    }
    return names.isNotEmpty ? names.join(', ') : "-";
  }

  void _editItem(dynamic item) {
    debugPrint("=== EDIT ITEM DEBUG ===");
    debugPrint("Item keys: ${item.keys.toList()}");
    debugPrint("Item data: $item");

    String? matchedDeviceId;

    // 1. Direct device_id in item
    final rawDeviceId = (item['device_id'] ?? item['device_ids'] ?? item['Device_id'])?.toString().trim();
    if (rawDeviceId != null && rawDeviceId.isNotEmpty) {
      final parsed = _parseDeviceIds(rawDeviceId);
      for (final id in parsed) {
        if (_deviceDropdownList.any((d) => d['id']?.toString() == id)) {
          matchedDeviceId = id;
          break;
        }
      }
    }

    // 2. Direct device ID match (when item['id'] is device id)
    if (matchedDeviceId == null && item['id'] != null) {
      final idStr = item['id'].toString();
      if (_deviceDropdownList.any((d) => d['id']?.toString() == idStr)) {
        matchedDeviceId = idStr;
      }
    }

    // 3. Match by device_name / type_of_device
    if (matchedDeviceId == null) {
      final itemDeviceName = (item['device_name'] ?? item['Device_name'] ?? item['device_code'] ?? item['type_of_device'] ?? item['device_type'] ?? '').toString().trim();
      if (itemDeviceName.isNotEmpty) {
        for (var d in _deviceDropdownList) {
          final dName = (d['device_name'] ?? d['device_code'] ?? d['type_of_device'] ?? d['Device_name'] ?? '').toString().trim();
          if (dName.isNotEmpty && dName.toLowerCase() == itemDeviceName.toLowerCase()) {
            matchedDeviceId = d['id'].toString();
            break;
          }
        }
      }
    }

    // Resolve template ID
    String? matchedTemplateId;
    final rawTempId = (item['temp_id'] ?? item['template_id'])?.toString().trim();
    if (rawTempId != null && rawTempId.isNotEmpty) {
      if (_templateDropdownList.any((t) => t['id']?.toString() == rawTempId)) {
        matchedTemplateId = rawTempId;
      }
    }

    if (matchedTemplateId == null && item['id'] != null) {
      final idStr = item['id'].toString();
      if (_templateDropdownList.any((t) => t['id']?.toString() == idStr)) {
        matchedTemplateId = idStr;
      }
    }

    if (matchedTemplateId == null) {
      final String itemTempName = (item['temp_name'] ?? item['template_name'] ?? '').toString().trim();
      if (itemTempName.isNotEmpty) {
        for (var t in _templateDropdownList) {
          final tName = (t['temp_name'] ?? t['template_name'] ?? '').toString().trim();
          if (tName.isNotEmpty && tName.toLowerCase() == itemTempName.toLowerCase()) {
            matchedTemplateId = t['id']?.toString();
            break;
          }
        }
      }
    }

    debugPrint("Parsed deviceId: $matchedDeviceId, templateId: $matchedTemplateId");

    setState(() {
      _editingId = int.tryParse(item['id'].toString());
      _selectedDeviceId = matchedDeviceId;
      _selectedCategoryId = matchedTemplateId;
    });

    _showDefaultTemplateDialog();
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _selectedDeviceId = null;
      _selectedCategoryId = null;
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POPUP DIALOG
  // ──────────────────────────────────────────────────────────────────────────

  void _showDefaultTemplateDialog() {
    // Capture current selections into local dialog-scoped variables
    String? dialogDeviceId = _selectedDeviceId;
    String? dialogCategoryId = _selectedCategoryId;

    StylishDialog.show(
      context: context,
      title: _editingId == null
          ? "Create Default Template"
          : "Edit Default Template",
      titleStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      subtitle: "Assign a default template to a device type",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      maxWidth: 480,
      builder: (dialogContext, setDialogState) {
        String? safeDeviceId;
        if (dialogDeviceId != null && dialogDeviceId!.isNotEmpty) {
          if (_deviceDropdownList.any((i) => i['id']?.toString() == dialogDeviceId)) {
            safeDeviceId = dialogDeviceId;
          }
        }

        String? safeTemplateId;
        if (dialogCategoryId != null && dialogCategoryId!.isNotEmpty) {
          if (_templateDropdownList.any((i) => i['id']?.toString() == dialogCategoryId)) {
            safeTemplateId = dialogCategoryId;
          }
        }

        return Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Device Type",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: safeDeviceId,
                isExpanded: true,
                menuMaxHeight: 250,
                dropdownColor: Colors.white,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Please select a Device Type' : null,
                decoration: InputDecoration(
                  hintText: "Select Device Type",
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                items: _deviceDropdownList.map((item) {
                  final name = (item['device_name'] ??
                          item['device_code'] ??
                          item['Device_name'] ??
                          '')
                      .toString();
                  return DropdownMenuItem<String>(
                    value: item['id'].toString(),
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() {
                    dialogDeviceId = val;
                    safeDeviceId = val;
                  });
                  setState(() => _selectedDeviceId = val);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                "Template Name",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: safeTemplateId,
                isExpanded: true,
                menuMaxHeight: 250,
                dropdownColor: Colors.white,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Please select a Template Name' : null,
                decoration: InputDecoration(
                  hintText: "Select Template Name",
                  hintStyle:
                      const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                items: _templateDropdownList.map((item) {
                  final name =
                      (item['temp_name'] ?? item['template_name'] ?? '')
                          .toString();
                  return DropdownMenuItem<String>(
                    value: item['id'].toString(),
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() {
                    dialogCategoryId = val;
                    safeTemplateId = val;
                  });
                  setState(() => _selectedCategoryId = val);
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _resetForm();
                      Navigator.pop(dialogContext);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
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
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            if (_formKey.currentState!.validate()) {
                              if (_selectedDeviceId == null ||
                                  _selectedDeviceId!.isEmpty ||
                                  _selectedCategoryId == null ||
                                  _selectedCategoryId!.isEmpty) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Please fill in all required fields'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(dialogContext);
                              await _submitAction();
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
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _editingId == null ? 'Submit' : 'Update',
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
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI BUILDERS
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final heading = const AnimatedHeading(
      text: "Default Templates",
      style: TextStyle(
        color: Color.fromARGB(255, 33, 150, 243),
        fontWeight: FontWeight.bold,
        fontSize: 22,
      ),
    );

    final createBtn = ElevatedButton.icon(
      onPressed: _showDefaultTemplateDialog,
      icon: Icon(Icons.settings_applications, size: isMobile ? 14 : 20),
      style: isMobile
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(80, 32),
            )
          : null,
      label: Text(
        "CREATE DEFAULT TEMPLATE",
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
            Align(
              alignment: isMobile ? Alignment.center : Alignment.centerLeft,
              child: heading,
            ),
            const SizedBox(height: 16),
            isMobile
                ? _buildRightListContent(
                    isMobile: isMobile,
                    createBtn: createBtn,
                  )
                : Expanded(
                    child: _buildRightListContent(
                      isMobile: isMobile,
                      createBtn: createBtn,
                    ),
                  ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SelectionArea(
        child: isMobile
            ? SingleChildScrollView(
                child: bodyContent,
              )
            : bodyContent,
      ),
    );
  }

  Widget _buildRightListContent({bool isMobile = false, Widget? createBtn}) {
    if (_isLoading && _templateList.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    List<dynamic> filtered = _templateList.where((item) {
      final devName = (item['device_name'] ?? item['type_of_device'] ?? item['device_code'] ?? "").toString().toLowerCase();
      final tempName = (item['temp_name'] ?? item['template_name'] ?? "").toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return devName.contains(q) || tempName.contains(q);
    }).toList();

    filtered.sort((a, b) {
      String aVal = "";
      String bVal = "";

      switch (_sortColumnIndex) {
        case 0:
          final idsA = _parseDeviceIds(a['device_id']);
          aVal = idsA.isNotEmpty
              ? _resolveDeviceNames(idsA).toLowerCase()
              : (a['device_name'] ?? a['type_of_device'] ?? a['Device_name'] ?? a['device_code'] ?? "").toString().toLowerCase();

          final idsB = _parseDeviceIds(b['device_id']);
          bVal = idsB.isNotEmpty
              ? _resolveDeviceNames(idsB).toLowerCase()
              : (b['device_name'] ?? b['type_of_device'] ?? b['Device_name'] ?? b['device_code'] ?? "").toString().toLowerCase();
          break;

        case 1:
          aVal = (a['temp_name'] ?? a['template_name'] ?? "").toString().toLowerCase();
          bVal = (b['temp_name'] ?? b['template_name'] ?? "").toString().toLowerCase();
          break;
      }

      return _sortAscending ? aVal.compareTo(bVal) : bVal.compareTo(aVal);
    });

    final int perPage = int.tryParse(_entriesValue) ?? 10;
    final int startIdx = (_currentPage - 1) * perPage;
    final paginated = filtered.skip(startIdx).take(perPage).toList();

    final dataTableWidget = LayoutBuilder(
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
                columns: [
                  _buildTableCol('Device Name', 0),
                  _buildTableCol('Template Name', 1),
                  _buildTableCol('Edit', -1),
                ],
                rows: paginated.map((item) {
                  // Resolve device name
                  final deviceIds = _parseDeviceIds(item['device_id']);
                  String resolvedName;
                  if (deviceIds.isNotEmpty) {
                    resolvedName = _resolveDeviceNames(deviceIds);
                  } else {
                    resolvedName = (item['device_name'] ??
                            item['type_of_device'] ??
                            item['Device_name'] ??
                            item['device_code'] ??
                            "-")
                        .toString();
                  }

                  // Resolve template name
                  String resolvedTempName = (item['temp_name'] ?? item['template_name'] ?? "-").toString();
                  if (resolvedTempName == "-") {
                    final tempId = (item['temp_id'] ?? item['template_id'])?.toString();
                    if (tempId != null) {
                      final matchedTemp = _templateDropdownList.firstWhere(
                        (t) => t['id']?.toString() == tempId,
                        orElse: () => null,
                      );
                      if (matchedTemp != null) {
                        resolvedTempName = (matchedTemp['temp_name'] ?? matchedTemp['template_name'] ?? "-").toString();
                      }
                    }
                  }

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          resolvedName,
                          style: const TextStyle(fontSize: 12.0),
                        ),
                      ),
                      DataCell(
                        Text(
                          resolvedTempName,
                          style: const TextStyle(fontSize: 12.0),
                        ),
                      ),
                      DataCell(
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.blue,
                            size: 20,
                          ),
                          onPressed: () => _editItem(item),
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

    return Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTableControls(isMobile: isMobile, createBtn: createBtn),
        const SizedBox(height: 15),
        isMobile
            ? SizedBox(
                height: 300,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (_templateList.isNotEmpty && filtered.isEmpty)
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
                                "No matching devices found",
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
                      : dataTableWidget,
                ),
              )
            : Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (_templateList.isNotEmpty && filtered.isEmpty)
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
                                "No matching devices found",
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
                      : dataTableWidget,
                ),
              ),
        const SizedBox(height: 15),
        _buildTableFooter(filtered.length, isMobile: isMobile),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WIDGET HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLabel(String text, {Color color = Colors.black87}) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
    ),
  );

  Widget _buildDropdown(
    String? value,
    List<dynamic> items,
    String idKey,
    String nameKey,
    String hint,
    Function(String?) onChanged, {
    String? Function(String?)? validator,
  }) {
    String? validValue = items.any((i) => i[idKey].toString() == value) ? value : null;

    return DropdownButtonFormField<String>(
      value: validValue,
      isExpanded: true,
      menuMaxHeight: 250,
      dropdownColor: Colors.white,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      style: const TextStyle(color: Colors.black87, fontSize: 13),
      items: items.map((item) {
        final displayName = item[nameKey] ?? item['device_code'] ?? item['temp_name'] ?? item['Device_name'] ?? "";
        return DropdownMenuItem<String>(
          value: item[idKey].toString(),
          child: Text(displayName.toString()),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTableControls({bool isMobile = false, Widget? createBtn}) {
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
            value: _entriesValue,
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
              _entriesValue = v!;
              _currentPage = 1;
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
          onChanged: (v) => setState(() {
            _searchQuery = v;
            _currentPage = 1;
          }),
          style: const TextStyle(color: Colors.black87, fontSize: 12),
          decoration: InputDecoration(
            hintText: "Search devices...",
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
            children: [
              showEntries,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  searchBox,
                  if (createBtn != null) ...[
                    const SizedBox(width: 12),
                    createBtn,
                  ],
                ],
              ),
            ],
          );
  }

  DataColumn _buildTableCol(String label, int colIndex) {
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
            _currentPage = 1;
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

  Widget _buildTableFooter(int total, {bool isMobile = false}) {
    final int perPage = int.tryParse(_entriesValue) ?? 10;
    final int start = (_currentPage - 1) * perPage + 1;
    final int end = (start + perPage - 1 < total) ? start + perPage - 1 : total;

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
        _buildSquareBtn(
          "Previous",
          _currentPage > 1,
          () => setState(() => _currentPage--),
        ),
        ..._buildPageNumbers(total, perPage),
        _buildSquareBtn(
          "Next",
          end < total,
          () => setState(() => _currentPage++),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: isMobile
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
            ),
    );
  }

  List<Widget> _buildPageNumbers(int total, int perPage) {
    int totalPages = (total / perPage).ceil();
    if (totalPages <= 1) return [];

    final visibleCount = totalPages.clamp(1, 3);
    int windowStart = _currentPage - 1; // Try to center around current page
    if (windowStart < 1) windowStart = 1;
    if (windowStart + visibleCount - 1 > totalPages) {
      windowStart = totalPages - visibleCount + 1;
      if (windowStart < 1) windowStart = 1;
    }
    
    List<Widget> widgets = [];
    for (int i = windowStart; i < windowStart + visibleCount; i++) {
      final idx = i;
      widgets.add(
        _buildSquareBtn(
          "$idx",
          true,
          () => setState(() => _currentPage = idx),
          isActive: _currentPage == idx,
        ),
      );
    }
    return widgets;
  }

  Widget _buildSquareBtn(
    String label,
    bool enabled,
    VoidCallback? onTap, {
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
