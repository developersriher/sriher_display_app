import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import '../../widgets/animated_heading.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

class MappingView extends StatefulWidget {
  const MappingView({super.key});

  @override
  State<MappingView> createState() => _MappingViewState();
}

class _MappingViewState extends State<MappingView> {
  // ─── API CONFIG ───────────────────────────────────────────────────────────
  final String _apiKey =
      '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';
  String get _base => getBaseUrl();

  // ─── STATE ────────────────────────────────────────────────────────────────
  List<dynamic> _mappingList = [];
  List<dynamic> _deviceList = []; // from deviceview → data.DeviceMasters
  List<dynamic> _locationList = []; // from locationview → data (flat list)

  bool _tableLoading = true;
  bool _dropsLoading = true;
  bool _submitting = false;
  int? _editingId;
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Sorting
  int _sortColumnIndex = 0;
  bool _sortAscending = false;

  // Pagination & search
  String _entries = '10';
  int _page = 1;
  final _searchCtrl = TextEditingController();
  String _searchQ = '';

  // ─── FORM STATE ───────────────────────────────────────────────────────────
  // Row 1: device code (dropdown) | device name (text) | device model (text)
  String? _selDeviceId; // id of selected device
  final _devNameCtrl = TextEditingController();
  final _devModelCtrl = TextEditingController();

  // Row 2: location (dropdown) + Submit button
  String? _selLocationId;

  // ─── LIFECYCLE ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadDropdowns();
    _fetchMappings();
    _searchCtrl.addListener(
      () => setState(() {
        _searchQ = _searchCtrl.text.toLowerCase();
        _page = 1;
      }),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _devNameCtrl.dispose();
    _devModelCtrl.dispose();
    super.dispose();
  }

  // ─── API CALLS ────────────────────────────────────────────────────────────

  Future<void> _loadDropdowns() async {
    setState(() => _dropsLoading = true);
    try {
      final body = jsonEncode({'api_key': _apiKey});
      final headers = {'Content-Type': 'application/json'};

      final devRes = await http.post(
        Uri.parse('$_base/deviceview'),
        headers: headers,
        body: body,
      );
      final locRes = await http.post(
        Uri.parse('$_base/locationview'),
        headers: headers,
        body: body,
      );

      if (devRes.statusCode == 200) {
        final parsed = jsonDecode(devRes.body);
        final dataField = parsed['data'];
        if (!mounted) return;
        if (dataField is Map) {
          final masters = dataField['DeviceMasters'];
          if (masters is List) _deviceList = masters;
        } else if (dataField is List) {
          _deviceList = dataField;
        }
        _deviceList.sort((a, b) {
          final ca = int.tryParse(a['device_code']?.toString() ?? '0') ?? 0;
          final cb = int.tryParse(b['device_code']?.toString() ?? '0') ?? 0;
          return ca.compareTo(cb);
        });
      }

      if (locRes.statusCode == 200) {
        final parsed = jsonDecode(locRes.body);
        final dataField = parsed['data'];
        if (!mounted) return;
        if (dataField is List) {
          _locationList = dataField;
        } else if (dataField is Map) {
          final first = dataField.values.first;
          if (first is List) _locationList = first;
        }

        final seen = <String>{};
        _locationList = _locationList.where((item) {
          final locName = item['location_name']?.toString() ?? '';
          if (seen.contains(locName)) return false;
          seen.add(locName);
          return true;
        }).toList();
      }
    } catch (e) {
      debugPrint('Dropdown Load Error: $e');
    } finally {
      if (mounted) setState(() => _dropsLoading = false);
    }
  }

