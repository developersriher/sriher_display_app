import 'package:intl/intl.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ScheduleListView extends StatefulWidget {
  final Function(Map<String, dynamic>)? onEdit;
  final Function(Map<String, dynamic>)? onExtend;

  const ScheduleListView({super.key, this.onEdit, this.onExtend});

  @override
  State<ScheduleListView> createState() => _ScheduleListViewState();
}

class _ScheduleListViewState extends State<ScheduleListView> {
  final String _baseUrl = "https://display.sriher.com";
  final String _apiKey =
      "933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2";

  List<dynamic> scheduleData = [];
  List<dynamic> _filteredData = [];
  bool isLoading = false;

  // true = Active (default), false = Inactive
  bool showActive = true;

  // Inactive date range
  int _selYear = DateTime.now().year;
  int _selMonth = DateTime.now().month;

  // Table controls
  String entriesValue = "10";
  int _currentPage = 1;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _fetchSchedules();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── APIs ──────────────────────────────────────────────────────────────────

  /// Fetch active schedules (no date params needed)
  Future<void> _fetchSchedules() async {
    setState(() {
      isLoading = true;
      scheduleData = [];
      _filteredData = [];
    });
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/scheduleList_activeListview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"api_key": _apiKey}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          scheduleData = (data['data'] as List<dynamic>?) ?? [];
          _currentPage = 1;
        });
        _applyFilter();
      } else {
        _showServiceUnavailable();
      }
    } catch (_) {
      _showServiceUnavailable();
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Fetch inactive schedules with explicit year+month so popup closure
  /// values are used directly — avoids StylishDialog setState shadowing bug.
  Future<void> _fetchInactive(int year, int month) async {
    // from_date = Jan 1 of selected year  →  broad enough range to always return data
    // to_date   = last day of selected month
    final fromDate = DateFormat('yyyy-MM-dd').format(DateTime(year, 1, 1));
    final toDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(year, month + 1, 0)); // day 0 = last day of month

    // Update outer widget state BEFORE async work
    setState(() {
      showActive = false;
      _selYear = year;
      _selMonth = month;
      isLoading = true;
      scheduleData = [];
      _filteredData = [];
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/scheduleList_inactiveListview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "from_date": fromDate,
              "to_date": toDate,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          scheduleData = (data['data'] as List<dynamic>?) ?? [];
          _currentPage = 1;
        });
        _applyFilter();
      } else {
        _showServiceUnavailable();
      }
    } catch (_) {
      _showServiceUnavailable();
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateStatus(int id, int newStatus) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/scheduleList_statusUpdateview'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "api_key": _apiKey,
              "schedule_id": id,
              "status": newStatus,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _showSnack("Status updated successfully.");
        // Refresh whichever tab is currently active
        if (showActive) {
          _fetchSchedules();
        } else {
          _fetchInactive(_selYear, _selMonth);
        }
      } else {
        _showSnack("Failed to update status.", isError: true);
      }
    } catch (_) {
      _showSnack("Network error.", isError: true);
    }
  }

  // ── Filter / pagination ───────────────────────────────────────────────────

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredData = scheduleData.where((item) {
        return (item['schedule_name'] ?? '').toString().toLowerCase().contains(q) ||
            (item['temp_name'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
      _currentPage = 1;
    });
  }

  int get _perPage => int.tryParse(entriesValue) ?? 10;
  int get _totalPages => (_filteredData.length / _perPage).ceil().clamp(1, 999);

  List<dynamic> get _pageData {
    final start = (_currentPage - 1) * _perPage;
    if (start >= _filteredData.length) return [];
    return _filteredData.sublist(
        start, (start + _perPage).clamp(0, _filteredData.length));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade800 : Colors.blue.shade800,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _showServiceUnavailable() {
    if (!mounted) return;
    StylishDialog.show(
      context: context,
      title: "Service Unavailable",
      subtitle: "The server is unreachable. Please try again later.",
      icon: Icons.cloud_off,
      maxWidth: 400,
      builder: (ctx, _) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  /// Popup: pick Month + Year, then Save to fetch inactive
  void _showInactivePopup() {
    int tmpYear = _selYear;
    int tmpMonth = _selMonth;

    StylishDialog.show(
      context: context,
      title: "SELECT ARCHIVE PERIOD",
      subtitle: "Choose a month and year to view inactive schedules.",
      maxWidth: 450,
      builder: (ctx, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Month
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Month",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0F172A))),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: tmpMonth,
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (m) =>
                            setPopupState(() => tmpMonth = m!),
                        items: List.generate(12, (i) => i + 1)
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(DateFormat('MMMM')
                                      .format(DateTime(2024, m))),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Year
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Year",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0F172A))),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: tmpYear,
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (y) =>
                            setPopupState(() => tmpYear = y!),
                        items: List.generate(
                                5, (i) => DateTime.now().year - i)
                            .map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text(y.toString()),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Close
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Close",
                      style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                // Save
                ElevatedButton(
                  onPressed: () {
                    // Close dialog first, then fetch with captured local vars.
                    // We call _fetchInactive(tmpYear, tmpMonth) directly so
                    // the dialog's StatefulBuilder setState doesn't shadow
                    // the outer widget's setState.
                    Navigator.pop(ctx);
                    _fetchInactive(tmpYear, tmpMonth);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 32),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Save",
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header row ───────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Back arrow chip – only visible in inactive view
                    if (!showActive) ...[
                      Tooltip(
                        message: "Back to Active Schedules",
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              showActive = true;
                              scheduleData = [];
                            });
                            _fetchSchedules();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Dynamic heading
                    Expanded(
                      child: AnimatedHeading(
                        text: showActive
                            ? "Active Schedule List"
                            : "Inactive Schedule List",
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Right-side action
                    if (showActive)
                      // "View Inactive" button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 2,
                        ),
                        onPressed: _showInactivePopup,
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text(
                          "View Inactive",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      // Period button – click to re-open month/year popup
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 2,
                        ),
                        onPressed: _showInactivePopup,
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: Text(
                          "${DateFormat('MMM').format(DateTime(2024, _selMonth))} $_selYear",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Table card
                Expanded(
                  child: Container(
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
                      children: [
                        _buildListHeader(),
                        const Divider(height: 1),
                        Expanded(
                          child: isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _buildTableContainer(),
                        ),
                        const Divider(height: 1),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTableContainer() {
    final rows = _pageData;
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      const Color(0xFF0F172A)),
                  headingRowHeight: 48,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 20,
                  columnSpacing: 20,
                  columns: [
                    _col('S.NO'),
                    _col('SCHEDULE NAME'),
                    _col('TEMPLATE NAME'),
                    _col('FROM TIME – TO TIME'),
                    _col('FROM DATE'),
                    _col('TO DATE'),
                    _col('STATUS'),
                    _col('CHANGES'),
                  ],
                  rows: rows.asMap().entries.map((e) {
                    final sno =
                        (_currentPage - 1) * _perPage + e.key + 1;
                    return _buildRow(e.value, sno);
                  }).toList(),
                ),
              ),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        scheduleData.isEmpty
                            ? "No schedules found"
                            : "No results match your search",
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  DataRow _buildRow(dynamic item, int sno) {
    final isActive =
        (item['status'] == 1 || item['status'] == '1');
    final id = int.tryParse(item['id'].toString()) ?? 0;
    return DataRow(cells: [
      DataCell(Text(sno.toString(),
          style:
              const TextStyle(color: Colors.black54, fontSize: 13))),
      DataCell(Text(item['schedule_name'] ?? '-',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.black87))),
      DataCell(Text(item['temp_name'] ?? '-',
          style: const TextStyle(color: Colors.black87))),
      DataCell(Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          "${item['from_time'] ?? '-'} – ${item['to_time'] ?? '-'}",
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700),
        ),
      )),
      DataCell(Text(item['from_date'] ?? '-',
          style: const TextStyle(color: Colors.black87))),
      DataCell(Text(item['to_date'] ?? '-',
          style: const TextStyle(color: Colors.black87))),
      DataCell(Transform.scale(
        scale: 0.8,
        child: Switch(
          value: isActive,
          activeColor: Colors.green.shade600,
          inactiveThumbColor: Colors.red.shade400,
          inactiveTrackColor: Colors.red.shade100,
          onChanged: (val) => _updateStatus(id, val ? 1 : 0),
        ),
      )),
      DataCell(_buildChangesBtn(item)),
    ]);
  }

  Widget _buildChangesBtn(dynamic item) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      elevation: 4,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings, color: Colors.blue, size: 18),
            SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, color: Colors.blue, size: 18),
          ],
        ),
      ),
      onSelected: (value) {
        if (value == 'edit' && widget.onEdit != null) {
          widget.onEdit!(Map<String, dynamic>.from(item));
        } else if (value == 'extend' && widget.onExtend != null) {
          widget.onExtend!(Map<String, dynamic>.from(item));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined,
                size: 20, color: Colors.blue.shade600),
            const SizedBox(width: 12),
            const Text("Edit Schedule",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ]),
        ),
        PopupMenuItem(
          value: 'extend',
          child: Row(children: [
            Icon(Icons.more_time,
                size: 20, color: Colors.orange.shade600),
            const SizedBox(width: 12),
            const Text("Extend Period",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ]),
        ),
      ],
    );
  }

  DataColumn _col(String label) => DataColumn(
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      );

  // ── List header ───────────────────────────────────────────────────────────

 Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
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
                width: 70,
                height: 36,
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
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        entriesValue = v;
                        _currentPage = 1;
                      });
                    }
                  },
                  items: ['10', '25', '50']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
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
          ),
          SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search schedules…',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Colors.grey,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
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
  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final start = _filteredData.isEmpty
        ? 0
        : (_currentPage - 1) * _perPage + 1;
    final end =
        (_currentPage * _perPage).clamp(0, _filteredData.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _filteredData.isEmpty
                ? "Showing 0 entries"
                : "Showing $start–$end of ${_filteredData.length} entries",
            style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
          Row(children: [
            _pageBtn("Previous",
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--)),
            ..._pageNums(),
            _pageBtn("Next",
                enabled: _currentPage < _totalPages,
                onTap: () => setState(() => _currentPage++)),
          ]),
        ],
      ),
    );
  }

  List<Widget> _pageNums() {
    if (_totalPages <= 1) return [_pageBtn("1", active: true, onTap: null)];
    return List.generate(_totalPages.clamp(1, 5), (i) {
      final p = i + 1;
      return _pageBtn(p.toString(),
          active: p == _currentPage,
          onTap: () => setState(() => _currentPage = p));
    });
  }

  Widget _pageBtn(String label,
      {bool active = false,
      bool enabled = true,
      VoidCallback? onTap}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? Colors.blue.shade600 : Colors.white,
        foregroundColor:
            active ? Colors.white : Colors.blue.shade600,
        side: BorderSide(
            color: active
                ? Colors.blue.shade600
                : Colors.grey.shade300),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 34),
      ),
      onPressed: (enabled && onTap != null) ? onTap : null,
      child: Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}
