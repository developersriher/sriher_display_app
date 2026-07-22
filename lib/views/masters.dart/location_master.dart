import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

class LocationMasterView extends StatefulWidget {
  const LocationMasterView({super.key});

  @override
  State<LocationMasterView> createState() => _LocationMasterViewState();
}

class _LocationMasterViewState extends State<LocationMasterView> {
  // --- API CONFIGURATION ---
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";
  String get _baseUrl => getBaseUrl();

  // --- STATE MANAGEMENT ---
  List<dynamic> locationList = [];
  bool isLoading = true;
  String entriesValue = "10";
  int? editingId;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String searchQuery = "";
  int currentPage = 1;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // --- FORM CONTROLLERS ---
  final TextEditingController _buildingAreaController = TextEditingController();
  final TextEditingController _floorNameController = TextEditingController();
  final TextEditingController _subLocationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchLocations(showLoading: true);
  }

  @override
  void dispose() {
    _buildingAreaController.dispose();
    _floorNameController.dispose();
    _subLocationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 1. FETCH ALL LOCATIONS
  Future<void> fetchLocations({bool showLoading = true}) async {
    if (showLoading) setState(() => isLoading = true);
    final url = Uri.parse('$_baseUrl/locationview');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          locationList = decoded['data'] ?? decoded['location_list'] ?? [];
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        _showSnackBar("Failed to load list from server");
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Network Error: $e");
      setState(() => isLoading = false);
    }
  }

  // 2. INSERT NEW LOCATION
  Future<void> submitNewLocation() async {
    final url = Uri.parse('$_baseUrl/insertLocationview');
    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "location_name": _buildingAreaController.text,
      "floor": _floorNameController.text,
      "sublocation": _subLocationController.text,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        _showSnackBar("Location Submitted Successfully!");
        _clearForm();
        fetchLocations(showLoading: false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Submit Error: $e");
    }
  }

  // 3. EDIT: FETCH SINGLE DATA
  Future<void> fetchLocationDetailsForEdit(dynamic id) async {
    final url = Uri.parse('$_baseUrl/locationEditview');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "id": int.tryParse(id.toString())}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        if (!mounted) return;
        setState(() {
          editingId = int.parse(id.toString());
          _buildingAreaController.text = data['location_name'] ?? "";
          _floorNameController.text = data['floor'] ?? "";
          _subLocationController.text = data['sublocation'] ?? "";
        });
        _showLocationDialog();
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error loading details for edit");
    }
  }

  // 4. UPDATE EXISTING LOCATION
  Future<void> updateLocation() async {
    final url = Uri.parse('$_baseUrl/locationUpdateview');
    final Map<String, dynamic> body = {
      "api_key": _apiKey,
      "id": editingId,
      "location_name": _buildingAreaController.text,
      "floor": _floorNameController.text,
      "sublocation": _subLocationController.text,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        _showSnackBar("Location Updated Successfully!");
        _clearForm();
        fetchLocations(showLoading: false);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Update Error: $e");
    }
  }

  // 5. UPDATE STATUS
  Future<void> toggleLocationStatus(dynamic id, dynamic currentStatus) async {
    final url = Uri.parse('$_baseUrl/locationStatusUpdateview');
    final int newStatus = (currentStatus == 1 || currentStatus == "1") ? 0 : 1;

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "location_id": int.tryParse(id.toString()),
          "status": newStatus,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        fetchLocations();
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint("Status Toggle Error: $e");
    }
  }

  void _clearForm() {
    setState(() {
      editingId = null;
      _buildingAreaController.clear();
      _floorNameController.clear();
      _subLocationController.clear();
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

void _showLocationDialog() {
    StylishDialog.show(
      context: context,
      title: editingId == null ? "Add Location Master" : "Edit Location",
      subtitle: "Configure building areas and floor levels",
      icon: editingId == null ? Icons.add_location_alt_rounded : Icons.edit_location_alt_rounded,
      width: MediaQuery.of(context).size.width * 0.4,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSmallTextField(
              'Enter Building/Area Name',
              _buildingAreaController,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))],
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Please enter the Building/Area Name'
                  : null,
            ),
            const SizedBox(height: 20),
            _buildSmallTextField(
              'Enter Floor Name',
              _floorNameController,
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Please enter the Floor Name'
                  : null,
            ),
            const SizedBox(height: 20),
            _buildSmallTextField(
              'Enter Sub Location Name',
              _subLocationController, 
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter the Sub Location Name';
                final clean = v.trim().toLowerCase();
                final exists = locationList.any((loc) {
                  final sub = (loc['sublocation'] ?? loc['sub_location'] ?? '').toString().trim().toLowerCase();
                  final id = loc['id'] ?? loc['ID'];
                  if (editingId != null && id?.toString() == editingId?.toString()) return false;
                  return sub == clean;
                });
                if (exists) return 'This sub location already exists.';
                return null;
              },
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
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
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
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context); // ← close first before submit
              if (editingId == null) {
                await submitNewLocation();
              } else {
                await updateLocation();
              }
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
          child: Text(
            editingId == null ? "Submit" : "Update",
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        )
      ],
    );
  }

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
                  text: "Location List",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _clearForm();
                    _showLocationDialog();
                  },
                  icon: const Icon(Icons.add_location_alt_rounded, size: 20),
                  label: const Text(
                    "ADD LOCATION MASTER",
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
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildListHeader(),
                      const SizedBox(height: 16),
                      _buildDataTableContainer(),
                      const SizedBox(height: 16),
                      _buildTableFooter(_filteredListForFooter()),
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

  List<dynamic> _filteredListForFooter() {
    return locationList.where((loc) {
      final name = (loc['location_name'] ?? "").toString().toLowerCase();
      final floor = (loc['floor'] ?? "").toString().toLowerCase();
      final sub = (loc['sublocation'] ?? "").toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      return name.contains(query) || floor.contains(query) || sub.contains(query);
    }).toList();
  }

  Widget _buildDataTableContainer() {
    final filteredList = locationList.where((loc) {
      final name = (loc['location_name'] ?? "").toString().toLowerCase();
      final floor = (loc['floor'] ?? "").toString().toLowerCase();
      final sub = (loc['sublocation'] ?? "").toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      return name.contains(query) || floor.contains(query) || sub.contains(query);
    }).toList();

    if (_sortColumnIndex != null) {
      filteredList.sort((a, b) {
        String aVal = "";
        String bVal = "";
        switch (_sortColumnIndex) {
          case 0:
            aVal = (a['location_name'] ?? "").toString();
            bVal = (b['location_name'] ?? "").toString();
            break;
          case 1:
            aVal = (a['floor'] ?? "").toString();
            bVal = (b['floor'] ?? "").toString();
            break;
          case 2:
            aVal = (a['sublocation'] ?? "").toString();
            bVal = (b['sublocation'] ?? "").toString();
            break;
        }
        return _sortAscending
            ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
            : bVal.toLowerCase().compareTo(aVal.toLowerCase());
      });
    } else {
      // Default sort by id to maintain consistent order
      filteredList.sort((a, b) => (int.tryParse(b['id']?.toString() ?? '0') ?? 0).compareTo(int.tryParse(a['id']?.toString() ?? '0') ?? 0));
    }

    final int perPage = int.tryParse(entriesValue) ?? 10;
    final int startIdx = (currentPage - 1) * perPage;
    final int endIdx = (startIdx + perPage > filteredList.length) ? filteredList.length : (startIdx + perPage);
    final pagedList = filteredList.sublist(startIdx, endIdx);

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: (locationList.isNotEmpty && filteredList.isEmpty)
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
                          "No matching locations found",
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
                    children: [
                      if (isLoading)
                        const LinearProgressIndicator(color: Colors.blue),
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
                                border: TableBorder.all(color: Colors.grey.shade200),
                                headingRowHeight: 45,
                                headingRowColor: WidgetStateProperty.all(
                                  Colors.blue.shade50,
                                ),
                                columns: [
                                  _buildSortableColumn('Building/Area Name', columnIndex: 0, sortable: true),
                                  _buildSortableColumn('Floor', columnIndex: 1, sortable: true),
                                  _buildSortableColumn('Sub Location', columnIndex: 2, sortable: true),
                                  _buildSortableColumn('Edit'),
                                  _buildSortableColumn('Action'),
                                ],
                                rows: pagedList.map((loc) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8.0),
                                          child: Text(
                                            loc['location_name']?.toString() ?? "-",
                                            style: const TextStyle(color: Colors.black87),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(
                                        loc['floor']?.toString() ?? "-",
                                        style: const TextStyle(color: Colors.black87),
                                      )),
                                      DataCell(
                                        Text(
                                          loc['sublocation']?.toString() ?? "-",
                                          style: const TextStyle(color: Colors.black87),
                                        ),
                                      ),
                                      DataCell(
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              editingId = int.tryParse(loc['id'].toString());
                                              _buildingAreaController.text = loc['location_name']?.toString() ?? "";
                                              _floorNameController.text = loc['floor']?.toString() ?? "";
                                              _subLocationController.text = loc['sublocation']?.toString() ?? "";
                                            });
                                            _showLocationDialog();
                                          },
                                        ),
                                      ),
                                      DataCell(
                                        Transform.scale(
                                          scale: 0.7,
                                          child: Switch(
                                            value:
                                                loc['status'] == 1 ||
                                                loc['status'] == "1",
                                            activeColor: Colors.blue,
                                            onChanged: (val) => toggleLocationStatus(
                                              loc['id'],
                                              loc['status'],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
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
    );
  }

Widget _buildSmallTextField(String hint, TextEditingController controller, {String? Function(String?)? validator, List<TextInputFormatter>? inputFormatters}) {
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
          validator: validator,
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
                color: Color(0xFFCBD5E1), // ← border stays visible on error
                width: 1.2,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF334155), // ← dark when focused with error
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
              horizontal: 10,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final showEntries = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Show",
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
            const SizedBox(width: 6),
            const Text(
              "entries",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ],
        );

        final searchBox = SizedBox(
          width: isNarrow ? 200 : 250,
          height: 40,
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => searchQuery = val),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            decoration: InputDecoration(
              hintText: "Search Locations...",
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
        );

        return isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  showEntries,
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: searchBox,
                  ),
                ],
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

  Widget _buildTableFooter(List<dynamic> filtered) {
    final total = filtered.length;
    final perPage = int.tryParse(entriesValue) ?? 10;
    final start = (currentPage - 1) * perPage + 1;
    final end = (start + perPage - 1 < total) ? start + perPage - 1 : total;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final showingText = Text(
          "Showing ${total == 0 ? 0 : start} to $end of $total entries",
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        );

        final pagination = _buildPagination(total, perPage);

        return isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  showingText,
                  const SizedBox(height: 10),
                  pagination,
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  showingText,
                  pagination,
                ],
              );
      },
    );
  }

  DataColumn _buildSortableColumn(String label, {int? columnIndex, bool sortable = false}) {
    return DataColumn(
      label: Expanded(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (sortable && columnIndex != null) ...[
              const SizedBox(width: 4),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sortColumnIndex = columnIndex;
                        _sortAscending = true;
                      });
                    },
                    child: Align(
                      heightFactor: 0.4,
                      child: Icon(
                        Icons.arrow_drop_up,
                        size: 18,
                        color: _sortColumnIndex == columnIndex && _sortAscending
                            ? Colors.blue
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sortColumnIndex = columnIndex;
                        _sortAscending = false;
                      });
                    },
                    child: Align(
                      heightFactor: 0.4,
                      child: Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: _sortColumnIndex == columnIndex && !_sortAscending
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
  }

  Widget _buildPagination(int total, int perPage) {
    final totalPages = (total / perPage).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Row(
      children: [
        _pageBtn(
          "Previous",
          enabled: currentPage > 1,
          onTap: () => setState(() => currentPage--),
        ),
        ..._buildPageNumberButtons(totalPages),
        _pageBtn(
          "Next",
          enabled: currentPage < totalPages,
          onTap: () => setState(() => currentPage++),
        ),
      ],
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
        _pageBtn(
          "$pageNum",
          enabled: true,
          onTap: () => setState(() => currentPage = pageNum),
          isActive: currentPage == pageNum,
        ),
      );
    }
    return widgets;
  }

  Widget _pageBtn(
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
