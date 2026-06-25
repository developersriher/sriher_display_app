import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Map<String, dynamic>? _scheduleEditData;
  bool _isScheduleExtend = false;

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
    setState(() {
      _userName = prefs.getString('userName');
      _userRole = prefs.getString('userRole');
    });
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

  void _navigateToScheduleAllocate({
    Map<String, dynamic>? editData,
    bool isExtend = false,
  }) {
    setState(() {
      _scheduleEditData = editData;
      _isScheduleExtend = isExtend;
      _selectedIndex = 6;
    });
    _viewController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // ClipRect at the Scaffold body level prevents ANY yellow/black overflow
      // stripes from leaking into view, no matter how small the window is.
      body: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below 700 px wide the sidebar is hidden to avoid overflow.
            final showSidebar = constraints.maxWidth >= 700;
            return Row(
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
                                0, 0,
                                showSidebar ? 24 : 12,
                                showSidebar ? 24 : 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                    color: Colors.white, width: 2),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    return Container(
      width: 260,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(4, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Sidebar Logo
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
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSidebarItem(Icons.dashboard_rounded, 'Dashboard', 0),
                  const SizedBox(height: 16),
                  _buildSectionHeader('SYSTEM MASTERS'),
                  _buildSidebarItem(
                    Icons.admin_panel_settings_rounded,
                    'Roles',
                    11,
                  ),
                  _buildSidebarItem(Icons.settings_cell_rounded, 'Devices', 12),
                  _buildSidebarItem(Icons.business_rounded, 'Departments', 13),
                  _buildSidebarItem(Icons.location_on_rounded, 'Locations', 14),
                  _buildSidebarItem(Icons.map_rounded, 'Mapping', 15),
                  const SizedBox(height: 16),
                  _buildSectionHeader('MANAGEMENT'),
                  _buildSidebarItem(Icons.person_add_rounded, 'Add User', 1),
                  _buildSidebarItem(
                    Icons.folder_shared_rounded,
                    'File Upload',
                    2,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('TEMPLATES'),
                  _buildSidebarItem(Icons.add_box_rounded, 'Create Template', 3),
                  _buildSidebarItem(
                    Icons.auto_awesome_mosaic_rounded,
                    'Default Template',
                    4,
                  ),
                  _buildSidebarItem(
                    Icons.library_add_check_rounded,
                    'Select Template',
                    5,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('SCHEDULING'),
                  _buildSidebarItem(Icons.calendar_month_rounded, 'Allocate', 6),
                  _buildSidebarItem(Icons.devices_rounded, 'Assign Device', 7),
                  _buildSidebarItem(Icons.list_alt_rounded, 'Schedule List', 8),
                  _buildSidebarItem(
                    Icons.date_range_rounded,
                    'Specific Ranges',
                    9,
                  ),
                  _buildSidebarItem(
                    Icons.cleaning_services_rounded,
                    'Maintenance',
                    10,
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // User Info / Logout
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF3B82F6),
                    radius: 18,
                    child: Text(
                      _userName?.isNotEmpty == true
                          ? _userName![0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _userName ?? "User",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _userRole ?? "Administrator",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _selectIndex(index),
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
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.4),
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
        showSidebar ? 0 : 12, 24, showSidebar ? 24 : 12, 16),
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
        return "Copy & Cleanup";
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
    final confirm = await StylishDialog.show<bool>(
      context: context,
      title: "CONFIRM LOGOUT",
      subtitle: "Are you sure you want to end your session?",
      icon: Icons.logout_rounded,
      maxWidth: 430,
      builder: (context, setPopupState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "You will need to sign in again to access the dashboard and manage display settings.",
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.5,
              ),
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
                  flex: 1,
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
                      "Logout Now",
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
        return const AddUserView();
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
