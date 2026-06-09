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

  /// POST /deviceview
  Future<void> _fetchDeviceList() async {
    setState(() => isLoadingDevices = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/deviceview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
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
        });
      } else {
        _showSnackBar("Failed to load devices (${response.statusCode}).");
      }
    } catch (e) {
      _showSnackBar("Error fetching devices: $e");
    } finally {
      setState(() => isLoadingDevices = false);
    }
  }

  /// POST /assignDevice_deviceListview
  Future<void> _fetchAssignDeviceList() async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/assignDevice_deviceListview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          assignDeviceList = data['data'] ?? [];
        });
      }
    } catch (e) {
      _showSnackBar("Error fetching assign devices: $e");
    }
  }

  /// POST /copyWipe_deviceSchedulesview
  /// Body:    { "api_key": "...", "device_id": <int> }
  /// Response: { "status": "Success", "schedules": [...] }
  Future<void> _fetchDeviceSchedules(int deviceId) async {
    setState(() {
      isLoadingSchedules = true;
      sourceSchedules = [];
      hasConflict = null;
      conflictMessage = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/copyWipe_deviceSchedulesview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey, "device_id": deviceId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          sourceSchedules = data['schedules'] ?? [];
          // Reset target selection whenever source changes
          selectedTargetDeviceId = null;
        });
      } else {
        _showSnackBar("Failed to load schedules (${response.statusCode}).");
      }
    } catch (e) {
      _showSnackBar("Error fetching schedules: $e");
    } finally {
      setState(() => isLoadingSchedules = false);
    }
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
      isCheckingConflicts = true;
      hasConflict = null;
      conflictMessage = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/copyWipe_checkConflictview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "source_device_id": selectedSourceDeviceId,
              "target_device_id": selectedTargetDeviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = (data['status'] ?? '').toString().toLowerCase();
        final msg = data['Message'] ?? data['message'] ?? '';
        setState(() {
          // "Success" → no conflict; anything else (e.g. "Failed") → conflict
          hasConflict = status != 'success';
          conflictMessage = msg.isNotEmpty
              ? msg
              : (hasConflict! ? "Conflict detected." : "No conflicts found.");
        });
      } else {
        _showSnackBar("Conflict check failed (${response.statusCode}).");
      }
    } catch (e) {
      _showSnackBar("Error checking conflicts: $e");
    } finally {
      setState(() => isCheckingConflicts = false);
    }
  }

  /// POST /copyWipe_copyScheduleview
  /// Body:    { "api_key": "...", "source_device_id": <int>, "target_device_id": <int> }
  /// Response: { "status": "Success|Failed", "Message": "..." }
  Future<void> _copySchedule() async {
    if (selectedSourceDeviceId == null || selectedTargetDeviceId == null) {
      _showSnackBar("Please select both Source Device and Assign Device.");
      return;
    }

    setState(() => isSubmittingCopy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/copyWipe_copyScheduleview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "source_device_id": selectedSourceDeviceId,
              "target_device_id": selectedTargetDeviceId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final msg =
            data['Message'] ??
            data['message'] ??
            "Schedules copied successfully!";
        final status = (data['status'] ?? '').toString().toLowerCase();
        _showSnackBar(msg);
        if (status == 'success') {
          setState(() {
            selectedSourceDeviceId = null;
            selectedTargetDeviceId = null;
            sourceSchedules = [];
            hasConflict = null;
            conflictMessage = null;
          });
        }
      } else {
        _showSnackBar("Copy failed (${response.statusCode}).");
      }
    } catch (e) {
      _showSnackBar("Error copying schedules: $e");
    } finally {
      setState(() => isSubmittingCopy = false);
    }
  }

  /// POST /copyWipe_wipeOffview
  /// Body:    { "api_key": "...", "device_id": <int> }
  /// Response: { "status": "Success|Failed", "Message": "..." }
  Future<void> _wipeOff() async {
    if (selectedWipeDeviceId == null) {
      _showSnackBar("Please select a device to wipe.");
      return;
    }

    bool? confirm = await StylishDialog.show<bool>(
      context: context,
      title: "CONFIRM WIPE OFF",
      maxWidth: 480,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to permanently remove ALL schedules from this device? This action cannot be undone.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
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
                    onPressed: () => Navigator.pop(context, true),
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
                      "Wipe Everything",
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

    if (confirm != true) return;

    setState(() => isSubmittingWipe = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/copyWipe_wipeOffview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "device_id": selectedWipeDeviceId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final msg =
            data['Message'] ??
            data['message'] ??
            "Schedules wiped successfully!";
        _showSnackBar(msg);
        setState(() => selectedWipeDeviceId = null);
      } else {
        _showSnackBar("Wipe failed (${response.statusCode}).");
      }
    } catch (e) {
      _showSnackBar("Error wiping schedules: $e");
    } finally {
      setState(() => isSubmittingWipe = false);
    }
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
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── COPY SECTION ──────────────────────────────────────────────────
            const AnimatedHeading(text: "Copy Schedule - Devices"),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(32),
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
                  // ── Row: Source | Target | Copy button ──────────────────────
                  isLoadingDevices
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : Row(
                          // 1. Align all items to the center vertically
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Source device dropdown
                            Expanded(
                              child: _buildDropdown(
                                hintText: "Choose source device…",
                                value: selectedSourceDeviceId,
                                items: deviceList,
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    selectedSourceDeviceId = val;
                                    hasConflict = null;
                                    conflictMessage = null;
                                  });
                                  _fetchDeviceSchedules(val);
                                },
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Target device dropdown
                            Expanded(
                              child: _buildDropdown(
                                hintText: selectedSourceDeviceId == null
                                    ? "Select source device first…"
                                    : "Choose assign device…",
                                value: selectedTargetDeviceId,
                                items: assignDeviceList,
                                onChanged: selectedSourceDeviceId == null
                                    ? null
                                    : (val) {
                                        setState(() {
                                          selectedTargetDeviceId = val;
                                          hasConflict = null;
                                          conflictMessage = null;
                                        });
                                        if (val != null) _checkConflicts();
                                      },
                              ),
                            ),
                            const SizedBox(width: 24),
                            // 2. Removed the Padding(top: 30) wrapper
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical:
                                      20, // Match the height to your dropdown
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
                                      "COPY SCHEDULE",
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
                          const SizedBox(width: 10),
                          Text(
                            "No schedules found on the selected source device.",
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 48),

            // ── WIPE OFF SECTION ──────────────────────────────────────────────
            const AnimatedHeading(text: "Wipe Off Devices"),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(32),
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
                  : Row(
                      // 1. CHANGE THIS TO CENTER
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _buildDropdown(
                            hintText: "Choose device to wipe…",
                            value: selectedWipeDeviceId,
                            items: deviceList,
                            onChanged: (val) =>
                                setState(() => selectedWipeDeviceId = val),
                          ),
                        ),
                        const SizedBox(width: 24),
                        // 2. REMOVED THE PADDING(TOP: 30) WRAPPER
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
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
                          onPressed: isSubmittingWipe ? null : _wipeOff,
                          child: isSubmittingWipe
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "WIPE OFF DEVICE",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                        const Spacer(),
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
