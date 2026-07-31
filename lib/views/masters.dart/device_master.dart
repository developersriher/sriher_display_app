import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int currentPage = 0;
  final TextEditingController _searchController = TextEditingController();
  int? _sortColumnIndex;
  bool _sortAscending = true;

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
  Future<void> loadDeviceToEdit(dynamic id, Map<String, dynamic> localData) async {
    final intId = int.tryParse(id.toString());
    
    // 1. Immediately pre-populate with local table data to ensure fields are never empty
    setState(() {
      editingId = intId ?? (id is int ? id : null);
      _deviceCodeController.text = localData['device_code']?.toString() ?? "";
      _deviceNameController.text = localData['device_name']?.toString() ?? "";
      _modelController.text = localData['device_model']?.toString() ?? "";
      _osController.text = localData['device_os']?.toString() ?? "";
      _yearController.text = localData['device_yr_model']?.toString() ?? localData['year']?.toString() ?? "";
      _warrantyController.text = localData['device_warranty']?.toString() ?? localData['warranty']?.toString() ?? "";
      _serialNoController.text = localData['device_s_no']?.toString() ?? localData['serial_number']?.toString() ?? "";
      _manufacturerController.text = localData['Manufacture']?.toString() ?? localData['manufacture']?.toString() ?? "";
      selectedDeviceType = localData['type_of_device']?.toString() ?? localData['device_type']?.toString();
    });

    // Show dialog immediately with local data
    _showDeviceDialog();

    final url = Uri.parse('$_baseUrl/deviceEditview');
    try {
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
            _deviceCodeController.text = device['device_code']?.toString() ?? _deviceCodeController.text;
            _deviceNameController.text = device['device_name']?.toString() ?? _deviceNameController.text;
            _modelController.text = device['device_model']?.toString() ?? _modelController.text;
            _osController.text = device['device_os']?.toString() ?? _osController.text;
            _yearController.text = device['device_yr_model']?.toString() ?? _yearController.text;
            _warrantyController.text = device['device_warranty']?.toString() ?? _warrantyController.text;
            _serialNoController.text = device['device_s_no']?.toString() ?? _serialNoController.text;
            _manufacturerController.text = device['Manufacture']?.toString() ?? _manufacturerController.text;
            selectedDeviceType = device['type_of_device']?.toString() ?? selectedDeviceType;
          });
        }
      } else {
        if (!mounted) return;
        _showSnackBar("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint("API Error loading full edit data: $e");
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
      titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      subtitle: "Configure system hardware and specifications",
      icon: editingId == null
          ? Icons.add_to_queue_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.8,
      builder: (context, setDialogState) {
        final isDialogMobile = MediaQuery.of(context).size.width < 800;
        return Form(
          key: dialogFormKey,
          autovalidateMode:
              AutovalidateMode.disabled, // ← no validation until submit
          child: SingleChildScrollView(
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
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter the Device Name';
                        final clean = v.trim().toLowerCase();
                        final exists = deviceList.any((d) {
                          final name = (d['device_name'] ?? d['deviceName'] ?? '').toString().trim().toLowerCase();
                          final id = d['id'] ?? d['ID'];
                          if (editingId != null && id?.toString() == editingId?.toString()) return false;
                          return name == clean;
                        });
                        if (exists) return 'This device name already exists.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      "Enter Device ID/Code",
                      _deviceCodeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter the Device ID/Code';
                        final clean = v.trim().toLowerCase();
                        final exists = deviceList.any((d) {
                          final code = (d['device_code'] ?? d['deviceCode'] ?? d['code'] ?? '').toString().trim().toLowerCase();
                          final id = d['id'] ?? d['ID'];
                          if (editingId != null && id?.toString() == editingId?.toString()) return false;
                          return code == clean;
                        });
                        if (exists) return 'This device id already exists.';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDropdownField(
                hint: "Select Device Type",
                value: selectedDeviceType,
                items: () {
                  final List<String> defaultTypes = [
                    "Android Smart TV",
                    "LED Display",
                    "Projector",
                    "Linux Player",
                  ];
                  if (selectedDeviceType != null && selectedDeviceType!.isNotEmpty && !defaultTypes.contains(selectedDeviceType)) {
                    defaultTypes.add(selectedDeviceType!);
                  }
                  return defaultTypes;
                }(),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please select the Device Type'
                    : null,
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
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter the Model Number'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      "Enter OS System",
                      _osController,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter the OS System'
                          : null,
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
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter the Year of Model'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      "Enter Serial Number",
                      _serialNoController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please enter the Serial Number';
                        final clean = v.trim().toLowerCase();
                        final exists = deviceList.any((d) {
                          final sno = (d['device_s_no'] ?? d['deviceSNo'] ?? d['serial_number'] ?? d['serial'] ?? '').toString().trim().toLowerCase();
                          final id = d['id'] ?? d['ID'];
                          if (editingId != null && id?.toString() == editingId?.toString()) return false;
                          return sno == clean;
                        });
                        if (exists) return 'This serial number already exists.';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionHeader("MANUFACTURING DETAILS"),
              isDialogMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTextField(
                          "Enter Manufacturer Name",
                          _manufacturerController,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Please enter the Manufacturer Name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          "Enter Warranty Status",
                          _warrantyController,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                          ],
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Please enter the Warranty Status'
                              : null,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            "Enter Manufacturer Name",
                            _manufacturerController,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Please enter the Manufacturer Name'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            "Enter Warranty Status",
                            _warrantyController,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                            ],
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Please enter the Warranty Status'
                                : null,
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
                        vertical: 8,
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
                              if (Navigator.canPop(context))
                                Navigator.pop(context);
                              await handleFormSubmit();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTabletOrMobile = screenWidth < 950;
    
    final int currentItemCount = _filteredList.isEmpty ? 1 : _filteredList.length;
    final double tableHeight = (isTabletOrMobile ? 180.0 : 250.0) + (currentItemCount * 45.0);

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
                    text: "Device List",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
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
                            _buildCreateDeviceButton(isNarrow),
                          ],
                        );
                },
              ),
              const SizedBox(height: 20),
              isMobile
                  ? SizedBox(
                      height: tableHeight,
                      child: _buildTableCard(),
                    )
                  : Expanded(
                      child: _buildTableCard(),
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
        child: isMobile
            ? SingleChildScrollView(
                child: bodyContent,
              )
            : bodyContent,
      ),
    );
  }

  // Form Section Replaced by inline build in the expanded view for better theme control
  Widget _buildFormSection() {
    return const SizedBox.shrink(); // No longer used directly
  }

  Widget _buildSortHeader(String label, int colIndex) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_sortColumnIndex == colIndex) {
            _sortAscending = !_sortAscending;
          } else {
            _sortColumnIndex = colIndex;
            _sortAscending = true;
          }
          currentPage = 0;
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
              textAlign: TextAlign.left,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                heightFactor: 0.5,
                child: Icon(
                  Icons.arrow_drop_up,
                  size: 14,
                  color: _sortColumnIndex == colIndex && _sortAscending
                      ? Colors.blue
                      : const Color(0xFF94A3B8),
                ),
              ),
              Align(
                heightFactor: 0.5,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: _sortColumnIndex == colIndex && !_sortAscending
                      ? Colors.blue
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, {int colIndex = -1}) {
    if (colIndex < 0) {
      return Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return _buildSortHeader(label, colIndex);
  }

  Widget _buildTableCard() {
    return Column(
      children: [
        _buildListHeaderControls(),
        const SizedBox(height: 16),

            // The Scrollable Table Container
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 1200;

                  if (isNarrow) {
                    final Map<int, TableColumnWidth> colWidths = const {
                      0: FixedColumnWidth(125),
                      1: FixedColumnWidth(95),
                      2: FixedColumnWidth(110),
                      3: FixedColumnWidth(90),
                      4: FixedColumnWidth(70),
                      5: FixedColumnWidth(70),
                      6: FixedColumnWidth(95),
                      7: FixedColumnWidth(105),
                      8: FixedColumnWidth(110),
                      9: FixedColumnWidth(45),
                      10: FixedColumnWidth(50),
                    };

                    final double tableWidth = constraints.maxWidth > 965 ? constraints.maxWidth : 965;
                    final pagedList = _filteredList;

                    return SizedBox(
                      width: double.infinity,
                      height: constraints.maxHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: tableWidth,
                              height: constraints.maxHeight,
                              child: Column(
                                children: [
                                  // Fixed Header Row — never scrolls vertically
                                  Container(
                                    height: 45,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      border: Border(
                                        bottom: BorderSide(color: Colors.grey.shade300, width: 1.0),
                                      ),
                                    ),
                                    child: Table(
                                      columnWidths: colWidths,
                                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                      children: [
                                        TableRow(
                                          children: [
                                            _buildHeaderCell("Type of Device", colIndex: 0),
                                            _buildHeaderCell("Device ID", colIndex: 1),
                                            _buildHeaderCell("Name", colIndex: 2),
                                            _buildHeaderCell("Model", colIndex: 3),
                                            _buildHeaderCell("OS", colIndex: 4),
                                            _buildHeaderCell("Year", colIndex: 5),
                                            _buildHeaderCell("Warranty", colIndex: 6),
                                            _buildHeaderCell("Serial No", colIndex: 7),
                                            _buildHeaderCell("Manufacture", colIndex: 8),
                                            _buildHeaderCell("Edit"),
                                            _buildHeaderCell("Action"),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Vertically scrollable body rows only
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: Table(
                                        columnWidths: colWidths,
                                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                        children: pagedList.isEmpty
                                            ? [
                                                TableRow(
                                                  children: [
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(vertical: 36.0),
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(Icons.search_off_rounded, size: 36, color: Colors.blue.shade200),
                                                          const SizedBox(height: 8),
                                                          Text("No matching devices found", style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
                                                          const SizedBox(height: 4),
                                                          const Text("Try a different search term", style: TextStyle(color: Colors.grey, fontSize: 11)),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                    const SizedBox.shrink(),
                                                  ],
                                                )
                                              ]
                                            : pagedList.map((device) {
                                          final Map<String, dynamic> data = (device is Map) ? Map<String, dynamic>.from(device) : {};
                                          String val(List<String> keys) {
                                            for (var k in keys) {
                                              if (data.containsKey(k) && data[k] != null) return data[k].toString();
                                            }
                                            return "-";
                                          }

                                          return TableRow(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(color: Colors.grey.shade100),
                                              ),
                                            ),
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['type_of_device', 'typeOfDevice', 'device_type', 'type']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_code', 'deviceCode', 'code']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_name', 'deviceName', 'name']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_model', 'deviceModel', 'model']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_os', 'deviceOs', 'os']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_yr_model', 'deviceYrModel', 'year', 'year_of_model']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_warranty', 'deviceWarranty', 'warranty']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['device_s_no', 'deviceSNo', 'serial_number', 'serial']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                                                child: Text(
                                                  val(['Manufacture', 'manufacture']),
                                                  style: const TextStyle(fontSize: 11),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Center(
                                                child: IconButton(
                                                  icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                  onPressed: () {
                                                    Map<String, dynamic> localData = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data);
                                                    loadDeviceToEdit(data['id'] ?? data['ID'], localData);
                                                  },
                                                ),
                                              ),
                                              Center(
                                                child: Transform.scale(
                                                  scale: 0.65,
                                                  child: Switch(
                                                    value: data['active_status'] == 1 || data['status'] == 1 || data['status'] == "1",
                                                    activeColor: Colors.green,
                                                    onChanged: (v) {},
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

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
                          child: SingleChildScrollView(
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
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                              Colors.blue.shade50,
                                            ),
                                        border: TableBorder.all(
                                          color: Colors.white10,
                                        ),
                                        columns: _getColumns(),
                                        rows: _filteredList.isEmpty
                                            ? [
                                                DataRow(
                                                  cells: [
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    DataCell(
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(Icons.search_off_rounded, size: 36, color: Colors.blue.shade200),
                                                            const SizedBox(height: 6),
                                                            Text("No matching devices found", style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
                                                            const SizedBox(height: 4),
                                                            const Text("Try a different search term", style: TextStyle(color: Colors.grey, fontSize: 11)),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                    const DataCell(SizedBox.shrink()),
                                                  ],
                                                ),
                                              ]
                                            : _filteredList
                                            .map(
                                              (device) => _getDataRow(device),
                                            )
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
            SizedBox(height: MediaQuery.of(context).size.width < 950 ? 4 : 20),
            _buildTableFooter(),
      ],
    );
  }

  List<dynamic> get _allFilteredList {
    List<dynamic> list = [];
    if (searchQuery.isEmpty) {
      list = List.from(deviceList);
    } else {
      list = deviceList.where((device) {
        final code = (device['device_code'] ?? '').toString().toLowerCase();
        final name = (device['device_name'] ?? '').toString().toLowerCase();
        final model = (device['device_model'] ?? '').toString().toLowerCase();
        final q = searchQuery.toLowerCase();
        return code.contains(q) || name.contains(q) || model.contains(q);
      }).toList();
    }

    if (_sortColumnIndex != null) {
      list.sort((a, b) {
        final Map<String, dynamic> dataA = (a is Map) ? Map<String, dynamic>.from(a) : {};
        final Map<String, dynamic> dataB = (b is Map) ? Map<String, dynamic>.from(b) : {};

        String val(Map<String, dynamic> data, List<String> keys) {
          for (var k in keys) {
            if (data.containsKey(k) && data[k] != null) return data[k].toString();
          }
          return "";
        }

        String aVal = "";
        String bVal = "";

        switch (_sortColumnIndex) {
          case 0:
            aVal = val(dataA, ['type_of_device', 'typeOfDevice', 'device_type', 'type']);
            bVal = val(dataB, ['type_of_device', 'typeOfDevice', 'device_type', 'type']);
            break;
          case 1:
            aVal = val(dataA, ['device_code', 'deviceCode', 'code']);
            bVal = val(dataB, ['device_code', 'deviceCode', 'code']);
            break;
          case 2:
            aVal = val(dataA, ['device_name', 'deviceName', 'name']);
            bVal = val(dataB, ['device_name', 'deviceName', 'name']);
            break;
          case 3:
            aVal = val(dataA, ['device_model', 'deviceModel', 'model']);
            bVal = val(dataB, ['device_model', 'deviceModel', 'model']);
            break;
          case 4:
            aVal = val(dataA, ['device_os', 'deviceOs', 'os']);
            bVal = val(dataB, ['device_os', 'deviceOs', 'os']);
            break;
          case 5:
            aVal = val(dataA, ['device_yr_model', 'deviceYrModel', 'year', 'year_of_model']);
            bVal = val(dataB, ['device_yr_model', 'deviceYrModel', 'year', 'year_of_model']);
            break;
          case 6:
            aVal = val(dataA, ['device_warranty', 'deviceWarranty', 'warranty']);
            bVal = val(dataB, ['device_warranty', 'deviceWarranty', 'warranty']);
            break;
          case 7:
            aVal = val(dataA, ['device_s_no', 'deviceSNo', 'serial_number', 'serial']);
            bVal = val(dataB, ['device_s_no', 'deviceSNo', 'serial_number', 'serial']);
            break;
          case 8:
            aVal = val(dataA, ['Manufacture', 'manufacture']);
            bVal = val(dataB, ['Manufacture', 'manufacture']);
            break;
        }

        return _sortAscending
            ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
            : bVal.toLowerCase().compareTo(aVal.toLowerCase());
      });
    }

    return list;
  }

  List<dynamic> get _filteredList {
    final all = _allFilteredList;
    final limit = int.tryParse(entriesValue) ?? 10;
    final start = currentPage * limit;
    if (start >= all.length) return [];
    return all.sublist(start, (start + limit).clamp(0, all.length));
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
          'Manufacture',
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
          Text(
            val(['Manufacture', 'manufacture']),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
            onPressed: () {
               Map<String, dynamic> localData = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data);
               loadDeviceToEdit(data['id'] ?? data['ID'], localData);
            }
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
  Widget _buildTextField(
    String hint,
    TextEditingController controller, {
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    String label = hint;
    if (label.toLowerCase().startsWith('enter ')) {
      label = label.substring(6);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          validator: validator,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
            errorStyle: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            helperText: null,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    String label = hint;
    if (label.toLowerCase().startsWith('select ')) {
      label = label.substring(7);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
        ),
        SearchableDropdown<String>(
          value: value,
          hint: hint,
          onChanged: onChanged,
          items: items
              .map(
                (item) => SearchableDropdownItem<String>(
                  value: item,
                  label: item,
                ),
              )
              .toList(),
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          helperText: null,
        ),
      ],
    );
  }

  Widget _buildCreateDeviceButton(bool isNarrow) {
    return ElevatedButton.icon(
      onPressed: () {
        _clearForm();
        _showDeviceDialog();
      },
      icon: Icon(Icons.add_to_queue_rounded, size: isNarrow ? 14 : 20),
      style: isNarrow
          ? ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(80, 32),
            )
          : null,
      label: Text(
        "CREATE DEVICE",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isNarrow ? 10 : 12,
        ),
      ),
    );
  }

  Widget _buildListHeaderControls() {
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
                isExpanded: true,
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
              onChanged: (val) {
                setState(() {
                  searchQuery = val;
                  currentPage = 0;
                });
              },
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Search Devices...",
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
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
                    _buildCreateDeviceButton(isNarrow),
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
                  searchBox,
                ],
              );
      },
    );
  }

  Widget _buildTableFooter() {
    final limit = int.tryParse(entriesValue) ?? 10;
    final total = _allFilteredList.length;
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
            fontSize: 11,
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
                children: [
                  paginationText,
                  paginationControls,
                ],
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
