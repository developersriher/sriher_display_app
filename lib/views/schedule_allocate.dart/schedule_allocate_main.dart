import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';
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
  String get _baseUrl => getBaseUrl();
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
  final TextEditingController _toTimeController = TextEditingController();
  final TextEditingController _newScheduleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  /// Filtered template files based on search query
  List<dynamic> get _filteredTemplateFiles {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return templateFiles;
    return templateFiles.where((file) {
      final fileName = (file['user_filename'] ?? file['file_name'] ?? '')
          .toString()
          .toLowerCase();
      return fileName.contains(query);
    }).toList();
  }

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

      String rawToTime = widget.editData!['to_time']?.toString() ?? '';
      if (rawToTime.length > 5) {
        _toTimeController.text = rawToTime.substring(0, 5);
      } else {
        _toTimeController.text = rawToTime;
      }

      if (selectedTemplateId != null) {
        _fetchTemplateFiles(selectedTemplateId!);
      }

      if (_fromTimeController.text.isNotEmpty &&
          _toTimeController.text.isNotEmpty &&
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
    _toTimeController.dispose();
    _newScheduleController.dispose();
    _searchController.dispose();
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
      _fromTimeController.text.isNotEmpty &&
      _toTimeController.text.isNotEmpty;

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
      String fromTime = _fromTimeController.text;
      String toTime = _toTimeController.text;

      int timeToMinutes(String timeStr) {
        final parts = timeStr.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        return h * 60 + m;
      }

      int startMin = timeToMinutes(fromTime);
      int endMin = timeToMinutes(toTime);

      List<String> matchedSlots = [];
      for (var pair in slotPairs) {
        String slotStartStr = pair.split(' - ')[0];
        int slotStartMin = timeToMinutes(slotStartStr);
        if (endMin > startMin) {
          if (slotStartMin >= startMin && slotStartMin < endMin) {
            matchedSlots.add(pair);
          }
        } else {
          // Crosses midnight, e.g. 22:00 to 02:00
          if (slotStartMin >= startMin || slotStartMin < endMin) {
            matchedSlots.add(pair);
          }
        }
      }

      if (matchedSlots.isNotEmpty) {
        for (int i = 0; i <= end.difference(start).inDays; i++) {
          String key = DateFormat(
            'yyyy-MM-dd',
          ).format(start.add(Duration(days: i)));
          selectedSlotsByDay[key] = List.from(matchedSlots);
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
          "to_time": _toTimeController.text,
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

  void _addNewSchedule(String name) {
    if (name.isEmpty) return;
    setState(() {
      final newId = DateTime.now().millisecondsSinceEpoch % 10000;
      scheduleList = List.from(scheduleList)
        ..add({"id": newId.toString(), "schedule_name": name});
      selectedScheduleId = newId;
      _newScheduleController.clear();
    });
  }

  void _showSchedulePopup() {
    final GlobalKey<FormState> _popupFormKey = GlobalKey<FormState>();
    StylishDialog.show(
      context: context,
      title: "New Schedule",
      subtitle: "Define a new department or purpose for scheduling.",
      maxWidth: 480,
      builder: (context, setPopupState) {
        return Form(
          key: _popupFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Schedule Name",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newScheduleController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                textInputAction: TextInputAction.done,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Enter the schedule";
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (_popupFormKey.currentState!.validate()) {
                    final name = _newScheduleController.text.trim();
                    Navigator.pop(context);
                    _addNewSchedule(name);
                  }
                },
                decoration: InputDecoration(
                  hintText: "Enter the schedule name",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: Color(0xFF0F172A),
                      width: 1.5,
                    ),
                  ),
                  errorBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Colors.red, width: 1.0),
                  ),
                  focusedErrorBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Colors.red, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
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
                    // 👇 CHANGED FROM 2 TO 1 TO TAKE HALF THE HORIZONTAL SPACE
                    flex: 1,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_popupFormKey.currentState!.validate()) {
                          final name = _newScheduleController.text.trim();
                          Navigator.pop(context);
                          _addNewSchedule(name);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          // 👇 REDUCED FROM 32 TO 20 TO MAKE THE WIDTH NARROWER
                          horizontal: 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Create Schedule",
                        style: TextStyle(fontWeight: FontWeight.bold),
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
      body: SelectionArea(
        child: LayoutBuilder(
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
                        Expanded(flex: 7, child: _buildLeftColumn()),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 5,
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
                      child: _buildDropdown(
                        label: "Schedule Name",
                        hint: "Select Schedule Name",
                        value: selectedScheduleId,
                        items: scheduleList,
                        showAdd: true,
                        onChanged: (val) {
                          setState(() {
                            selectedScheduleId = val;
                            _fromDateController.clear();
                            _fromTimeController.clear();
                            _toDateController.clear();
                            _toTimeController.clear();
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 25),
                    Expanded(
                      child: _buildDropdown(
                        label: "Template Name",
                        hint: "Select Template Name",
                        value: selectedTemplateId,
                        items: templateList,
                        onChanged: (val) {
                          setState(() {
                            selectedTemplateId = val;
                            templateFiles = [];
                            _fromDateController.clear();
                            _fromTimeController.clear();
                            _toDateController.clear();
                            _toTimeController.clear();
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
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
                      flex: 2,
                      child: _buildDateField(
                        "From Date",
                        _fromDateController,
                        enabled:
                            selectedScheduleId != null &&
                            selectedTemplateId != null,
                        onChanged: () {
                          setState(() {
                            _fromTimeController.clear();
                            _toDateController.clear();
                            _toTimeController.clear();
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildTimeDropdown(
                        "From Time",
                        "From Time",
                        _fromTimeController,
                        enabled:
                            selectedScheduleId != null &&
                            selectedTemplateId != null &&
                            _fromDateController.text.isNotEmpty,
                        onChanged: () {
                          setState(() {
                            _toDateController.clear();
                            _toTimeController.clear();
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildDateField(
                        "To Date",
                        _toDateController,
                        enabled:
                            selectedScheduleId != null &&
                            selectedTemplateId != null &&
                            _fromDateController.text.isNotEmpty &&
                            _fromTimeController.text.isNotEmpty,
                        onChanged: () {
                          setState(() {
                            _toTimeController.clear();
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildTimeDropdown(
                        "To Time",
                        "To Time",
                        _toTimeController,
                        enabled:
                            selectedScheduleId != null &&
                            selectedTemplateId != null &&
                            _fromDateController.text.isNotEmpty &&
                            _fromTimeController.text.isNotEmpty &&
                            _toDateController.text.isNotEmpty,
                        onChanged: () {
                          setState(() {
                            selectAllSlot = false;
                            selectedSlotsByDay.clear();
                            _prepopulateSlots();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (isAllFilled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
                            selectedSlotsByDay[key] = List.from(slotPairs);
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
                    "Select All",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.0,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
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
    return Column(
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

                    if (_filteredTemplateFiles.isEmpty) {
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                "No matching files found",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
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
                          rows: _filteredTemplateFiles.map((file) {
                            final index =
                                _filteredTemplateFiles.indexOf(file) + 1;
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
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child:
                                          (file['file_name'] != null &&
                                              file['file_name']
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty)
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

  Widget _buildDropdown({
    required String label,
    required String hint,
    int? value,
    required List<dynamic> items,
    bool showAdd = false,
    required ValueChanged<int?> onChanged,
  }) {
    final seenLabels = <String>{};
    final seenValues = <int>{};
    final List<SearchableDropdownItem<int>> dropdownItems = [];

    for (var item in items) {
      final idStr =
          item['schedule_id']?.toString() ?? item['id']?.toString() ?? '';
      final id = int.tryParse(idStr) ?? 0;

      final itemLabel =
          item['schedule_name']?.toString() ??
          item['template_name']?.toString() ??
          item['temp_name']?.toString() ??
          item['name']?.toString() ??
          item['role_name']?.toString() ??
          item['device_name']?.toString() ??
          item['location_name']?.toString() ??
          item['department_name']?.toString() ??
          'Unnamed';

      final normLabel = itemLabel.toLowerCase().trim();
      if (seenLabels.add(normLabel) && seenValues.add(id)) {
        dropdownItems.add(
          SearchableDropdownItem<int>(value: id, label: itemLabel),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SearchableDropdown<int>(
                value: value,
                hint: hint,
                items: dropdownItems,
                onChanged: onChanged,
              ),
            ),
            if (showAdd) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Material(
                    color: Colors.blue.shade300,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showSchedulePopup(),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildTimeDropdown(
    String label,
    String hint,
    TextEditingController controller, {
    bool enabled = true,
    VoidCallback? onChanged,
  }) {
    final List<String> slots = _generateTimeSlots();
    final String? currentValue =
        (slots.contains(controller.text) && controller.text.isNotEmpty)
        ? controller.text
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.0,
            color: Color(0xFF334155),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        SearchableDropdown<String>(
          value: currentValue,
          hint: hint,
          items: slots.map((time) {
            return SearchableDropdownItem<String>(value: time, label: time);
          }).toList(),
          onChanged: enabled
              ? (v) {
                  if (v != null) {
                    setState(() {
                      controller.text = v;
                    });
                    if (onChanged != null) onChanged();
                  }
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    VoidCallback? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.0,
            color: Color(0xFF334155),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          enabled: enabled,
          style: const TextStyle(fontSize: 13.0, color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'MM/DD/YYYY',
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
            disabledBorder: OutlineInputBorder(
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
          onTap: enabled
              ? () async {
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
                    if (onChanged != null) onChanged();
                  }
                }
              : null,
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
              const Text(
                "Show",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 12),
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
                  onChanged: (v) => setState(() {
                    entriesValue = v!;
                  }),
                ),
              ),
              const SizedBox(width: 8),
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
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 16),
                hintText: "Search...",
                hintStyle: const TextStyle(
                  fontSize: 12.0,
                  color: Color(0xFF94A3B8),
                ),
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
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
            ),
            itemCount: slotPairs.length,
            itemBuilder: (context, index) {
              String slot = slotPairs[index];
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
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      slot,
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
