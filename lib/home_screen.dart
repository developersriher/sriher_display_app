import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'login_page.dart';

import 'package:sriher_display_application/views/dashboard_view.dart';
import 'package:sriher_display_application/views/authentication/add_user_view.dart';
import 'package:sriher_display_application/views/file_master.dart/file_upload.dart';
import 'package:sriher_display_application/views/template_master.dart/create_template.dart';
import 'package:sriher_display_application/views/template_master.dart/default_template.dart';
import 'package:sriher_display_application/views/template_master.dart/select_template.dart';
import 'package:sriher_display_application/views/schedule_allocate.dart/schedule_allocate_main.dart';
import 'package:sriher_display_application/views/schedule_allocate.dart/assign_device.dart';
import 'package:sriher_display_application/views/schedule_allocate.dart/schedule_list.dart';
import 'package:sriher_display_application/views/schedule_allocate.dart/specific_ranges.dart';
import 'package:sriher_display_application/views/schedule_allocate.dart/copy_wipeoff.dart';
import 'package:sriher_display_application/views/masters.dart/role.dart';
import 'package:sriher_display_application/views/masters.dart/device_master.dart';
import 'package:sriher_display_application/views/masters.dart/department.dart';
import 'package:sriher_display_application/views/masters.dart/location_master.dart';
import 'package:sriher_display_application/views/masters.dart/mapping.dart';
import 'package:sriher_display_application/widgets/stylish_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  String? _userName;
  String? _userRole;
  String? _roleId;
  String? _userId;
  Set<String> _adminOrManagerRoleIds = {'1', '4', '13', '18'};

  Map<String, dynamic>? _scheduleEditData;
  bool _isScheduleExtend = false;
  String? _expandedSection;

  bool get _canAccessAuth {
    final currentRole = (_userRole ?? '').toLowerCase().trim();
    final currentRoleId = (_roleId ?? '').toLowerCase().trim();
    return currentRole == 'admin' ||
        currentRole == 'manager' ||
        currentRole == 'administrator' ||
        currentRoleId == '1' ||
        currentRoleId == '4' ||
        currentRoleId == '13' ||
        currentRoleId == '18' ||
        _adminOrManagerRoleIds.contains(currentRoleId) ||
        _adminOrManagerRoleIds.contains(currentRole);
  }

  late AnimationController _sidebarController;
  late AnimationController _viewController;
  late Animation<double> _sidebarFade;
  late Animation<Offset> _sidebarSlide;
  late Animation<double> _viewFade;
  late Animation<Offset> _viewSlide;

  @override
  void initState() {
    super.initState();
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _sidebarFade = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOut,
    );
    _sidebarSlide =
        Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _sidebarController,
            curve: Curves.easeOutCubic,
          ),
        );

    _viewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _viewFade = CurvedAnimation(parent: _viewController, curve: Curves.easeIn);
    _viewSlide = Tween<Offset>(begin: const Offset(0.01, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _viewController, curve: Curves.easeOutCubic),
        );

    _sidebarController.forward();
    _viewController.forward();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName');
      _userRole = prefs.getString('userRole');
      _roleId = prefs.getString('roleId');
      _userId = prefs.getString('userId');
    });
    await _checkUserRoleFromApi();
  }

  Future<void> _checkUserRoleFromApi() async {
    try {
      const apiKey =
          '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2';

      // 1. Fetch roles from roleview
      final roleRes = await http
          .post(
            Uri.parse('${getBaseUrl()}/roleview'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': apiKey}),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, String> roleMap = {};
      final Set<String> adminManagerIds = {'1', '4', '13', '18'};

      if (roleRes.statusCode == 200) {
        final data = jsonDecode(roleRes.body);
        List<dynamic> roles = [];
        if (data is Map &&
            data['data'] is Map &&
            data['data']['roles'] is List) {
          roles = data['data']['roles'];
        } else if (data is Map && data['roles'] is List) {
          roles = data['roles'];
        }

        for (var r in roles) {
          if (r is Map) {
            final id = (r['id'] ?? r['role_id'])?.toString() ?? '';
            final name = (r['role_name'] ?? r['name'])?.toString() ?? '';
            if (id.isNotEmpty) {
              roleMap[id] = name;
              final lower = name.toLowerCase().trim();
              if (lower == 'admin' ||
                  lower == 'manager' ||
                  lower.contains('admin') ||
                  lower.contains('manager')) {
                adminManagerIds.add(id);
              }
            }
          }
        }
      }

      // 2. Fetch users from Registerview to accurately match current logged-in user
      final userRes = await http
          .post(
            Uri.parse('${getBaseUrl()}/Registerview'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': apiKey}),
          )
          .timeout(const Duration(seconds: 10));

      if (userRes.statusCode == 200) {
        final uData = jsonDecode(userRes.body);
        List<dynamic> users = [];
        if (uData is Map &&
            uData['data'] is Map &&
            uData['data']['users'] is List) {
          users = uData['data']['users'];
        } else if (uData is Map && uData['users'] is List) {
          users = uData['users'];
        }

        final currentName = (_userName ?? '').trim().toLowerCase();
        final currentUserId = (_userId ?? '').trim().toLowerCase();

        for (var u in users) {
          if (u is Map) {
            final uName = (u['user_name'] ?? u['username'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final uId = (u['user_id'] ?? '').toString().trim().toLowerCase();

            if ((currentName.isNotEmpty && uName == currentName) ||
                (currentUserId.isNotEmpty && uId == currentUserId)) {
              final userRoleId = (u['role_id'] ?? u['roleId'])?.toString();
              if (userRoleId != null && userRoleId.isNotEmpty) {
                final resolvedRoleName = roleMap[userRoleId] ?? _userRole;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('roleId', userRoleId);
                if (resolvedRoleName != null && resolvedRoleName.isNotEmpty) {
                  await prefs.setString('userRole', resolvedRoleName);
                }

                if (mounted) {
                  setState(() {
                    _roleId = userRoleId;
                    if (resolvedRoleName != null &&
                        resolvedRoleName.isNotEmpty) {
                      _userRole = resolvedRoleName;
                    }
                    _adminOrManagerRoleIds = adminManagerIds;
                    if (!_canAccessAuth && _selectedIndex == 1) {
                      _selectedIndex = 0;
                    }
                    if (!_canAccessAuth &&
                        _expandedSection == 'Authentication') {
                      _expandedSection = null;
                    }
                  });
                }
                return;
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _adminOrManagerRoleIds = adminManagerIds;
          if (_roleId != null && roleMap.containsKey(_roleId)) {
            _userRole = roleMap[_roleId];
          }
          if (!_canAccessAuth && _selectedIndex == 1) {
            _selectedIndex = 0;
          }
          if (!_canAccessAuth && _expandedSection == 'Authentication') {
            _expandedSection = null;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    _viewController.dispose();
    super.dispose();
  }

  void _selectIndex(int index) {
    if (_selectedIndex == index) return;

    setState(() {
      _selectedIndex = index;
      if (index != 6) {
        _scheduleEditData = null;
        _isScheduleExtend = false;
      }
    });
    _viewController.forward(from: 0.0);
  }

  void _toggleSection(String title) {
    setState(() {
      if (_expandedSection == title) {
        _expandedSection = null;
      } else {
        _expandedSection = title;
      }
    });
  }

  void _navigateToScheduleAllocate({
    Map<String, dynamic>? editData,
    bool isExtend = false,
  }) {
    setState(() {
      _scheduleEditData = editData;
      _isScheduleExtend = isExtend;
      _selectedIndex = 6;
      _expandedSection = 'Schedule';
    });
    _viewController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below 700 px wide the sidebar is hidden to avoid overflow.
        final showSidebar = constraints.maxWidth >= 700;
        return Scaffold(
          drawer: !showSidebar
              ? Drawer(
                  backgroundColor: const Color(0xFF0F172A),
                  child: SafeArea(child: _buildSidebar(theme, isDrawer: true)),
                )
              : null,
          backgroundColor: const Color(0xFFF8FAFC),
          // ClipRect at the Scaffold body level prevents ANY yellow/black overflow
          // stripes from leaking into view, no matter how small the window is.
          body: ClipRect(
            child: Row(
              children: [
                // Sidebar (conditionally shown)
                if (showSidebar)
                  SlideTransition(
                    position: _sidebarSlide,
                    child: FadeTransition(
                      opacity: _sidebarFade,
                      child: _buildSidebar(theme),
                    ),
                  ),

                // Main Content
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(theme, showSidebar: showSidebar),
                      Expanded(
                        child: FadeTransition(
                          opacity: _viewFade,
                          child: SlideTransition(
                            position: _viewSlide,
                            child: Container(
                              margin: EdgeInsets.fromLTRB(
                                0,
                                0,
                                showSidebar ? 24 : 12,
                                showSidebar ? 24 : 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _getSelectedView(),
                            ),
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
      },
    );
  }

  Widget _buildSidebar(ThemeData theme, {bool isDrawer = false}) {
    return Container(
      width: isDrawer ? double.infinity : 260,
      margin: EdgeInsets.all(isDrawer ? 0 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(isDrawer ? 0 : 24),
        boxShadow: isDrawer
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(4, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDrawer ? 0 : 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 24,
                      width: 24,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.display_settings_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "SRIHER",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (isDrawer) ...[
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSidebarItem(
                    Icons.space_dashboard_rounded,
                    'Dashboard',
                    0,
                    isDrawer: isDrawer,
                    iconColor: const Color(
                      0xFF3B82F6,
                    ), // Dashboard icon color (Blue)
                    isHeaderStyle: true,
                  ),
                  const SizedBox(height: 5),

                  if (_canAccessAuth) ...[
                    _CollapsibleSection(
                      title: 'Authentication',
                      icon: Icons.lock_person_rounded,
                      iconColor: const Color(0xFFFBBF24),
                      isExpanded: _expandedSection == 'Authentication',
                      onToggle: () => _toggleSection('Authentication'),
                      children: [
                        _buildSidebarItem(
                          Icons.person_add_rounded,
                          'Add User',
                          1,
                          isDrawer: isDrawer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                  ],

                  _CollapsibleSection(
                    title: 'Masters',
                    icon: Icons.dns_rounded,
                    iconColor: const Color(0xFF34D399),
                    isExpanded: _expandedSection == 'Masters',
                    onToggle: () => _toggleSection('Masters'),
                    children: [
                      _buildSidebarItem(
                        Icons.admin_panel_settings_rounded,
                        'Roles',
                        11,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.settings_cell_rounded,
                        'Device Master',
                        12,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.business_rounded,
                        'Department',
                        13,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.location_on_rounded,
                        'Location Master',
                        14,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.map_rounded,
                        'Mapping',
                        15,
                        isDrawer: isDrawer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  _CollapsibleSection(
                    title: 'File Master',
                    icon: Icons.folder_shared_rounded,
                    iconColor: const Color(0xFFF472B6),
                    isExpanded: _expandedSection == 'File Master',
                    onToggle: () => _toggleSection('File Master'),
                    children: [
                      _buildSidebarItem(
                        Icons.cloud_upload_rounded,
                        'File Upload',
                        2,
                        isDrawer: isDrawer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  _CollapsibleSection(
                    title: 'Template Master',
                    icon: Icons.dashboard_customize_rounded,
                    iconColor: const Color(0xFFA78BFA),
                    isExpanded: _expandedSection == 'Template Master',
                    onToggle: () => _toggleSection('Template Master'),
                    children: [
                      _buildSidebarItem(
                        Icons.add_to_photos_rounded,
                        'Create Template',
                        3,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.view_quilt_rounded,
                        'Default Templates',
                        4,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.dashboard_customize_outlined,
                        'Select Template',
                        5,
                        isDrawer: isDrawer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  _CollapsibleSection(
                    title: 'Schedule',
                    icon: Icons.calendar_month_rounded,
                    iconColor: const Color(0xFF22D3EE),
                    isExpanded: _expandedSection == 'Schedule',
                    onToggle: () => _toggleSection('Schedule'),
                    children: [
                      _buildSidebarItem(
                        Icons.event_available_rounded,
                        'Schedule Allocate',
                        6,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.precision_manufacturing_rounded,
                        'Assign Device',
                        7,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.view_headline_rounded,
                        'Schedule List',
                        8,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.date_range_rounded,
                        'Specific Ranges',
                        9,
                        isDrawer: isDrawer,
                      ),
                      _buildSidebarItem(
                        Icons.copy_all_rounded,
                        'Copy and Wipe Off',
                        10,
                        isDrawer: isDrawer,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF3B82F6),
                    child: Text(
                      _userName != null && _userName!.isNotEmpty
                          ? _userName![0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _userName ?? "Admin",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    onPressed: () => _handleLogout(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: iconColor),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String title,
    int index, {
    bool isDrawer = false,
    Color? iconColor,
    bool isHeaderStyle = false,
  }) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        _selectIndex(index);
        if (isDrawer && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Colors.white
                  : (iconColor ?? Colors.white.withOpacity(0.4)),
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: isHeaderStyle
                  ? TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    )
                  : TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, {bool showSidebar = true}) {
    return Container(
      height: 72,
      margin: EdgeInsets.fromLTRB(
        showSidebar ? 0 : 12,
        24,
        showSidebar ? 24 : 12,
        16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!showSidebar) ...[
            Builder(
              builder: (ctx) => InkWell(
                onTap: () => Scaffold.of(ctx).openDrawer(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.menu_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              _getPageTitle(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          _buildHeaderAction(Icons.logout_rounded, onTap: _handleLogout),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF64748B), size: 20),
      ),
    );
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return "Dashboard Overview";
      case 1:
        return "User Management";
      case 2:
        return "File Management";
      case 3:
        return "Create Template";
      case 4:
        return "Default Templates";
      case 5:
        return "Template Selection";
      case 6:
        return "Schedule Allocation";
      case 7:
        return "Device Assignment";
      case 8:
        return "Schedule Registry";
      case 9:
        return "Time Ranges";
      case 10:
        return "Copy and wipe off";
      case 11:
        return "Role Configuration";
      case 12:
        return "Hardware Devices";
      case 13:
        return "Department Directory";
      case 14:
        return "Location Directory";
      case 15:
        return "Asset Mapping";
      default:
        return "SRIHER Display";
    }
  }

  Future<void> _handleLogout() async {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 1024;
    final bool isDesktop = screenWidth >= 1024;

    final double dialogWidth = isDesktop
        ? 560.0
        : (isTablet ? 480.0 : (screenWidth * 0.92).clamp(300.0, 420.0));

    final confirm = await StylishDialog.show<bool>(
      context: context,
      title: "CONFIRM LOGOUT",
      titleStyle: TextStyle(
        fontSize: isDesktop ? 22 : (isTablet ? 20 : 18),
        fontWeight: FontWeight.w900,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
      subtitle: "Are you sure you want to end your session?",
      subtitleStyle: TextStyle(
        fontSize: isDesktop ? 14 : 12,
        color: Colors.white70,
      ),
      icon: Icons.logout_rounded,
      maxWidth: dialogWidth,
      builder: (context, setPopupState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Do you want to log out or stay signed in?",
              style: TextStyle(
                fontSize: isDesktop ? 17 : (isMobile ? 15 : 16),
                fontWeight: FontWeight.w800,
                color: const Color.fromARGB(255, 76, 78, 83),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            // Current Active Session Info Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF3B82F6,
                          ).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (_userName != null && _userName!.trim().isNotEmpty)
                          ? _userName!.trim()[0].toUpperCase()
                          : "U",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? "Current User",
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _userRole ?? "Administrator",
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          "Active",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Advisory Note

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: isDesktop ? 15 : (isMobile ? 13 : 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "Logout Now",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: isDesktop ? 15 : (isMobile ? 13 : 14),
                      ),
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Widget _getSelectedView() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardView();
      case 1:
        return _canAccessAuth ? const AddUserView() : const DashboardView();
      case 2:
        return const FileUploadView();
      case 3:
        return const CreateTemplateView();
      case 4:
        return const DefaultTemplateView();
      case 5:
        return const SelectTemplateView();
      case 6:
        return ScheduleAllocateView(
          editData: _scheduleEditData,
          isExtend: _isScheduleExtend,
          onBack: () => setState(() => _selectedIndex = 8),
        );
      case 7:
        return AssignDeviceView();
      case 8:
        return ScheduleListView(
          onEdit: (data) =>
              _navigateToScheduleAllocate(editData: data, isExtend: false),
          onExtend: (data) =>
              _navigateToScheduleAllocate(editData: data, isExtend: true),
        );
      case 9:
        return const SpecificRangesView();
      case 10:
        return const CopyWipeoffView();
      case 11:
        return const RoleView();
      case 12:
        return const DeviceMasterView();
      case 13:
        return const DepartmentView();
      case 14:
        return const LocationMasterView();
      case 15:
        return const MappingView();
      default:
        return const DashboardView();
    }
  }
}

class _CollapsibleSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 13, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white.withOpacity(0.5),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
