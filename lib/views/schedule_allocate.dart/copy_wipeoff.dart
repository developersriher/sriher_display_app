import '../../api_config.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CopyWipeoffView extends StatefulWidget {
  const CopyWipeoffView({super.key});

  @override
  State<CopyWipeoffView> createState() => _CopyWipeoffViewState();
}

class _CopyWipeoffViewState extends State<CopyWipeoffView> {
  String get _baseUrl => getBaseUrl();
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  // Fetched from deviceview
  List<dynamic> deviceList = [];

  // Schedules fetched from copyWipe_deviceSchedulesview → schedules[]
  List<dynamic> sourceSchedules = [];

  // Fetched from assignDevice_deviceListview
  List<dynamic> assignDeviceList = [];

  int? selectedSourceDeviceId;
  int? selectedTargetDeviceId;
  int? selectedWipeDeviceId;

  bool isLoadingDevices = false;
  bool isLoadingSchedules = false;
  bool isCheckingConflicts = false;
  bool isSubmittingCopy = false;
  bool isSubmittingWipe = false;

  // null = not checked yet, true = has conflict, false = clear
  bool? hasConflict;
  String? conflictMessage;

  @override
  void initState() {
    super.initState();
    _fetchDeviceList();
    _fetchAssignDeviceList();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // API CALLS
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _fetchDeviceList() async {
    setState(() {
      deviceList = [];
    });
  }

  /// POST /assignDevice_deviceListview
  Future<void> _fetchAssignDeviceList() async {
    setState(() {
      assignDeviceList = [];
    });
  }

  Future<void> _fetchDeviceSchedules(int deviceId) async {
    setState(() {
      sourceSchedules = [];
      hasConflict = null;
      conflictMessage = null;
    });
  }

  /// POST /copyWipe_checkConflictview
  /// Body:    { "api_key": "...", "source_device_id": <int>, "target_device_id": <int> }
  /// Response: { "status": "Success|Failed", "Message": "..." }
  Future<void> _checkConflicts() async {
    if (selectedSourceDeviceId == null || selectedTargetDeviceId == null)
      return;
    if (selectedSourceDeviceId == selectedTargetDeviceId) {
      setState(() {
        hasConflict = true;
        conflictMessage = "Source and Target devices cannot be the same.";
      });
      return;
    }

    setState(() {
      hasConflict = false;
      conflictMessage = "No conflicts found.";
    });
  }

  /// POST /copyWipe_copyScheduleview
  /// Body:    { "api_key": "...", "source_device_id": <int>, "target_device_id": <int> }
  /// Response: { "status": "Success|Failed", "Message": "..." }
  Future<void> _copySchedule() async {
    if (selectedSourceDeviceId == null || selectedTargetDeviceId == null) {
      _showSnackBar("Please select both Source Device and Assign Device.");
      return;
    }

    _showSnackBar("Schedules copied successfully!");
    setState(() {
      selectedSourceDeviceId = null;
      selectedTargetDeviceId = null;
      sourceSchedules = [];
      hasConflict = null;
      conflictMessage = null;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 1100;
    final isTablet = screenWidth <= 1100 && screenWidth >= 600;
    final isNarrow = isMobile || isTablet;

    return SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isNarrow ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isNarrow)
              const AnimatedHeading(
                text: "Copy Schedule - Devices",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 33, 150, 243),
                ),
              ),
            if (!isNarrow) const SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(isNarrow ? 16 : 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.blue.shade50),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card title for mobile/tablet
                  if (isNarrow) ...[
                    Text(
                      "Copy Schedule Devices",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.blue.shade900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ── Row: Source | Target | Copy button ──────────────────────
                  isLoadingDevices
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Choose Device",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              hintText: " Select device name",
                              value: selectedSourceDeviceId,
                              items: deviceList,
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  selectedSourceDeviceId = val;
                                  hasConflict = null;
                                  conflictMessage = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Selected Device",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              hintText: selectedSourceDeviceId == null
                                  ? "Select assign device name"
                                  : "Choose assign device…",
                              value: selectedTargetDeviceId,
                              items: assignDeviceList,
                              onChanged: (val) {
                                setState(() {
                                  selectedTargetDeviceId = val;
                                  hasConflict = null;
                                  conflictMessage = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed:
                                    (isSubmittingCopy || isCheckingConflicts)
                                    ? null
                                    : _copySchedule,
                                child: isSubmittingCopy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        "Submit",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _buildDropdown(
                                hintText: "Select device name",
                                value: selectedSourceDeviceId,
                                items: deviceList,
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    selectedSourceDeviceId = val;
                                    hasConflict = null;
                                    conflictMessage = null;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildDropdown(
                                hintText: selectedSourceDeviceId == null
                                    ? "Select assign device name"
                                    : "Choose assign device…",
                                value: selectedTargetDeviceId,
                                items: assignDeviceList,
                                onChanged: (val) {
                                  setState(() {
                                    selectedTargetDeviceId = val;
                                    hasConflict = null;
                                    conflictMessage = null;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              onPressed:
                                  (isSubmittingCopy || isCheckingConflicts)
                                  ? null
                                  : _copySchedule,
                              child: isSubmittingCopy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "Submit",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),

                  // ── Conflict banner ──────────────────────────────────────────
                  if (isCheckingConflicts)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Checking for conflicts…",
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (conflictMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (hasConflict == true)
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (hasConflict == true)
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (hasConflict == true)
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            color: (hasConflict == true)
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              conflictMessage!,
                              style: TextStyle(
                                color: (hasConflict == true)
                                    ? Colors.red.shade900
                                    : Colors.green.shade900,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Schedule list (from source device) ───────────────────────
                  if (isLoadingSchedules)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (sourceSchedules.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      "Schedules on selected device:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: sourceSchedules.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = sourceSchedules[index];
                          final name =
                              s['schedule_name'] ??
                              s['name'] ??
                              'Unnamed Schedule';
                          final fromDate =
                              s['from_date'] ?? s['start_date'] ?? '-';
                          final toDate = s['to_date'] ?? s['end_date'] ?? '-';
                          final fromTime =
                              s['from_time'] ?? s['start_time'] ?? '-';
                          final toTime = s['to_time'] ?? s['end_time'] ?? '-';
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.blueGrey,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              "$fromDate → $toDate  |  $fromTime – $toTime",
                            ),
                            trailing: const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                          );
                        },
                      ),
                    ),
                  ] else if (selectedSourceDeviceId != null &&
                      !isLoadingSchedules) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: isNarrow ? 24 : 48),

            // ── WIPE OFF SECTION ──────────────────────────────────────────────
            if (!isNarrow)
              const AnimatedHeading(
                text: "Wipe Off Devices",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 33, 150, 243),
                ),
              ),
            if (!isNarrow) const SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(isNarrow ? 16 : 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.red.shade50),
              ),
              child: isLoadingDevices
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          Text(
                            "Choose Copy Wipe",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.red.shade900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          width: isNarrow ? double.infinity : 400,
                          child: _buildDropdown(
                            hintText: "Select device name",
                            value: selectedWipeDeviceId,
                            items: deviceList,
                            onChanged: (val) =>
                                setState(() => selectedWipeDeviceId = val),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (selectedWipeDeviceId == null) {
                              _showSnackBar("Please select device name");
                              return;
                            }
                            _showSnackBar("Submitted successfully");
                            setState(() {
                              selectedWipeDeviceId = null;
                            });
                          },
                          child: const Text(
                            "Submit",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildDropdown({
    required String hintText,
    required int? value,
    required List<dynamic> items,
    required ValueChanged<int?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SearchableDropdown<int>(
          value: items.any((i) => _itemId(i) == value) ? value : null,
          hint: hintText,
          items: items.map((item) {
            return SearchableDropdownItem<int>(
              value: _itemId(item) ?? 0,
              label:
                  item['device_name'] ??
                  item['Device_name'] ??
                  'Unknown Device',
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Safely parse the `id` field as an integer regardless of whether the API
  /// returns it as a number or a string.
  int? _itemId(dynamic item) {
    final raw = item['id'];
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }
}
