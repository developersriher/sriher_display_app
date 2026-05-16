import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

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

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
    _fetchTableData();
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
          } else {
            _deviceDropdownList = devParsed ?? [];
          }

          final tempParsed = jsonDecode(resTemplate.body)['data'];
          if (tempParsed is Map) {
            _templateDropdownList = tempParsed.values.first ?? [];
          } else {
            _templateDropdownList = tempParsed ?? [];
          }
        });
      }
    } catch (e) {
      _showSnackBar("Error loading dropdowns: $e");
    }
  }

  Future<void> _fetchTableData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateview'), // Reusing this for the list
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final dataField = decoded['data'];
        setState(() {
          if (dataField is List) {
            _templateList = dataField;
          } else if (dataField is Map) {
            _templateList = dataField.values.first ?? [];
          } else {
            _templateList = [];
          }
        });
      }
    } catch (e) {
      _showSnackBar("Sync Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    // DISMISS NOW HANDLED IN BUTTON PRESS

    try {
      // Find the name of the selected device to send as device_name
      final selectedDevice = _deviceDropdownList.firstWhere(
        (element) => element['id'].toString() == _selectedDeviceId,
        orElse: () => {},
      );
      final String deviceName = selectedDevice['device_name'] ?? "Unknown";

      // Find the name of the selected template to send as template_name
      final selectedTemplate = _templateDropdownList.firstWhere(
        (element) => element['id'].toString() == _selectedCategoryId,
        orElse: () => {},
      );
      final String templateName = selectedTemplate['temp_name'] ?? "Unknown";

      final url = _editingId == null
          ? '/insertNew_templateview'
          : '/new_templateUpdateview';
      Map<String, dynamic> body = {
        "api_key": _apiKey,
        "device_name": deviceName,
        "template_name": templateName,
      };
      if (_editingId != null) body["id"] = _editingId!;

      final response = await http.post(
        Uri.parse('$_baseUrl$url'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
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

  void _editItem(dynamic item) {
    debugPrint("=== EDIT ITEM DEBUG ===");
    debugPrint("Item keys: ${item.keys.toList()}");
    debugPrint("Item data: $item");

    // Resolve the device name from the item using all possible keys
    final String itemDeviceName =
        (item['device_name'] ??
                item['Device_name'] ??
                item['device_code'] ??
                '')
            .toString()
            .trim();
    final String? itemDeviceId = item['device_id']?.toString();

    debugPrint("Resolved device name from item: '$itemDeviceName'");
    debugPrint("Device ID from item: '$itemDeviceId'");

    // Find matching device from dropdown list
    String? deviceId;
    for (var d in _deviceDropdownList) {
      final dName = (d['device_name'] ?? '').toString().trim();
      final dId = d['id']?.toString();
      final dDevId = d['device_id']?.toString();

      if ((itemDeviceId != null &&
              itemDeviceId.isNotEmpty &&
              (dId == itemDeviceId || dDevId == itemDeviceId)) ||
          (itemDeviceName.isNotEmpty &&
              dName.toLowerCase() == itemDeviceName.toLowerCase())) {
        deviceId = dId;
        debugPrint("MATCHED device: dName='$dName', dId='$dId'");
        break;
      }
    }

    // Resolve the template name from the item
    final String itemTempName =
        (item['temp_name'] ?? item['template_name'] ?? '').toString().trim();
    final String? itemTemplateId = item['template_id']?.toString();

    debugPrint("Resolved template name from item: '$itemTempName'");

    // Find matching template from dropdown list
    String? templateId;
    for (var t in _templateDropdownList) {
      final tName = (t['temp_name'] ?? '').toString().trim();
      final tId = t['id']?.toString();

      if ((itemTemplateId != null &&
              itemTemplateId.isNotEmpty &&
              tId == itemTemplateId) ||
          (itemTempName.isNotEmpty &&
              tName.toLowerCase() == itemTempName.toLowerCase())) {
        templateId = tId;
        debugPrint("MATCHED template: tName='$tName', tId='$tId'");
        break;
      }
    }

    debugPrint("Final deviceId: $deviceId, templateId: $templateId");

    setState(() {
      _editingId = int.tryParse(item['id'].toString());
      _selectedDeviceId = deviceId;
      _selectedCategoryId = templateId;
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
    String? dialogDeviceId = _selectedDeviceId;
    String? dialogCategoryId = _selectedCategoryId;

    StylishDialog.show(
      context: context,
      title: _editingId == null
          ? "Create Default Template"
          : "Edit Default Template",
      subtitle: "Assign a default template to a device type",
      subtitleStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      maxWidth: 480,
      builder: (context, setDialogState) {
        return Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _buildDropdown(
              dialogDeviceId,
              _deviceDropdownList,
              "id",
              "device_name",
              "Select Device Type",
              (val) {
                setDialogState(() => dialogDeviceId = val);
                setState(() => _selectedDeviceId = val);
              },
              validator: (v) => (v == null || v.isEmpty) ? 'Select the Device Type' : null,
            ),
            const SizedBox(height: 16),
            _buildDropdown(
              dialogCategoryId,
              _templateDropdownList,
              "id",
              "temp_name",
              "Select Template Name",
              (val) {
                setDialogState(() => dialogCategoryId = val);
                setState(() => _selectedCategoryId = val);
              },
              validator: (v) => (v == null || v.isEmpty) ? 'Select the Template Name' : null,
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
                ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            Navigator.pop(context);
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
                      borderRadius: BorderRadius.circular(
                        4,
                      ), // ← was 16, now sharp
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
                  text: "Default Templates",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showDefaultTemplateDialog,
                  icon: const Icon(Icons.settings_applications, size: 20),
                  label: const Text(
                    "CREATE DEFAULT TEMPLATE",
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
                child: _buildRightListContent(),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildRightListContent() {
    List<dynamic> filtered = _templateList.where((item) {
      final name = (item['temp_name'] ?? "").toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort(
      (a, b) => (int.tryParse(b['id'].toString()) ?? 0).compareTo(
        int.tryParse(a['id'].toString()) ?? 0,
      ),
    );

    final int perPage = int.tryParse(_entriesValue) ?? 10;
    final int startIdx = (_currentPage - 1) * perPage;
    final paginated = filtered.skip(startIdx).take(perPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTableControls(),
        const SizedBox(height: 15),
        Expanded(
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isLoading)
                        const LinearProgressIndicator(color: Colors.blue),
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
                                    columns: [
                                      _buildTableCol('Device Name'),
                                      _buildTableCol('Template Name'),
                                      _buildTableCol('Edit'),
                                    ],
                                    rows: paginated.map((item) {
                                      final devId =
                                          item['device_id']?.toString() ??
                                          item['id']?.toString();
                                      String? resolvedName;

                                      // 1. Try Lookup from master list first if ID is available
                                      if (devId != null) {
                                        final dev = _deviceDropdownList.firstWhere(
                                          (d) =>
                                              d['id'].toString() == devId ||
                                              d['device_id']?.toString() == devId,
                                          orElse: () => null,
                                        );
                                        if (dev != null) {
                                          resolvedName =
                                              dev['device_name'] ??
                                              dev['device_code'];
                                        }
                                      }

                                      // 2. Fallback to item's own fields if lookup failed or no ID
                                      resolvedName ??=
                                          item['device_name'] ??
                                          item['Device_name'] ??
                                          item['device_code'] ??
                                          "-";

                                      return DataRow(
                                        cells: [
                                          DataCell(Text(resolvedName ?? "-")),
                                          DataCell(Text(item['temp_name'] ?? "-")),
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
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        _buildTableFooter(filtered.length),
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
    return SearchableDropdown<String>(
      value: items.any((i) => i[idKey].toString() == value) ? value : null,
      hint: hint,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      items: items.map((item) {
        return SearchableDropdownItem<String>(
          value: item[idKey].toString(),
          label: item[nameKey] ?? "",
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

 Widget _buildTableControls() {
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
      ],
    );
  }

  DataColumn _buildTableCol(String label) => DataColumn(
    label: Text(
      label,
      style: TextStyle(
        color: Colors.blue.shade800,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );

  Widget _buildTableFooter(int total) {
    final int perPage = int.tryParse(_entriesValue) ?? 10;
    final int start = (_currentPage - 1) * perPage + 1;
    final int end = (start + perPage - 1 < total) ? start + perPage - 1 : total;

    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Showing ${total == 0 ? 0 : start} to $end of $total entries",
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          Row(
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
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(int total, int perPage) {
    List<Widget> widgets = [];
    int totalPages = (total / perPage).ceil();
    if (totalPages <= 1)
      return [_buildSquareBtn("1", false, null, isActive: true)];

    for (int i = 1; i <= totalPages; i++) {
      if (i == 1 ||
          i == totalPages ||
          (i >= _currentPage - 1 && i <= _currentPage + 1)) {
        widgets.add(
          _buildSquareBtn(
            "$i",
            true,
            () => setState(() => _currentPage = i),
            isActive: _currentPage == i,
          ),
        );
      } else if (i == _currentPage - 2 || i == _currentPage + 2) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text("...", style: TextStyle(fontSize: 11)),
          ),
        );
      }
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          horizontal: label.length > 2 ? 8 : 4,
          vertical: 4,
        ),
        constraints: const BoxConstraints(minWidth: 30),
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue
              : (enabled ? Colors.white : Colors.grey.shade50),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? Colors.white
                : (enabled ? Colors.black87 : Colors.black26),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
