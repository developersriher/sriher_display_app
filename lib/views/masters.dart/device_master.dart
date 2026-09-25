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
  Future<void> loadDeviceToEdit(
    dynamic id,
    Map<String, dynamic> localData,
  ) async {
    final intId = int.tryParse(id.toString());

    // 1. Immediately pre-populate with local table data to ensure fields are never empty
    setState(() {
      editingId = intId ?? (id is int ? id : null);
      _deviceCodeController.text = localData['device_code']?.toString() ?? "";
      _deviceNameController.text = localData['device_name']?.toString() ?? "";
      _modelController.text = localData['device_model']?.toString() ?? "";
      _osController.text = localData['device_os']?.toString() ?? "";
      _yearController.text =
          localData['device_yr_model']?.toString() ??
          localData['year']?.toString() ??
          "";
      _warrantyController.text =
          localData['device_warranty']?.toString() ??
          localData['warranty']?.toString() ??
          "";
      _serialNoController.text =
          localData['device_s_no']?.toString() ??
          localData['serial_number']?.toString() ??
          "";
      _manufacturerController.text =
          localData['Manufacture']?.toString() ??
          localData['manufacture']?.toString() ??
          "";
      selectedDeviceType =
          localData['type_of_device']?.toString() ??
          localData['device_type']?.toString();
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
            _deviceCodeController.text =
                device['device_code']?.toString() ?? _deviceCodeController.text;
            _deviceNameController.text =
                device['device_name']?.toString() ?? _deviceNameController.text;
            _modelController.text =
                device['device_model']?.toString() ?? _modelController.text;
            _osController.text =
                device['device_os']?.toString() ?? _osController.text;
            _yearController.text =
                device['device_yr_model']?.toString() ?? _yearController.text;
            _warrantyController.text =
                device['device_warranty']?.toString() ??
                _warrantyController.text;
            _serialNoController.text =
                device['device_s_no']?.toString() ?? _serialNoController.text;
            _manufacturerController.text =
                device['Manufacture']?.toString() ??
                _manufacturerController.text;
            selectedDeviceType =
                device['type_of_device']?.toString() ?? selectedDeviceType;
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
      titleStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
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
                          if (v == null || v.trim().isEmpty)
                            return 'Please enter the Device Name';
                          final clean = v.trim().toLowerCase();
                          final exists = deviceList.any((d) {
                            final name =
                                (d['device_name'] ?? d['deviceName'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final id = d['id'] ?? d['ID'];
                            if (editingId != null &&
                                id?.toString() == editingId?.toString())
                              return false;
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Please enter the Device ID/Code';
                          final clean = v.trim().toLowerCase();
                          final exists = deviceList.any((d) {
                            final code =
                                (d['device_code'] ??
                                        d['deviceCode'] ??
                                        d['code'] ??
                                        '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final id = d['id'] ?? d['ID'];
                            if (editingId != null &&
                                id?.toString() == editingId?.toString())
                              return false;
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
                    if (selectedDeviceType != null &&
                        selectedDeviceType!.isNotEmpty &&
                        !defaultTypes.contains(selectedDeviceType)) {
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Please enter the Serial Number';
                          final clean = v.trim().toLowerCase();
                          final exists = deviceList.any((d) {
                            final sno =
                                (d['device_s_no'] ??
                                        d['deviceSNo'] ??
                                        d['serial_number'] ??
                                        d['serial'] ??
                                        '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final id = d['id'] ?? d['ID'];
                            if (editingId != null &&
                                id?.toString() == editingId?.toString())
                              return false;
                            return sno == clean;
                          });
                          if (exists)
                            return 'This serial number already exists.';
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
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z ]'),
                              ),
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
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z ]'),
                                ),
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
          fontSize: 12,
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
                            _buildCreateDeviceButton(isNarrow),
                          ],
                        );
                },
              ),
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: bodyContent,
        ),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color.fromRGBO(33, 150, 243, 1),
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
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
      return Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 12.0),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color.fromRGBO(33, 150, 243, 1),
              fontWeight: FontWeight.bold,
              fontSize: 16.0,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 12.0),
        child: _buildSortHeader(label, colIndex),
      ),
    );
  }

  Widget _buildTableCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildListHeaderControls(),
        const SizedBox(height: 16),
        _buildDataTableContent(),
        const SizedBox(height: 16),
        _buildTableFooter(),
      ],
    );
  }

  Widget _buildDataTableContent() {
    if (isLoading) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              "Loading devices...",
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final pagedList = _filteredList;

    return LayoutBuilder(
      builder: (context, constraints) {
        const double minWidth = 1400;
        final double tableWidth = constraints.maxWidth > minWidth
            ? constraints.maxWidth
            : minWidth;

        final Map<int, TableColumnWidth> colWidths = const {
          0: FlexColumnWidth(4.2), // TYPE OF DEVICE
          1: FlexColumnWidth(2.5), // DEVICE ID
          2: FlexColumnWidth(3.0), // NAME
          3: FlexColumnWidth(2.5), // MODEL
          4: FlexColumnWidth(1.8), // OS
          5: FlexColumnWidth(3.5), // YEAR OF MODEL
          6: FlexColumnWidth(2.5), // WARRANTY
          7: FlexColumnWidth(2.5), // SERIAL NO
          8: FlexColumnWidth(3.5), // MANUFACTURE
          9: FlexColumnWidth(1.4), // EDIT
          10: FlexColumnWidth(1.6), // ACTION
        };

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200, width: 1.0),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Table Header Row
                  Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.shade200,
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: Table(
                      columnWidths: colWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            _buildHeaderCell("TYPE OF DEVICE", colIndex: 0),
                            _buildHeaderCell("DEVICE ID", colIndex: 1),
                            _buildHeaderCell("NAME", colIndex: 2),
                            _buildHeaderCell("MODEL", colIndex: 3),
                            _buildHeaderCell("OS", colIndex: 4),
                            _buildHeaderCell("YEAR OF MODEL", colIndex: 5),
                            _buildHeaderCell("WARRANTY", colIndex: 6),
                            _buildHeaderCell("SERIAL NO", colIndex: 7),
                            _buildHeaderCell("MANUFACTURE", colIndex: 8),
                            _buildHeaderCell("EDIT"),
                            _buildHeaderCell("ACTION"),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Data Rows or Empty State
                  if (pagedList.isEmpty)
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
                            "No matching devices found",
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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
                    Table(
                      columnWidths: colWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: pagedList.map((device) {
                        final Map<String, dynamic> data = (device is Map)
                            ? Map<String, dynamic>.from(device)
                            : {};
                        String val(List<String> keys) {
                          for (var k in keys) {
                            if (data.containsKey(k) && data[k] != null) {
                              return data[k].toString();
                            }
                          }
                          return "-";
                        }

                        return TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1.0,
                              ),
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val([
                                    'type_of_device',
                                    'typeOfDevice',
                                    'device_type',
                                    'type',
                                  ]),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val(['device_code', 'deviceCode', 'code']),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val(['device_name', 'deviceName', 'name']),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val(['device_model', 'deviceModel', 'model']),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val(['device_os', 'deviceOs', 'os']),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val([
                                    'device_yr_model',
                                    'deviceYrModel',
                                    'year',
                                    'year_of_model',
                                  ]),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val([
                                    'device_warranty',
                                    'deviceWarranty',
                                    'warranty',
                                  ]),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val([
                                    'device_s_no',
                                    'deviceSNo',
                                    'serial_number',
                                    'serial',
                                  ]),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                  vertical: 10.0,
                                ),
                                child: Text(
                                  val(['Manufacture', 'manufacture']),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  Map<String, dynamic> localData =
                                      Map<String, dynamic>.from(data);
                                  loadDeviceToEdit(
                                    data['id'] ?? data['ID'],
                                    localData,
                                  );
                                },
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: Transform.scale(
                                scale: 0.7,
                                child: Switch(
                                  value:
                                      data['active_status'] == 1 ||
                                      data['status'] == 1 ||
                                      data['status'] == "1",
                                  activeColor: Colors.green,
                                  onChanged: (v) {},
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
        final Map<String, dynamic> dataA = (a is Map)
            ? Map<String, dynamic>.from(a)
            : {};
        final Map<String, dynamic> dataB = (b is Map)
            ? Map<String, dynamic>.from(b)
            : {};

        String val(Map<String, dynamic> data, List<String> keys) {
          for (var k in keys) {
            if (data.containsKey(k) && data[k] != null)
              return data[k].toString();
          }
          return "";
        }

        String aVal = "";
        String bVal = "";

        switch (_sortColumnIndex) {
          case 0:
            aVal = val(dataA, [
              'type_of_device',
              'typeOfDevice',
              'device_type',
              'type',
            ]);
            bVal = val(dataB, [
              'type_of_device',
              'typeOfDevice',
              'device_type',
              'type',
            ]);
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
            aVal = val(dataA, [
              'device_yr_model',
              'deviceYrModel',
              'year',
              'year_of_model',
            ]);
            bVal = val(dataB, [
              'device_yr_model',
              'deviceYrModel',
              'year',
              'year_of_model',
            ]);
            break;
          case 6:
            aVal = val(dataA, [
              'device_warranty',
              'deviceWarranty',
              'warranty',
            ]);
            bVal = val(dataB, [
              'device_warranty',
              'deviceWarranty',
              'warranty',
            ]);
            break;
          case 7:
            aVal = val(dataA, [
              'device_s_no',
              'deviceSNo',
              'serial_number',
              'serial',
            ]);
            bVal = val(dataB, [
              'device_s_no',
              'deviceSNo',
              'serial_number',
              'serial',
            ]);
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
          'TYPE OF DEVICE',
          'DEVICE ID',
          'NAME',
          'MODEL',
          'OS',
          'YEAR OF MODEL',
          'WARRANTY',
          'SERIAL NO',
          'MANUFACTURE',
          'EDIT',
          'ACTION',
        ]
        .map(
          (title) => DataColumn(
            label: Text(
              title,
              style:TextStyle(
                color: Color.fromRGBO(33, 150, 243, 1),
                fontWeight: FontWeight.bold,
                fontSize: 10,
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
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_code', 'deviceCode', 'code']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_name', 'deviceName', 'name']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_model', 'deviceModel', 'model']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_os', 'deviceOs', 'os']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_yr_model', 'deviceYrModel', 'year', 'year_of_model']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_warranty', 'deviceWarranty', 'warranty']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['device_s_no', 'deviceSNo', 'serial_number', 'serial']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          Text(
            val(['Manufacture', 'manufacture']),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
            onPressed: () {
              Map<String, dynamic> localData =
                  Map<String, dynamic>.from(data);
              loadDeviceToEdit(data['id'] ?? data['ID'], localData);
            },
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
                (item) =>
                    SearchableDropdownItem<String>(value: item, label: item),
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
                children: [showEntries, searchBox],
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
