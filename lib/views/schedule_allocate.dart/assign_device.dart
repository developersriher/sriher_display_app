import '../../api_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/searchable_dropdown.dart';

class AssignDeviceView extends StatefulWidget {
  const AssignDeviceView({super.key});

  @override
  State<AssignDeviceView> createState() => _AssignDeviceViewState();
}

class _AssignDeviceViewState extends State<AssignDeviceView>
    with SingleTickerProviderStateMixin {
  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  List<dynamic> deviceList = [];
  List<dynamic> scheduleList = [];
  List<dynamic> assignedList = [];
  bool isLoadingDevices = false;
  bool isLoadingSchedules = false;
  bool isLoadingAssigned = false;

  int? selectedDeviceId;
  int? selectedScheduleId;
  DateTime today = DateTime.now();
  int? selectedDay;

  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    selectedDay = today.day;
    _fetchDevices();
    _fetchSchedules(null);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0), // Start from RIGHT
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    setState(() => isLoadingDevices = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/assignDevice_deviceListview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => deviceList = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching devices: $e");
    } finally {
      setState(() => isLoadingDevices = false);
    }
  }

  Future<void> _fetchSchedules(int? deviceId) async {
    setState(() => isLoadingSchedules = true);
    try {
      final Map<String, dynamic> requestBody = {"api_key": _apiKey};
      if (deviceId != null) {
        requestBody["device_id"] = deviceId;
      }
      final response = await http.post(
        Uri.parse('$_baseUrl/assignDevice_scheduleListview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => scheduleList = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching schedules: $e");
    } finally {
      setState(() => isLoadingSchedules = false);
    }
  }

  Future<void> _fetchAssignedSchedules(int deviceId) async {
    setState(() => isLoadingAssigned = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/assignDevice_assignedListview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"api_key": _apiKey, "device_id": deviceId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => assignedList = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Error fetching assigned schedules: $e");
    } finally {
      setState(() => isLoadingAssigned = false);
    }
  }

  Future<void> _handleAssignmentSubmit() async {
    if (selectedDeviceId == null || selectedScheduleId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/assignDevice_insertview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "device_id": selectedDeviceId,
          "schedule_id": selectedScheduleId,
        }),
      );
      if (response.statusCode == 200) {
        _fetchAssignedSchedules(selectedDeviceId!);
        _showSnackBar("Assigned Successfully");
      }
    } catch (e) {
      debugPrint("Error submitting assignment: $e");
    }
  }

  Future<void> _handleAssignmentRemove(int scheduleId) async {
    if (selectedDeviceId == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/assignDevice_removeview'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "api_key": _apiKey,
          "device_id": selectedDeviceId,
          "schedule_id": scheduleId,
        }),
      );
      if (response.statusCode == 200) {
        _fetchAssignedSchedules(selectedDeviceId!);
        _showSnackBar("Removed Successfully");
      }
    } catch (e) {
      debugPrint("Error removing assignment: $e");
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

  @override
  Widget build(BuildContext context) {
    return SelectionArea(child: Padding(
      padding: const EdgeInsets.only(
        left: 24.0,
        right: 24.0,
        bottom: 24.0,
        top: 20.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnimatedHeading(text: "Assign Schedule for Device"),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            label: "Device Name",
                            hint: "Select Device",
                            value: selectedDeviceId,
                            items: deviceList,
                            onChanged: (val) {
                              setState(() {
                                selectedDeviceId = val;
                                selectedScheduleId = null;
                                scheduleList = [];
                                assignedList = [];
                              });
                              if (val != null) {
                                _fetchSchedules(val);
                                _fetchAssignedSchedules(val);
                                _controller.forward(from: 0.0);
                              } else {
                                _fetchSchedules(null);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildDropdown(
                            label: "Schedule Name",
                            hint: "Select Schedule",
                            value: selectedScheduleId,
                            items: scheduleList,
                            onChanged: (val) {
                              setState(() => selectedScheduleId = val);
                              if (val != null) {
                                _controller.forward(from: 0.0);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 24),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
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
                              disabledBackgroundColor: Colors.grey.shade200,
                            ),
                            onPressed:
                                (selectedDeviceId != null &&
                                    selectedScheduleId != null)
                                ? _handleAssignmentSubmit
                                : null,
                            child: const Text(
                              "SUBMIT",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selectedDeviceId != null)
                      FadeTransition(
                        opacity: _opacityAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            key: ValueKey('calendar_col_$selectedDeviceId'),
                            children: [
                              const SizedBox(height: 24),
                              const Divider(height: 1),
                              const SizedBox(height: 24),
                              _buildCagedCalendar(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildCagedCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: _buildSmallCalendar(),
            ),
          ),
          Container(width: 1, height: 450, color: Colors.grey.shade100),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(32.0),
              color: Colors.blue.withOpacity(0.01),
              child: _buildScheduleSideBox(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String hint,
    int? value,
    required List<dynamic> items,
    required ValueChanged<int?> onChanged,
  }) {
    final seenLabels = <String>{};
    final seenValues = <int>{};
    final List<SearchableDropdownItem<int>> dropdownItems = [];

    for (var item in items) {
      final idStr = item['schedule_id']?.toString() ?? item['id']?.toString() ?? '';
      final id = int.tryParse(idStr) ?? 0;
      
      final itemLabel =
          item['device_name']?.toString() ??
          item['schedule_name']?.toString() ??
          item['temp_name']?.toString() ??
          item['template_name']?.toString() ??
          item['device_code']?.toString() ??
          item['name']?.toString() ??
          '';

      if (itemLabel.trim().isEmpty) continue;

      final normLabel = itemLabel.toLowerCase().trim();
      if (seenLabels.add(normLabel) && seenValues.add(id)) {
        dropdownItems.add(SearchableDropdownItem<int>(
          value: id,
          label: itemLabel,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        SearchableDropdown<int>(
          value: value,
          hint: hint,
          items: dropdownItems,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSmallCalendar() {
    int daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    int firstWeekday = DateTime(today.year, today.month, 1).weekday % 7;
    String monthName = DateFormat('MMMM yyyy').format(today).toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.display_settings, size: 20, color: Colors.blue.shade800),
              const SizedBox(width: 12),
              Text(
                monthName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.5,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
              childAspectRatio: 1.2,
            ),
            itemCount: daysInMonth + firstWeekday,
            itemBuilder: (context, index) {
              if (index < firstWeekday) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade50.withOpacity(0.5),
                      width: 0.5,
                    ),
                  ),
                );
              }

              int day = index - firstWeekday + 1;
              bool isSelected = day == selectedDay;
              bool hasAssignment = assignedList.any(
                (a) => int.tryParse(a['day']?.toString() ?? '') == day,
              );

              return InkWell(
                onTap: () => setState(() => selectedDay = day),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade100, width: 0.5),
                    color: isSelected
                        ? Colors.blue.shade50
                        : (hasAssignment
                              ? Colors.green.shade50.withOpacity(0.3)
                              : Colors.white),
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isSelected)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        "$day",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (hasAssignment
                                    ? Colors.green.shade700
                                    : Colors.black87),
                        ),
                      ),
                      if (hasAssignment && !isSelected)
                        Positioned(
                          bottom: 4,
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSideBox() {
    final dayAssignment = assignedList.firstWhere(
      (a) => int.tryParse(a['day']?.toString() ?? '') == selectedDay,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "SCHEDULE DETAILS",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
            color: Colors.blueAccent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          DateFormat(
            'EEEE, MMMM dd, yyyy',
          ).format(DateTime(today.year, today.month, selectedDay!)),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dayAssignment != null
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    dayAssignment != null
                        ? Icons.check_circle
                        : Icons.info_outline,
                    color: dayAssignment != null ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    dayAssignment != null ? "Active Schedule" : "No Assignment",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: dayAssignment != null
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                dayAssignment != null
                    ? (dayAssignment['schedule_name'] ?? 'Untitled Schedule')
                    : "There is no schedule assigned to this device for the selected date.",
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: dayAssignment != null
                      ? Colors.black87
                      : Colors.black54,
                  fontStyle: dayAssignment != null
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              ),
              if (dayAssignment != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () =>
                        _handleAssignmentRemove(dayAssignment['schedule_id']),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text("REMOVE ASSIGNMENT"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
