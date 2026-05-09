import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ScheduleAllocateView extends StatefulWidget {
  final Map<String, dynamic>? editData;
  final bool isExtend;
  final VoidCallback? onBack;

  const ScheduleAllocateView({
    
    super.key,
    this.editData,
    this.isExtend = false,
    this.onBack,
  });

  @override
  State<ScheduleAllocateView> createState() => _ScheduleAllocateViewState();
}

class _ScheduleAllocateViewState extends State<ScheduleAllocateView>
    with SingleTickerProviderStateMixin {
  final String _baseUrl = "https://display.sriher.com";
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  List<dynamic> scheduleList = [];
  List<dynamic> templateList = [];
  List<dynamic> templateFiles = [];
  bool isLoadingSchedules = false;
  bool isLoadingTemplates = false;
  bool isLoadingFiles = false;

  String entriesValue = "10";
  int? selectedScheduleId;
  int? selectedTemplateId;
  bool selectAllSlot = false;
  Map<String, List<String>> selectedSlotsByDay = {};

  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _fromTimeController = TextEditingController();
  final TextEditingController _newScheduleController = TextEditingController();

  late AnimationController _durationPanelController;
  bool _wasSelectionComplete = false;

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
    _fetchTemplates();

    if (widget.editData != null) {
      selectedScheduleId =
          int.tryParse(widget.editData!['schedule_id']?.toString() ?? '') ??
          int.tryParse(widget.editData!['id']?.toString() ?? '');

      selectedTemplateId =
          int.tryParse(widget.editData!['temp_id']?.toString() ?? '') ??
          int.tryParse(widget.editData!['template_id']?.toString() ?? '');

      _fromDateController.text =
          widget.editData!['from_date']?.toString() ?? '';
      _toDateController.text = widget.editData!['to_date']?.toString() ?? '';
      String rawTime = widget.editData!['from_time']?.toString() ?? '';
      if (rawTime.length > 5) {
        _fromTimeController.text = rawTime.substring(0, 5);
      } else {
        _fromTimeController.text = rawTime;
      }

      if (selectedTemplateId != null) {
        _fetchTemplateFiles(selectedTemplateId!);
      }

      if (_fromTimeController.text.isNotEmpty &&
          _fromDateController.text.isNotEmpty &&
          _toDateController.text.isNotEmpty) {
        _prepopulateSlots();
      }
    }

    _durationPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _fromTimeController.dispose();
    _newScheduleController.dispose();
    _durationPanelController.dispose();
    super.dispose();
  }

  List<String> _generateTimeSlots() {
    List<String> slots = [];
    for (int i = 0; i < 24; i++) {
      String hour = i.toString().padLeft(2, '0');
      slots.add("$hour:00");
      slots.add("$hour:30");
    }
    return slots;
  }

  bool get isSelectionComplete =>
      selectedScheduleId != null && selectedTemplateId != null;

  bool get isAllFilled =>
      isSelectionComplete &&
      _fromDateController.text.isNotEmpty &&
      _toDateController.text.isNotEmpty &&
      _fromTimeController.text.isNotEmpty;

  List<String> get slotPairs {
    List<String> pairs = [];
    for (int i = 0; i < 24; i++) {
      String h1 = i.toString().padLeft(2, '0');
      String h2 = (i + 1).toString().padLeft(2, '0');
      if (i == 23) h2 = "00";
      pairs.add("$h1:00 - $h1:30");
      pairs.add("$h1:30 - $h2:00");
    }
    return pairs;
  }

  void _prepopulateSlots() {
    try {
      DateTime start = DateFormat('yyyy-MM-dd').parse(_fromDateController.text);
      DateTime end = DateFormat('yyyy-MM-dd').parse(_toDateController.text);
      String time = _fromTimeController.text;

      String? matchedSlot;
      for (var pair in slotPairs) {
        if (pair.startsWith(time)) {
          matchedSlot = pair;
          break;
        }
      }

      if (matchedSlot != null) {
        for (int i = 0; i <= end.difference(start).inDays; i++) {
          String key = DateFormat(
            'yyyy-MM-dd',
          ).format(start.add(Duration(days: i)));
          selectedSlotsByDay[key] = [matchedSlot];
        }
      }
    } catch (e) {
      debugPrint("Error pre-populating slots: $e");
    }
  }

  Future<void> _fetchSchedules() async {
    setState(() => isLoadingSchedules = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/scheduleMenu_listview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() => scheduleList = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => isLoadingSchedules = false);
    }
  }

  Future<void> _fetchTemplates() async {
    setState(() => isLoadingTemplates = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/new_templateview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() => templateList = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => isLoadingTemplates = false);
    }
  }

  Future<void> _fetchTemplateFiles(int templateId) async {
    setState(() => isLoadingFiles = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/selectTemplate_filesview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "template_id": templateId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() => templateFiles = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => isLoadingFiles = false);
    }
  }

  Future<void> _handleScheduleSubmit() async {
    if (selectedScheduleId == null || selectedTemplateId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/scheduleMenu_insertview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "schedule_id": selectedScheduleId,
          "temp_id": selectedTemplateId,
          "from_date": _fromDateController.text,
          "to_date": _toDateController.text,
          "from_time": _fromTimeController.text,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Assigned Successfully")),
          );
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _showSchedulePopup() {
    StylishDialog.show(
      context: context,
      title: "NEW SCHEDULE",
      maxWidth: 480,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Define a new department or purpose for scheduling.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 24),
            const Text(
              "Schedule Name",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.0,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newScheduleController,
              decoration: InputDecoration(
                hintText: "e.g., Cardiology OPD, General Ward",
                fillColor: const Color(0xFFF8FAFC),
              ),
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
                      // Logic to save
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Create Schedule",
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

  @override
  Widget build(BuildContext context) {
    if (isSelectionComplete && !_wasSelectionComplete) {
      _durationPanelController.forward(from: 0);
      _wasSelectionComplete = true;
    } else if (!isSelectionComplete) {
      _wasSelectionComplete = false;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;
          return Padding(
            padding: EdgeInsets.all(isNarrow ? 12.0 : 24.0),
            child: isNarrow
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildLeftColumn(),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),
                        if (isSelectionComplete) _buildRightColumn(),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildLeftColumn()),
                      const SizedBox(width: 32),
                      Expanded(
                        flex: 7,
                        child: isSelectionComplete
                            ? _buildRightColumn()
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_mosaic_rounded,
                                      size: 64,
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Select a template to view details",
                                      style: TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
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

  Widget _buildLeftColumn() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.editData != null) ...[
            Align(
              alignment: Alignment.topLeft,
              child: ElevatedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text(
                  "BACK",
                  style: TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _buildSectionTitle(widget.isExtend ? "Extend Schedule" : "Schedule"),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdownField(
                        hint: "Select Schedule Name",
                        value: selectedScheduleId,
                        items: scheduleList,
                        label: "Schedule Name",
                        onChanged: (val) =>
                            setState(() => selectedScheduleId = val),
                      ),
                    ),
                    const SizedBox(width: 15),
                    _buildCircularAddButton(),
                    const SizedBox(width: 25),
                    Expanded(
                      child: _buildDropdownField(
                        hint: "Select Template Name",
                        value: selectedTemplateId,
                        items: templateList,
                        label: "Template Name",
                        onChanged: (val) {
                          setState(() {
                            selectedTemplateId = val;
                            templateFiles = [];
                          });
                          if (val != null) _fetchTemplateFiles(val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _buildDateField("From Date", _fromDateController),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildTimeDropdown(
                        "From Time",
                        _fromTimeController,
                        enabled: _fromDateController.text.isNotEmpty,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildDateField("To Date", _toDateController),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Checkbox(
                            value: selectAllSlot,
                            activeColor: Colors.blue,
                            side: BorderSide(color: Colors.grey.shade400),
                            onChanged: (val) => setState(() {
                              selectAllSlot = val!;
                              if (selectAllSlot) {
                                try {
                                  DateTime start = DateFormat(
                                    'yyyy-MM-dd',
                                  ).parse(_fromDateController.text);
                                  DateTime end = DateFormat(
                                    'yyyy-MM-dd',
                                  ).parse(_toDateController.text);
                                  if (end.isBefore(start)) end = start;
                                  for (
                                    int i = 0;
                                    i <= end.difference(start).inDays;
                                    i++
                                  ) {
                                    String key = DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(start.add(Duration(days: i)));
                                    selectedSlotsByDay[key] = List.from(
                                      slotPairs,
                                    );
                                  }
                                } catch (e) {
                                  debugPrint(e.toString());
                                }
                              } else {
                                selectedSlotsByDay.clear();
                              }
                            }),
                          ),
                          const Text(
                            "Select All Slot",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.0,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (isAllFilled) ...[
            _buildSlotSelectionCard(),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 3,
                ),
                onPressed: _handleScheduleSubmit,
                child: const Text(
                  "SUBMIT",
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightColumn() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle("Template Duration"),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildListHeader(),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (isLoadingFiles) {
                        return const SizedBox(
                          height: 300,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (templateFiles.isEmpty) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: Text(
                              "No files found for this template",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16.0,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: DataTable(
                            columnSpacing: 25,
                            horizontalMargin: 20,
                            dataRowMinHeight: 70,
                            dataRowMaxHeight: 85,
                            headingRowHeight: 45,
                            headingRowColor: WidgetStateProperty.all(
                              Colors.blue.shade50,
                            ),
                            columns: [
                              _buildSortableColumn('Play order'),
                              _buildSortableColumn('File'),
                              _buildSortableColumn('File Name'),
                              _buildSortableColumn('Duration'),
                            ],
                            rows: templateFiles.map((file) {
                              final index = templateFiles.indexOf(file) + 1;
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      index.toString(),
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8.0,
                                      ),
                                      child: Container(
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: (file['file_name'] != null && file['file_name'].toString().trim().isNotEmpty)
                                            ? Image.network(
                                                "$_baseUrl/uploads/${file['file_name']}",
                                                height: 65,
                                                width: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
                                                      Icons.broken_image,
                                                      size: 30,
                                                      color: Colors.grey,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.image,
                                                size: 20,
                                                color: Colors.grey,
                                              ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      file['user_filename'] ??
                                          file['file_name'] ??
                                          '-',
                                      style: const TextStyle(
                                        fontSize: 12.0,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        "${file['duration'] ?? '30'}s",
                                        style: TextStyle(
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _buildPagination(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // UI Helpers
  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.w900,
        color: Colors.blue,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildDropdownField({
    required String hint,
    int? value,
    required List<dynamic> items,
    required String label,
    required Function(int?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.0,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: value,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 12.0),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          dropdownColor: Colors.white,
          isExpanded: true,
          onChanged: onChanged,
          items: items.map((e) {
            final id = int.tryParse(e['id'].toString());
            final name = e['schedule_name'] ?? e['temp_name'] ?? '';
            return DropdownMenuItem<int>(
              value: id,
              child: Text(
                name,
                style: const TextStyle(fontSize: 12.0, color: Colors.black87),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimeDropdown(
    String hint,
    TextEditingController controller, {
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "From Time",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.0,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value:
              (_generateTimeSlots().contains(controller.text) &&
                  controller.text.isNotEmpty)
              ? controller.text
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: enabled ? Colors.black38 : Colors.grey.shade400,
              fontSize: 13.0,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          dropdownColor: Colors.white,
          isExpanded: true,
          onChanged: enabled
              ? (v) {
                  if (v != null) setState(() => controller.text = v);
                }
              : null,
          items: _generateTimeSlots().map((String time) {
            return DropdownMenuItem<String>(
              value: time,
              child: Text(
                time,
                style: const TextStyle(fontSize: 13.0, color: Colors.black87),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCircularAddButton() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        iconSize: 18,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        icon: const Icon(Icons.add, color: Colors.blue, size: 16),
        onPressed: _showSchedulePopup,
      ),
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.0,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          style: const TextStyle(fontSize: 13.0, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'mm/dd/yy',
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 13.0),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            suffixIcon: const Icon(
              Icons.calendar_month,
              size: 20,
              color: Colors.blue,
            ),
          ),
          onTap: () async {
            DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
            );
            if (pickedDate != null) {
              setState(
                () => controller.text = DateFormat(
                  'yyyy-MM-dd',
                ).format(pickedDate),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 90,
                height: 38,
                child: DropdownButtonFormField<String>(
                  value: entriesValue,
                  items: ["10", "25", "50"]
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            style: const TextStyle(fontSize: 13.0),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => entriesValue = val!),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "entries",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          SizedBox(
            width: 180,
            height: 38,
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: "Search...",
                hintStyle: const TextStyle(fontSize: 12.0),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataColumn _buildSortableColumn(String label) {
    return DataColumn(
      label: Text(
        label,
        style: TextStyle(
          color: Colors.blue.shade900,
          fontWeight: FontWeight.bold,
          fontSize: 13.0,
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildPageBtn("Previous"),
          _buildPageBtn("1", isActive: true),
          _buildPageBtn("Next"),
        ],
      ),
    );
  }

  Widget _buildPageBtn(String label, {bool isActive = false}) {
    return Container(
      margin: EdgeInsets.zero,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? Colors.blue : Colors.white,
          foregroundColor: isActive ? Colors.white : Colors.blue,
          side: BorderSide(
            color: isActive ? Colors.blue : Colors.grey.shade300,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () {},
        child: Text(
          label,
          style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSlotSelectionCard() {
    DateTime start;
    DateTime end;
    try {
      start = DateFormat('yyyy-MM-dd').parse(_fromDateController.text);
      end = DateFormat('yyyy-MM-dd').parse(_toDateController.text);
      if (end.isBefore(start)) end = start;
    } catch (e) {
      return const SizedBox.shrink();
    }

    List<DateTime> days = [];
    for (int i = 0; i <= end.difference(start).inDays; i++) {
      days.add(start.add(Duration(days: i)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle("Slot Selection"),
        const SizedBox(height: 15),
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.separated(
              itemCount: days.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _buildDaySection(days[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaySection(DateTime day) {
    String dateStr = DateFormat('EEEE, MMM dd, yyyy').format(day);
    String key = DateFormat('yyyy-MM-dd').format(day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          color: Colors.blue.shade50.withOpacity(0.3),
          child: Row(
            children: [
              const Icon(Icons.event, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slotPairs.map((slot) {
              List<String> daySlots = selectedSlotsByDay[key] ?? [];
              bool isSelected = daySlots.contains(slot);

              return InkWell(
                onTap: () {
                  setState(() {
                    selectedSlotsByDay.putIfAbsent(key, () => []);
                    if (isSelected) {
                      selectedSlotsByDay[key]!.remove(slot);
                    } else {
                      selectedSlotsByDay[key]!.add(slot);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    slot,
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