  // API 1: Fetch all mappings — latest (highest id) at top
  Future<void> _fetchMappings() async {
    setState(() => _tableLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/mappingview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': _apiKey}),
      );
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        List<dynamic> data = [];
        final dataField = parsed['data'];
        if (!mounted) return;
        if (dataField is List) {
          data = dataField;
        } else if (dataField is Map) {
          data = dataField.values.first as List<dynamic>? ?? [];
        }
        // Sort: highest id first (newest at top)
        data.sort((a, b) {
          final ia = int.tryParse(a['id'].toString()) ?? 0;
          final ib = int.tryParse(b['id'].toString()) ?? 0;
          return ib.compareTo(ia);
        });
        setState(() => _mappingList = data);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Fetch error: $e');
    } finally {
      if (mounted) setState(() => _tableLoading = false);
    }
  }

  // API 2: Insert mapping
  Future<void> _insert() async {
    if (!_validate()) return;
    setState(() => _submitting = true);
    try {
      // Find the device entry to get device_name and device_model
      final dev = _deviceList.firstWhere(
        (d) => d['id'].toString() == _selDeviceId,
        orElse: () => {},
      );
      final loc = _locationList.firstWhere(
        (l) => l['id'].toString() == _selLocationId,
        orElse: () => {},
      );

      final res = await http.post(
        Uri.parse('$_base/insertMappingview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _apiKey,
          'device_id': int.parse(_selDeviceId!),
          'device_name': _devNameCtrl.text.trim().isEmpty
              ? (dev['device_name'] ?? '')
              : _devNameCtrl.text.trim(),
          'device_model': _devModelCtrl.text.trim().isEmpty
              ? (dev['device_model'] ?? '')
              : _devModelCtrl.text.trim(),
          'location_id': int.parse(_selLocationId!),
          'location_floor': loc['floor'] ?? '',
          'sub_location': loc['sublocation'] ?? '',
        }),
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
        _snack('Mapping submitted successfully!');
        _clearForm();
        await _fetchMappings();
      } else {
        if (!mounted) return;
        _snack('Server error: ${res.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Insert error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // API 3: Load for edit
  Future<void> _loadForEdit(dynamic id) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/mappingEditview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': _apiKey, 'id': int.parse(id.toString())}),
      );
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body);
        dynamic data = parsed['data'];
        if (data is List && data.isNotEmpty) data = data.first;

        String? foundDeviceId;
        final deviceIdStr = data['device_id']?.toString();
        if (deviceIdStr != null) {
          final byId = _deviceList.firstWhere(
            (d) => d['id'].toString() == deviceIdStr,
            orElse: () => <String, dynamic>{},
          );
          if ((byId as Map).isNotEmpty) foundDeviceId = deviceIdStr;
        }
        if (foundDeviceId == null) {
          final deviceCode = data['device_code']?.toString();
          if (deviceCode != null) {
            final byCode = _deviceList.firstWhere(
              (d) => d['device_code']?.toString() == deviceCode,
              orElse: () => <String, dynamic>{},
            );
            if ((byCode as Map).isNotEmpty) {
              foundDeviceId = byCode['id']?.toString();
            }
          }
        }

        String? foundLocId;
        final locNameStr = data['location_name']?.toString();
        if (locNameStr != null) {
          final loc = _locationList.firstWhere(
            (l) => l['location_name']?.toString() == locNameStr,
            orElse: () => <String, dynamic>{},
          );
          if ((loc as Map).isNotEmpty) foundLocId = loc['id']?.toString();
        }

        if (!mounted) return;
        setState(() {
          _editingId = int.parse(id.toString());
          _selDeviceId = foundDeviceId;
          _selLocationId = foundLocId;
          _devNameCtrl.text = data['device_name'] ?? '';
          _devModelCtrl.text = data['device_model'] ?? '';
        });
        _showMappingDialog(); // Open dialog after loading data
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Edit load error: $e');
    }
  }

  // API 4: Update
  Future<void> _update() async {
    if (!_validate()) return;
    setState(() => _submitting = true);
    try {
      final loc = _locationList.firstWhere(
        (l) => l['id'].toString() == _selLocationId,
        orElse: () => {},
      );

      final res = await http.post(
        Uri.parse('$_base/mappingUpdateview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _apiKey,
          'id': _editingId,
          'device_id': int.parse(_selDeviceId!),
          'device_name': _devNameCtrl.text.trim(),
          'device_model': _devModelCtrl.text.trim(),
          'location_id': int.parse(_selLocationId!),
          'location_floor': loc['floor'] ?? '',
          'sub_location': loc['sublocation'] ?? '',
        }),
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        if (Navigator.canPop(context)) Navigator.pop(context);
        _snack('Record updated!');
        _clearForm();
        await _fetchMappings();
      } else {
        if (!mounted) return;
        _snack('Update failed: ${res.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Update error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // API 5: Delete
  Future<void> _delete(dynamic id) async {
    final confirm = await StylishDialog.show<bool>(
      context: context,
      title: "Delete Confirmation",
      icon: Icons.delete_forever_rounded,
      maxWidth: 400,
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to delete this mapping? All associated data will be removed.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Delete",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    try {
      final res = await http.post(
        Uri.parse('$_base/deleteMappingview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': _apiKey, 'id': int.parse(id.toString())}),
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        _snack('Mapping deleted.');
        await _fetchMappings();
      } else {
        if (!mounted) return;
        _snack('Delete failed: ${res.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Delete error: $e');
    }
  }

  // ──────────────────────────── POPUP DIALOG ────────────────────────────────

  void _showMappingDialog() {
    _formKey = GlobalKey<FormState>();
    StylishDialog.show(
      context: context,
      title: _editingId == null
          ? "Create Device Mapping"
          : "Edit Mapping Details",
      subtitle: "Link display hardware to facility locations",
      icon: _editingId == null
          ? Icons.add_link_rounded
          : Icons.edit_note_rounded,
      width: MediaQuery.of(context).size.width * 0.6,
      builder: (context, setDialogState) {
        return Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("DEVICE INFORMATION"),
              Row(
                children: [
                  Expanded(
                    child: _dropsLoading
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _buildDropdownField(
                            hint: "Select Device Code",
                            value: _selDeviceId,
                            items: _deviceList
                                .map(
                                  (d) => SearchableDropdownItem<String>(
                                    value: d['id'].toString(),
                                    label:
                                        d['device_code']?.toString() ??
                                        d['id'].toString(),
                                  ),
                                )
                                .toList(),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Please select the Device Code'
                                : null,
                            onChanged: (v) {
                              final dev = _deviceList.firstWhere(
                                (d) => d['id'].toString() == v,
                                orElse: () => <String, dynamic>{},
                              );
                              if ((dev as Map).isNotEmpty) {
                                _devNameCtrl.text =
                                    dev['device_name']?.toString() ?? '';
                                _devModelCtrl.text =
                                    dev['device_model']?.toString() ?? '';
                              }
                              setDialogState(() => _selDeviceId = v);
                              setState(() => _selDeviceId = v);
                            },
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      "Device Name",
                      _devNameCtrl,
                      readOnly: false,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please enter the Device Name'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                "Device Model",
                _devModelCtrl,
                readOnly: false,
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please enter the Device Model'
                    : null,
              ),
              const SizedBox(height: 32),
              _buildSectionHeader("LOCATION ASSIGNMENT"),
              _dropsLoading
                  ? const Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _buildDropdownField(
                      hint: "Select Location Name",
                      value: _selLocationId,
                      items: _locationList
                          .map(
                            (l) => SearchableDropdownItem<String>(
                              value: l['id'].toString(),
                              label:
                                  l['location_name']?.toString() ??
                                  l['id'].toString(),
                            ),
                          )
                          .toList(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Please select the Location Name'
                          : null,
                      onChanged: (v) {
                        setDialogState(() => _selLocationId = v);
                        setState(() => _selLocationId = v);
                      },
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
                    onPressed: _submitting
                        ? null
                        : () async {
                            if (_formKey.currentState!.validate()) {
                              Navigator.pop(context);
                              if (_editingId == null) {
                                await _insert();
                              } else {
                                await _update();
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
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _editingId == null ? "Submit" : "Update",
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
        );
      },
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  bool _validate() {
    if (_selDeviceId == null) {
      _snack('Please select a device code.');
      return false;
    }
    if (_selLocationId == null) {
      _snack('Please select a location.');
      return false;
    }
    return true;
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _selDeviceId = null;
      _selLocationId = null;
    });
    _devNameCtrl.clear();
    _devModelCtrl.clear();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  List<dynamic> get _filtered {
    List<dynamic> list = List.from(_mappingList);

    if (_searchQ.isNotEmpty) {
      list = list.where((item) {
        final code = (item['device_code'] ?? '').toString().toLowerCase();
        final name = (item['device_name'] ?? '').toString().toLowerCase();
        final model = (item['device_model'] ?? '').toString().toLowerCase();
        final loc = (item['location_name'] ?? '').toString().toLowerCase();
        final floor = (item['floor'] ?? '').toString().toLowerCase();
        final sub = (item['sublocation'] ?? '').toString().toLowerCase();
        return code.contains(_searchQ) ||
            name.contains(_searchQ) ||
            model.contains(_searchQ) ||
            loc.contains(_searchQ) ||
            floor.contains(_searchQ) ||
            sub.contains(_searchQ);
      }).toList();
    }

    list.sort((a, b) {
      String aVal = "";
      String bVal = "";

      String val(Map data, List<String> keys) {
        for (var k in keys) {
          if (data.containsKey(k) && data[k] != null) return data[k].toString();
        }
        return "-";
      }

      final dataA = (a is Map)
          ? Map<String, dynamic>.from(a)
          : <String, dynamic>{};
      final dataB = (b is Map)
          ? Map<String, dynamic>.from(b)
          : <String, dynamic>{};

      switch (_sortColumnIndex) {
        case 1:
          aVal = val(dataA, ['device_code']);
          bVal = val(dataB, ['device_code']);
          break;
        case 2:
          aVal = val(dataA, ['device_name']);
          bVal = val(dataB, ['device_name']);
          break;
        case 3:
          aVal = val(dataA, ['device_model']);
          bVal = val(dataB, ['device_model']);
          break;
        case 4:
          aVal = val(dataA, ['location_name']);
          bVal = val(dataB, ['location_name']);
          break;
        case 5:
          aVal = val(dataA, ['floor']);
          bVal = val(dataB, ['floor']);
          break;
        case 6:
          aVal = val(dataA, ['sublocation']);
          bVal = val(dataB, ['sublocation']);
          break;
        default:
          aVal = val(dataA, ['id']);
          bVal = val(dataB, ['id']);
          break;
      }

      if (_sortColumnIndex == 0) {
        final intA = int.tryParse(aVal) ?? 0;
        final intB = int.tryParse(bVal) ?? 0;
        return _sortAscending ? intA.compareTo(intB) : intB.compareTo(intA);
      }

      return _sortAscending
          ? aVal.toLowerCase().compareTo(bVal.toLowerCase())
          : bVal.toLowerCase().compareTo(aVal.toLowerCase());
    });

    return list;
  }

  List<dynamic> get _paged {
    final per = int.tryParse(_entries) ?? 10;
    final start = (_page - 1) * per;
    final list = _filtered;
    if (start >= list.length) return [];
    return list.sublist(start, (start + per).clamp(0, list.length));
  }

  int get _totalPages => ((_filtered.length) / (int.tryParse(_entries) ?? 10))
      .ceil()
      .clamp(1, 9999);

  // ─── BUILD ────────────────────────────────────────────────────────────────

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
                    text: "Device Mapping",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      _clearForm();
                      _showMappingDialog();
                    },
                    icon: const Icon(Icons.add_link_rounded, size: 20),
                    label: const Text(
                      "CREATE MAPPING",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // List Card
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
                  child: _buildTableCard(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  );

  // ─── FORM CARD ───────────────────────────────────────────────────────────

  Widget _buildFormCard() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Device Code dropdown | Device Name text | Device Model text ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Code Dropdown
              Expanded(
                child: _dropsLoading
                    ? const Center(
                        child: SizedBox(
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : SearchableDropdown<String>(
                        value: _selDeviceId,
                        hint: "Select Device Code",
                        items: _deviceList.map((d) {
                          return SearchableDropdownItem<String>(
                            value: d['id'].toString(),
                            label:
                                d['device_code']?.toString() ??
                                d['id'].toString(),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selDeviceId = v),
                      ),
              ),
              const SizedBox(width: 16),
              // Device Name
              Expanded(
                child: TextFormField(
                  controller: _devNameCtrl,
                  decoration: _hintDec('Device Name'),
                ),
              ),
              const SizedBox(width: 16),
              // Device Model
              Expanded(
                child: TextFormField(
                  controller: _devModelCtrl,
                  decoration: _hintDec('Device Model'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ── Row 2: Location Name dropdown | Submit button ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Location dropdown
              Expanded(
                child: _dropsLoading
                    ? const Center(
                        child: SizedBox(
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : SearchableDropdown<String>(
                        value: _selLocationId,
                        hint: "Select Location Name",
                        items: _locationList.map((l) {
                          return SearchableDropdownItem<String>(
                            value: l['id'].toString(),
                            label:
                                l['location_name']?.toString() ??
                                l['id'].toString(),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selLocationId = v),
                      ),
              ),
              const SizedBox(width: 16),

              // Submit / Update Button
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    if (_editingId != null) ...[
                      OutlinedButton(
                        onPressed: _clearForm,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF000000),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: _submitting
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                if (_editingId == null) {
                                  _insert();
                                } else {
                                  _update();
                                }
                              }
                            },
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _editingId == null ? 'Submit' : 'Update',
                              style: const TextStyle(
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
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label) => InputDecoration(
    hintText: label,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF334155), width: 1.6),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  InputDecoration _hintDec(String hint) => _inputDec(hint);

  Widget _buildTextField(
    String hint,
    TextEditingController controller, {
    bool readOnly = false,
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
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
          decoration: InputDecoration(
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
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String hint,
    String? value,
    required List<SearchableDropdownItem<String>> items,
    required ValueChanged<String?> onChanged,
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
          items: items,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
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

  // ─── TABLE CARD ───────────────────────────────────────────────────────────

  Widget _buildTableCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Entries + search
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Show ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(
                    width: 75,
                    height: 35,
                    child: DropdownButtonFormField<String>(
                      value: _entries,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                      ),
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
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _entries = v;
                            _page = 1;
                          });
                        }
                      },
                    ),
                  ),
                  const Text(
                    ' entries',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search mappings...',
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _tableLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildTable(),
          ),

          const SizedBox(height: 16),

          // Footer pagination
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${_paged.length} of ${_filtered.length} records',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
              Row(
                children: [
                  _pageBtn(
                    'Prev',
                    enabled: _page > 1,
                    onTap: () => setState(() => _page--),
                  ),

                  _pageNum('$_page / $_totalPages'),

                  _pageBtn(
                    'Next',
                    enabled: _page < _totalPages,
                    onTap: () => setState(() => _page++),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final rows = _paged;
    if (_mappingList.isNotEmpty && _filtered.isEmpty) {
      return Center(
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
              "No matching mappings found",
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Try a different search term",
              style: TextStyle(color: Colors.grey, fontSize: 13.0),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                columnSpacing: 20,
                horizontalMargin: 16,
                headingRowHeight: 46,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                border: TableBorder.all(color: Colors.grey.shade100, width: 1),
                columns: [
                  _col('S.No', 0),
                  _col('Device Code', 1),
                  _col('Device Name', 2),
                  _col('Device Model', 3),
                  _col('Location', 4),
                  _col('Floor', 5),
                  _col('Sub Location', 6),
                  _col('Edit', -1),
                  _col('Delete', -1),
                ],
                rows: rows.isEmpty
                    ? [
                        DataRow(
                          cells: List.generate(
                            9,
                            (i) => DataCell(
                              i == 0
                                  ? const Text(
                                      'No data available',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                        ),
                      ]
                    : List.generate(rows.length, (i) {
                        final item = rows[i];
                        final sno =
                            (_page - 1) * (int.tryParse(_entries) ?? 10) +
                            i +
                            1;
                        return DataRow(
                          color: WidgetStateProperty.resolveWith(
                            (s) =>
                                i.isEven ? Colors.grey.shade50 : Colors.white,
                          ),
                          cells: [
                            DataCell(_cellText('$sno', 40)),
                            DataCell(
                              _cellText(
                                item['device_code']?.toString() ?? '-',
                                80,
                              ),
                            ),
                            DataCell(
                              _cellText(
                                item['device_name']?.toString() ?? '-',
                                120,
                              ),
                            ),
                            DataCell(
                              _cellText(
                                item['device_model']?.toString() ?? '-',
                                120,
                              ),
                            ),
                            DataCell(
                              _cellText(
                                item['location_name']?.toString() ?? '-',
                                120,
                              ),
                            ),
                            DataCell(
                              _cellText(item['floor']?.toString() ?? '-', 100),
                            ),
                            DataCell(
                              _cellText(
                                item['sublocation']?.toString() ?? '-',
                                100,
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                tooltip: 'Edit',
                                onPressed: () => _loadForEdit(item['id']),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                tooltip: 'Delete',
                                onPressed: () => _delete(item['id']),
                              ),
                            ),
                          ],
                        );
                      }),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cellText(String text, double width) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black87),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  DataColumn _col(String label, int colIndex) => DataColumn(
    label: InkWell(
      onTap: colIndex < 0
          ? null
          : () {
              setState(() {
                if (_sortColumnIndex == colIndex) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortColumnIndex = colIndex;
                  _sortAscending = true;
                }
                _page = 1;
              });
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
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
          if (colIndex >= 0) ...[
            const SizedBox(width: 4),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  heightFactor: 0.4,
                  child: Icon(
                    Icons.arrow_drop_up,
                    size: 18,
                    color: _sortColumnIndex == colIndex && _sortAscending
                        ? Colors.blue
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
                Align(
                  heightFactor: 0.4,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: _sortColumnIndex == colIndex && !_sortAscending
                        ? Colors.blue
                        : Colors.grey.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _pageBtn(String label, {bool enabled = true, VoidCallback? onTap}) {
    return ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? Colors.blue.shade50 : Colors.grey.shade50,
        foregroundColor: enabled ? Colors.blue.shade800 : Colors.black26,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: enabled ? Colors.blue.shade100 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _pageNum(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}
