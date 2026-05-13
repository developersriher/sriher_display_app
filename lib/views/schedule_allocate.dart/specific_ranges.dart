import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

class SpecificRangesView extends StatefulWidget {
  const SpecificRangesView({super.key});

  @override
  State<SpecificRangesView> createState() => _SpecificRangesViewState();
}

class _SpecificRangesViewState extends State<SpecificRangesView> {
  final String _baseUrl = "https://display.sriher.com";
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  bool skipDates = false;
  int? selectedScheduleId;
  int? selectedTemplateId;
  String entriesValue = "10";

  List<dynamic> scheduleList = [];
  List<dynamic> templateList = [];
  List<dynamic> templateFiles = [];
  List<String> offDates = [];

  bool isLoadingSchedules = false;
  bool isLoadingTemplates = false;
  bool isLoadingFiles = false;
  bool selectAllSlots = false;

  Map<int, bool> slotSelection = {};

  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _scheduleNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _scheduleNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
    for (int i = 0; i < 48; i++) {
      slotSelection[i] = false;
    }
  }

  List<String> _generateTimeSlots() {
    List<String> slots = [];
    for (int i = 0; i < 24; i++) {
      String start = i.toString().padLeft(2, '0');
      String end = (i + 1 == 24 ? "00" : (i + 1).toString().padLeft(2, '0'));
      slots.add("$start:00-$start:30");
      slots.add("$start:30-$end:00");
    }
    return slots;
  }

  Future<void> _fetchDropdownData() async {
    setState(() {
      isLoadingSchedules = true;
      isLoadingTemplates = true;
    });
    try {
      // Fetch Schedules from the main schedule list API
      final schedRes = await http.post(
        Uri.parse('$_baseUrl/scheduleMenu_listview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      // Fetch Templates from the schedulerange API
      final tempRes = await http.post(
        Uri.parse('$_baseUrl/schedulerange_scheduleNamesview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );

      if (schedRes.statusCode == 200) {
        final schedData = jsonDecode(schedRes.body);
        final List<dynamic> rawSchedules = schedData['data'] ?? [];
        
        // Filter for unique schedule names to avoid dropdown duplicates
        final Map<String, dynamic> uniqueSchedules = {};
        for (var item in rawSchedules) {
          final name = item['schedule_name']?.toString() ?? '';
          if (name.isNotEmpty && !uniqueSchedules.containsKey(name)) {
            uniqueSchedules[name] = item;
          }
        }

        setState(() {
          scheduleList = uniqueSchedules.values.toList();
        });
      }

      if (tempRes.statusCode == 200) {
        final tempData = jsonDecode(tempRes.body);
        setState(() {
          // Keep templates from this endpoint
          templateList = tempData['templates'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error fetching dropdown data: $e");
    } finally {
      setState(() {
        isLoadingSchedules = false;
        isLoadingTemplates = false;
      });
    }
  }

  Future<void> _fetchTemplateFiles(int tempId, {int? scheduleId}) async {
    setState(() => isLoadingFiles = true);
    try {
      final body = {"api_key": _apiKey, "temp_id": tempId};
      if (scheduleId != null) body["schedule_id"] = scheduleId;

      final response = await http.post(
        Uri.parse('$_baseUrl/schedulerange_temptableview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          templateFiles = data['files'] ?? data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error fetching template files: $e");
    } finally {
      setState(() => isLoadingFiles = false);
    }
  }

  Future<void> _fetchOffDates() async {
    if (_fromDateController.text.isEmpty || _toDateController.text.isEmpty)
      return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/schedulerange_getOffDatesview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "from_date": _fromDateController.text,
          "to_date": _toDateController.text,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => offDates = List<String>.from(data['data'] ?? []));
      }
    } catch (e) {
      debugPrint("Error fetching off dates: $e");
    }
  }

  Future<void> _showConflictDatesPopup() async {
    if (_fromDateController.text.isEmpty || _toDateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select From Date and To Date first"),
        ),
      );
      setState(() => skipDates = false);
      return;
    }

    List<String> rangeDates = [];
    try {
      DateTime start = DateFormat('yyyy-MM-dd').parse(_fromDateController.text);
      DateTime end = DateFormat('yyyy-MM-dd').parse(_toDateController.text);
      for (int i = 0; i <= end.difference(start).inDays; i++) {
        rangeDates.add(
          DateFormat('yyyy-MM-dd').format(start.add(Duration(days: i))),
        );
      }
    } catch (e) {
      debugPrint("Error parsing dates: $e");
    }

    List<String> tempSelected = List.from(offDates);
    bool showDateList = false;

  StylishDialog.show(
      context: context,
      title: "Remove Dates",
      subtitle: "Select dates to exclude from the schedule.",
      maxWidth: 480,
      builder: (context, setDialogState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toggle Button
            GestureDetector(
              onTap: () {
                setDialogState(() {
                  showDateList = !showDateList;
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: showDateList
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1),
                    width: showDateList ? 1.6 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      showDateList
                          ? Icons.calendar_month_rounded
                          : Icons.calendar_today_rounded,
                      size: 16,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      showDateList
                          ? "Hide date list"
                          : "Select dates to remove",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      showDateList
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),

            // Date List
            if (showDateList) ...[
              const SizedBox(height: 12),
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Select All Row
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                      ),
                      child: CheckboxListTile(
                        dense: true,
                        title: const Text(
                          "Select All Dates",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        value: tempSelected.length == rangeDates.length &&
                            rangeDates.isNotEmpty,
                        activeColor: const Color(0xFF0F172A),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val!) {
                              tempSelected = List.from(rangeDates);
                            } else {
                              tempSelected = [];
                            }
                          });
                        },
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    // Date Items
                    Expanded(
                      child: ListView.separated(
                        itemCount: rangeDates.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: Color(0xFFE2E8F0),
                        ),
                        itemBuilder: (context, index) {
                          final date = rangeDates[index];
                          final isSelected = tempSelected.contains(date);
                          return Container(
                            color: isSelected
                                ? const Color(0xFFF1F5F9)
                                : Colors.transparent,
                            child: CheckboxListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 13,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    date,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                              value: isSelected,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: const Color(0xFF0F172A),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val!) {
                                    tempSelected.add(date);
                                  } else {
                                    tempSelected.remove(date);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    // Selected count badge
                    if (tempSelected.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        child: Text(
                          "${tempSelected.length} date${tempSelected.length > 1 ? 's' : ''} selected",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => skipDates = false);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() => offDates = List.from(tempSelected));
                    Navigator.pop(context);
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Save",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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

  Future<void> _handleInsertSlots() async {
    if (selectedScheduleId == null ||
        selectedTemplateId == null ||
        _fromDateController.text.isEmpty ||
        _toDateController.text.isEmpty) {
      _showSnackBar("Please complete all required fields");
      return;
    }

    List<int> selectedIndices = slotSelection.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (selectedIndices.isEmpty) {
      _showSnackBar("Please select at least one slot");
      return;
    }

    List<String> times = _generateTimeSlots();
    bool success = true;

    String durationStr = "01:00:00";
    try {
      final selectedTemp = templateList.firstWhere(
        (t) => int.tryParse(t['id'].toString()) == selectedTemplateId,
        orElse: () => null,
      );
      if (selectedTemp != null && selectedTemp['duration'] != null) {
        durationStr = selectedTemp['duration'].toString();
      }
    } catch (e) {
      debugPrint("Error extracting template duration: $e");
    }

    for (int index in selectedIndices) {
      String slot = times[index];
      List<String> range = slot.split('-');

      final body = {
        "api_key": _apiKey,
        "schedule_id": selectedScheduleId,
        "temp_id": selectedTemplateId,
        "from_date": _fromDateController.text,
        "to_date": _toDateController.text,
        "t_duration": durationStr,
        "slot_from_time": range[0],
        "slot_to_time": range[1],
        "r_dates": skipDates ? offDates : [],
      };

      try {
        final response = await http.post(
          Uri.parse('$_baseUrl/schedulerange_insertSlotsview'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );
        if (response.statusCode != 200) success = false;
      } catch (e) {
        success = false;
        debugPrint("Error inserting slot $slot: $e");
      }
    }

    if (success) {
      _showSnackBar("Slots successfully assigned");
    } else {
      _showSnackBar("Some slots failed to assign");
    }
  }

  void _showSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.blue.shade800,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  void _addNewSchedule(String name) {
    if (name.isEmpty) return;
    setState(() {
      // Mock an ID for now until API is integrated
      final newId = DateTime.now().millisecondsSinceEpoch % 10000;
      scheduleList = List.from(scheduleList)..add({
        "id": newId.toString(),
        "schedule_name": name,
      });
      selectedScheduleId = newId;
      _scheduleNameController.clear();
    });
  }

  void _showAddSchedulePopup(BuildContext context) {
    StylishDialog.show(
      context: context,
      title: "NEW SCHEDULE",
      subtitle: "Define a new department or purpose for scheduling.",
      maxWidth: 480,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _scheduleNameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                final name = _scheduleNameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  _addNewSchedule(name);
                }
              },
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: "Enter the schedule name",
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
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
                  onPressed: () {
                    final name = _scheduleNameController.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      _addNewSchedule(name);
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
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "Create Schedule",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
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
    return SelectionArea(
      child: LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 1000;

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AnimatedHeading(text: "Schedule Range Allocation"),
              const SizedBox(height: 20),
              // Combined Header Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                  children: [
                    // Row 1: Dropdowns
                    isNarrow
                        ? Column(
                            children: [
                              _buildDropdown(
                                label: "Schedule Name",
                                hint: "Select Schedule",
                                value: selectedScheduleId,
                                items: scheduleList,
                                showAdd: true,
                                onChanged: (val) {
                                  setState(() {
                                    selectedScheduleId = val;
                                  });
                                  if (val != null &&
                                      selectedTemplateId != null) {
                                    _fetchTemplateFiles(
                                      selectedTemplateId!,
                                      scheduleId: val,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildDropdown(
                                label: "Template Name",
                                hint: "Select Template",
                                value: selectedTemplateId,
                                items: templateList,
                                onChanged: (val) {
                                  setState(() {
                                    selectedTemplateId = val;
                                    templateFiles = [];
                                  });
                                  if (val != null) {
                                    _fetchTemplateFiles(
                                      val,
                                      scheduleId: selectedScheduleId,
                                    );
                                  }
                                },
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildDropdown(
                                  label: "Schedule Name",
                                  hint: "Select Schedule",
                                  value: selectedScheduleId,
                                  items: scheduleList,
                                  showAdd: true,
                                  onChanged: (val) {
                                    setState(() {
                                      selectedScheduleId = val;
                                    });
                                    if (val != null &&
                                        selectedTemplateId != null) {
                                      _fetchTemplateFiles(
                                        selectedTemplateId!,
                                        scheduleId: val,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: _buildDropdown(
                                  label: "Template Name",
                                  hint: "Select Template",
                                  value: selectedTemplateId,
                                  items: templateList,
                                  onChanged: (val) {
                                    setState(() {
                                      selectedTemplateId = val;
                                      templateFiles = [];
                                    });
                                    if (val != null) {
                                      _fetchTemplateFiles(
                                        val,
                                        scheduleId: selectedScheduleId,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 24),
                    // Row 2: Dates, Checkbox, Submit
                    isNarrow
                        ? Column(
                            children: [
                              _buildDateField("From Date", _fromDateController),
                              const SizedBox(height: 16),
                              _buildDateField("To Date", _toDateController),
                              const SizedBox(height: 16),
                              _buildCheckboxRow(),
                              const SizedBox(height: 24),
                              _buildSubmitButton(isFullWidth: true),
                            ],
                          )
                        : Row(
  crossAxisAlignment: CrossAxisAlignment.end,
  mainAxisAlignment: MainAxisAlignment.start, // Keeps everything on the left
  children: [
    // Fixed width for From Date
    SizedBox(
      width: 180, // Half the usual size
      child: _buildDateField(
        "From Date",
        _fromDateController,
      ),
    ),
    const SizedBox(width: 12),
    // Fixed width for To Date
    SizedBox(
      width: 180, // Half the usual size
      child: _buildDateField(
        "To Date",
        _toDateController,
      ),
    ),
    const SizedBox(width: 20),
    _buildCheckboxRow(),
    const SizedBox(width: 20),
    _buildSubmitButton(),
    // This is the secret: it pushes everything to the left
    const Spacer(flex: 2), 
  ],
)
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Lower content shown after selection
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (selectedTemplateId != null) ...[
                        if (isNarrow) ...[
                          _buildSlotsPanel(),
                          const SizedBox(height: 24),
                          _buildTemplateDetailsPanel(),
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: _buildSlotsPanel()),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 6,
                                child: _buildTemplateDetailsPanel(),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
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

  Widget _buildCheckboxRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: skipDates,
          activeColor: Colors.blue.shade600,
          onChanged: (val) {
            setState(() => skipDates = val!);
            if (val!) _showConflictDatesPopup();
          },
        ),
        const Text(
          "Skip Dates(Between Selected Range)",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

 Widget _buildSubmitButton({bool isFullWidth = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 32,
          vertical: 12,
        ),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: _handleInsertSlots,
      child: const Text(
        "SUBMIT",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildSlotsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPanelHeader(
          "SELECT TIME SLOTS",
          Icons.access_time,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: selectAllSlots,
                activeColor: const Color.fromARGB(255, 140, 193, 239),
                side: const BorderSide(color: Color.fromARGB(255, 21, 97, 183)),
                onChanged: (val) {
                  setState(() {
                    selectAllSlots = val!;
                    for (int i = 0; i < 48; i++) {
                      slotSelection[i] = val;
                    }
                  });
                },
              ),
              const Text(
                "Select All",
                style: TextStyle(
                  color: Color.fromARGB(255, 16, 96, 188),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
            ),
            itemCount: 48,
            itemBuilder: (context, index) {
              String slot = _generateTimeSlots()[index];
              bool isSelected = slotSelection[index] ?? false;
              return InkWell(
                onTap: () => setState(() => slotSelection[index] = !isSelected),
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
                        fontSize: 10,
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

  Widget _buildTemplateDetailsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPanelHeader("TEMPLATE PREVIEW", Icons.visibility_outlined),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildListHeader(),
              _buildTableHeader(),
              if (isLoadingFiles)
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (templateFiles.isEmpty)
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      "No files in this template",
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: templateFiles.length,
                  itemBuilder: (context, index) {
                    final file = templateFiles[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade100),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Center(
                              child: Text(
                                "${file['play_order'] ?? file['order_no'] ?? file['file_order'] ?? index + 1}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: (file['file_name'] != null && file['file_name'].toString().trim().isNotEmpty)
                                      ? Image.network(
                                          "$_baseUrl/uploads/${file['file_name']}",
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                Icons.broken_image,
                                                size: 24,
                                                color: Colors.grey,
                                              ),
                                        )
                                      : const Icon(Icons.image, size: 24, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              file['user_filename'] ?? file['file_name'] ?? '-',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "${file['duration'] ?? '30'}s",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
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
              _buildTableFooter(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanelHeader(String title, IconData icon, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue.shade800, size: 18),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.blue.shade50,
      child: const Row(
        children: [
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                "PLAY ORDER",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                "FILE",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              "FILE NAME",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                "DURATION",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
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
                "entries",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text(
                "Search:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 200,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: "Search files...",
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
          ),
        ],
      ),
    );
  }

  Widget _buildTableFooter() {
    int rowsPerPage = int.tryParse(entriesValue) ?? 10;
    int totalPages = (templateFiles.length / rowsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Total Files: ${templateFiles.length}",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMiniBtn("Prev", isFirst: true),
              ...List.generate(totalPages, (index) {
                return _buildMiniBtn(
                  "${index + 1}",
                  active: (index + 1) == 1,
                );
              }),
              _buildMiniBtn("Next", isLast: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBtn(
    String label, {
    bool active = false,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: active ? Colors.blue.shade700 : Colors.white,
          foregroundColor: active ? Colors.white : Colors.black87,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          side: BorderSide(
            color: active ? Colors.blue.shade700 : Colors.grey.shade300,
            width: 1.0,
          ),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {},
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SearchableDropdown<int>(
                value: value,
                hint: hint,
                items: items.map((item) {
                  return SearchableDropdownItem<int>(
                    value: int.tryParse(item['id']?.toString() ?? '') ?? 0,
                    label: item['name']?.toString() ??
                        item['schedule_name']?.toString() ??
                        item['temp_name']?.toString() ??
                        '',
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
            if (showAdd) ...[
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.blue),
                  onPressed: () => _showAddSchedulePopup(context),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color.fromARGB(255, 83, 96, 115),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
  controller: controller,
  readOnly: true,
  style: const TextStyle(fontSize: 13), // Main text size
  decoration: InputDecoration(
    hintText: 'YYYY-MM-DD',
    // 1. THIS REDUCES THE HINT TEXT SIZE
    hintStyle: TextStyle(
      fontSize: 14, 
      color: Colors.grey.shade400,
    ),
    
    filled: true,
    fillColor: Colors.white,
    prefixIcon: const Icon(
      Icons.calendar_today,
      size: 16, // Slightly smaller icon to match
      color: Colors.blue,
    ),
    
    // 2. REDUCE PADDING TO MATCH THE SMALLER TEXT
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  ),
  onTap: () async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(), 
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      // Ensure you have the intl package for DateFormat
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {}); 
    }
  },
),
      ],
    );
  }
}