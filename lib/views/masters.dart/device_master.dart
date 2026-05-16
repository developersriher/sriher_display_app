import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

class DeviceMasterView extends StatefulWidget {
  const DeviceMasterView({super.key});

  @override
  State<DeviceMasterView> createState() => _DeviceMasterViewState();
}

class _DeviceMasterViewState extends State<DeviceMasterView> {
  // --- API CONFIGURATION ---
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  String get _baseUrl => getBaseUrl();

  // --- STATE MANAGEMENT ---
  List<dynamic> deviceList = [];
  bool isLoading = true;
  String entriesValue = "10";
  int? editingId;
  bool isSubmitting = false;
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // --- FORM CONTROLLERS ---
  final TextEditingController _deviceCodeController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _osController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _warrantyController = TextEditingController();
  final TextEditingController _serialNoController = TextEditingController();
  final TextEditingController _manufacturerController = TextEditingController();
  String? selectedDeviceType;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await fetchDevices();
  }

  @override
  void dispose() {
    _deviceCodeController.dispose();
    _deviceNameController.dispose();
    _modelController.dispose();
    _osController.dispose();
    _yearController.dispose();
    _warrantyController.dispose();
    _serialNoController.dispose();
    _manufacturerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // --- API INTEGRATION METHODS ---
  // ──────────────────────────────────────────────────────────────────────────

  // 1. FETCH DEVICE LIST
  Future<void> fetchDevices() async {
    setState(() => isLoading = true);
    final url = Uri.parse('$_baseUrl/deviceview');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          if (decoded is List) {
            deviceList = decoded;
          } else if (decoded is Map) {
            final data = decoded['data'];
            if (data is Map) {
              deviceList = (data['DeviceMasters'] is List)
                  ? data['DeviceMasters']
                  : [];
            } else if (data is List) {
              deviceList = data;
            } else {
              final otherPossibility =
                  decoded['device_list'] ?? decoded['device_data'];
              deviceList = (otherPossibility is List) ? otherPossibility : [];
            }
          } else {
            deviceList = [];
          }
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        _showSnackBar("Server Error: ${response.statusCode}");
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Network Error: $e");
      setState(() => isLoading = false);
    }
  }

  // 2. INSERT OR UPDATE DEVICE
  Future<void> handleFormSubmit() async {
    // Basic Validation
    if (_deviceCodeController.text.isEmpty ||
        _deviceNameController.text.isEmpty) {
      _showSnackBar("Please fill the Device ID and Name");
      return;
    }

    setState(() => isSubmitting = true);

    final bool isUpdate = editingId != null;
    final String endPoint = isUpdate
        ? '/deviceUpdateview'
        : '/insertDeviceview';
    final url = Uri.parse('$_baseUrl$endPoint');

    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "device_code": _deviceCodeController.text,
      "device_name": _deviceNameController.text,
      "device_model": _modelController.text,
      "device_os": _osController.text,
      "device_yr_model": _yearController.text,
      "device_warranty": _warrantyController.text,
      "device_s_no": _serialNoController.text,
      "Manufacture": _manufacturerController.text,
      "type_of_device": selectedDeviceType ?? "Android Smart TV",
    };

    if (isUpdate) {
      body["id"] = editingId; // Send as integer per user example
    }

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        final status = resData['status']?.toString().toLowerCase();
        if (!mounted) return;
        if (status == 'success' || status == '1' || resData['status'] == 1) {
          _showSnackBar(
            isUpdate
                ? "Device Updated Successfully"
                : "Device Created Successfully",
          );
          _clearForm();
          // DISMISS NOW HANDLED IN BUTTON PRESS
          await fetchDevices(); // Ensure we await the refresh
        } else {
          _showSnackBar(
            "Server Error: ${resData['Message'] ?? resData['message'] ?? 'Unknown Error'}",
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error sending data: $e");
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  // 3. EDIT DEVICE (FETCH SINGLE DATA)
  Future<void> loadDeviceToEdit(dynamic id) async {
    final url = Uri.parse('$_baseUrl/deviceEditview');
    try {
      final intId = int.tryParse(id.toString());
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": intId ?? id}),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        dynamic device;
        if (decoded is Map) {
          final rawData = decoded['device_data'] ?? decoded['data'];
          if (rawData is Map) {
            device = rawData;
          } else if (rawData is List && rawData.isNotEmpty) {
            device = rawData[0];
          } else {
            final keys = ['device_code', 'device_name', 'device_model'];
            if (keys.any((k) => decoded.containsKey(k))) {
              device = decoded;
            }
          }
        }

        if (!mounted) return;
        if (device != null && device is Map) {
          setState(() {
            editingId = intId ?? (id is int ? id : null);
            _deviceCodeController.text =
                device['device_code']?.toString() ?? "";
            _deviceNameController.text =
                device['device_name']?.toString() ?? "";
            _modelController.text = device['device_model']?.toString() ?? "";
            _osController.text = device['device_os']?.toString() ?? "";
            _yearController.text = device['device_yr_model']?.toString() ?? "";
            _warrantyController.text =
                device['device_warranty']?.toString() ?? "";
            _serialNoController.text = device['device_s_no']?.toString() ?? "";
            _manufacturerController.text =
                device['Manufacture']?.toString() ?? "";
            selectedDeviceType = device['type_of_device']?.toString();
          });
          _showDeviceDialog();
        } else {
          setState(() {
            editingId = intId ?? (id is int ? id : null);
          });
          _showDeviceDialog();
          _showSnackBar(
            "Could not load full device details — showing available data.",
          );
        }
      } else {
        if (!mounted) return;
        _showSnackBar("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error loading details for edit: $e");
      setState(() => editingId = int.tryParse(id.toString()));
      _showDeviceDialog();
    }
  }

  // 4. DELETE DEVICE
  Future<void> deleteDevice(dynamic id) async {
    // Using the specific local URL provided by the user for delete
    final url = Uri.parse('http://127.0.0.1:8001/deleteDeviceview');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "id": int.tryParse(id.toString()) ?? id,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        _showSnackBar("Device deleted successfully");
        fetchDevices();
      } else {
        if (!mounted) return;
        _showSnackBar("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Delete request failed: $e");
    }
  }

  void _clearForm() {
    setState(() {
      editingId = null;
      _deviceCodeController.clear();
      _deviceNameController.clear();
      _modelController.clear();
      _osController.clear();
      _yearController.clear();
      _warrantyController.clear();
      _serialNoController.clear();
      _manufacturerController.clear();
      selectedDeviceType = null;
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ──────────────────────────── POPUP DIALOG ────────────────────────────────

  void _showDeviceDialog() {
    final GlobalKey<FormState> dialogFormKey = GlobalKey<FormState>();
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Create New Device" : "Edit Device Details",
      subtitle: "Configure system hardware and specifications",
      icon: editingId == null
          ? Icons.add_to_queue_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.7,
      builder: (context, setDialogState) {
        return Form(
          key: dialogFormKey,
  autovalidateMode: AutovalidateMode.disabled, // ← no validation until submit
  child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _buildSectionHeader("DEVICE IDENTITY"),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Enter Device Name",
                    _deviceNameController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Device Name' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    "Enter Device ID/Code",
                    _deviceCodeController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Device ID/Code' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDropdownField(
              hint: "Select Device Type",
              value: selectedDeviceType,
              items: [
                "Android Smart TV",
                "LED Display",
                "Projector",
                "Linux Player",
              ],
              validator: (v) => (v == null || v.isEmpty) ? 'Please select the Device Type' : null,
              onChanged: (val) {
                setDialogState(() => selectedDeviceType = val);
                setState(() => selectedDeviceType = val);
              },
            ),
            const SizedBox(height: 32),
            _buildSectionHeader("HARDWARE SPECIFICATIONS"),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Enter Model Number",
                    _modelController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Model Number' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    "Enter OS System", 
                    _osController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the OS System' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Enter Year of Model",
                    _yearController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Year of Model' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    "Enter Serial Number",
                    _serialNoController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Serial Number' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSectionHeader("MANUFACTURING DETAILS"),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    "Enter Manufacturer Name",
                    _manufacturerController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Manufacturer Name' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    "Enter Warranty Status",
                    _warrantyController,
                    validator: (v) => (v == null || v.isEmpty) ? 'Please enter the Warranty Status' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _clearForm();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
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
  onPressed: isSubmitting
      ? null
      : () async {
          if (dialogFormKey.currentState!.validate()) {
            if (Navigator.canPop(context)) Navigator.pop(context);
            await handleFormSubmit();
          }
        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 32,
                    ),
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
            ),
          ],
        ),
      );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // --- UI BUILDING METHODS ---
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
                  text: "Device List",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ElevatedButton.icon(
  onPressed: () {
    _clearForm();
    _showDeviceDialog();
  },
  icon: const Icon(Icons.add_to_queue_rounded, size: 20),
  label: const Text(
    "CREATE DEVICE",
    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
  ),
),
              ],
            ),
            const SizedBox(height: 20),

            // List Card
            Expanded(child: _buildTableCard()),
          ],
        ),
      ),
      ),
    );
  }

  // Form Section Replaced by inline build in the expanded view for better theme control
  Widget _buildFormSection() {
    return const SizedBox.shrink(); // No longer used directly
  }

  Widget _buildTableCard() {
    return Container(
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildListHeaderControls(),
            const SizedBox(height: 16),

            // The Scrollable Table Container
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (isLoading)
                          const LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Colors.transparent,
                            color: Colors.white24,
                          ),

                        Expanded(
                          child: (deviceList.isNotEmpty && _filteredList.isEmpty)
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
                              : SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minWidth: constraints.maxWidth,
                                      ),
                                      child: DataTable(
                                        columnSpacing: 20,
                                        headingRowHeight: 45,
                                        headingRowColor: WidgetStateProperty.all(
                                          Colors.blue.shade50,
                                        ),
                                        border: TableBorder.all(
                                          color: Colors.white10,
                                        ),
                                        columns: _getColumns(),
                                        rows: _filteredList
                                            .map((device) => _getDataRow(device))
                                            .toList(),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),
            _buildTableFooter(),
          ],
        ),
      ),
    );
  }

  List<dynamic> get _filteredList {
    if (searchQuery.isEmpty) return deviceList;
    return deviceList.where((device) {
      final code = (device['device_code'] ?? '').toString().toLowerCase();
      final name = (device['device_name'] ?? '').toString().toLowerCase();
      final model = (device['device_model'] ?? '').toString().toLowerCase();
      final q = searchQuery.toLowerCase();
      return code.contains(q) || name.contains(q) || model.contains(q);
    }).toList();
  }

  List<DataColumn> _getColumns() {
    return [
          'Type of device',
          'Device ID',
          'Name',
          'Model',
          'OS',
          'Year of Model',
          'Warranty',
          'Serial No',
          'Edit',
          'Action',
        ]
        .map(
          (title) => DataColumn(
            label: Text(
              title,
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        )
        .toList();
  }

  DataRow _getDataRow(dynamic device) {
    // Ensure device is treated as a Map for safe access
    final Map<String, dynamic> data = (device is Map)
        ? Map<String, dynamic>.from(device)
        : {};

    // Robust key search to handle server-side camelCase or snake_case variations
    String val(List<String> keys) {
      for (var k in keys) {
        if (data.containsKey(k) && data[k] != null) return data[k].toString();
      }
      return "-";
    }

    return DataRow(
      cells: [
        DataCell(
          Text(
            val(['type_of_device', 'typeOfDevice', 'device_type', 'type']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_code', 'deviceCode', 'code']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_name', 'deviceName', 'name']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_model', 'deviceModel', 'model']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_os', 'deviceOs', 'os']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_yr_model', 'deviceYrModel', 'year', 'year_of_model']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_warranty', 'deviceWarranty', 'warranty']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_s_no', 'deviceSNo', 'serial_number', 'serial']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
            onPressed: () => loadDeviceToEdit(data['id'] ?? data['ID']),
          ),
        ),

        DataCell(
          Transform.scale(
            scale: 0.7,
            child: Switch(
              // Use active_status or status based on your API
              value:
                  data['active_status'] == 1 ||
                  data['status'] == 1 ||
                  data['status'] == "1",
              activeColor: Colors.green,
              onChanged: (v) {
                // Status toggle logic would go here
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- REUSABLE COMPONENTS ---
 Widget _buildTextField(String hint, TextEditingController controller, {
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        helperText: ' ', // Reserve space
      ),
    );
  }

  Widget _buildDropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      autovalidateMode: AutovalidateMode.onUserInteraction, // ← clears red once selected
      validator: validator,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        helperText: ' ', // Reserve space
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      hint: Text(hint, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      items: items.map((item) => DropdownMenuItem<String>(
        value: item,
        child: Text(item, style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: onChanged,
    );
  }

 

  Widget _buildListHeaderControls() {
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
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  entriesValue = v!;
                }),
              ),
            ),
            const SizedBox(width: 6),
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
            onChanged: (val) {
              setState(() {
                searchQuery = val;
              });
            },
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            decoration: InputDecoration(
              hintText: "Search Devices...",
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
  Widget _buildTableFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Showing 1 to ${deviceList.length} of ${deviceList.length} entries",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
        Row(
          children: [
            _buildPageBtn("Previous"),

            _buildPageBtn("1", active: true),

            _buildPageBtn("Next"),
          ],
        ),
      ],
    );
  }

  Widget _buildPageBtn(String label, {bool active = false}) {
    return Container(
      margin: EdgeInsets.zero,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? Colors.blue : Colors.grey.shade100,
          foregroundColor: active ? Colors.white : Colors.black87,
          side: active
              ? const BorderSide(color: Colors.blue)
              : BorderSide(color: Colors.grey.shade300),
          padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 15 : 12),
          minimumSize: const Size(40, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () {},
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _confirmDeletion(dynamic id) {
    StylishDialog.show(
      context: context,
      title: "CONFIRM DELETION",
      maxWidth: 400,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to remove this device from the records? This action cannot be undone.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
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
                    onPressed: () {
                      Navigator.pop(context);
                      deleteDevice(id);
                    },
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
                      "Delete Device",
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
  }
}
