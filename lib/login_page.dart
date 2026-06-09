import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'widgets/animated_background.dart';
import 'widgets/glass_card.dart';
import 'api_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();

  final _userIdFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _buttonFocusNode = FocusNode();

  late AnimationController _entryController;
  late AnimationController _buttonController;

  // Staggered Animations
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _formFade;
  late Animation<Offset> _formSlide;
  late Animation<double> _buttonFade;
  late Animation<double> _buttonScale;

  bool _isObscure = true;
  bool _isLoggingIn = false;
  String? _errorMessage;

  /// Track which of our 3 logical items is "active" for D-pad:
  /// 0 = userId, 1 = password, 2 = signIn button
  int _focusIndex = 0;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );

    // Sequence 1: Logo
    _logoFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(begin: const Offset(0, -0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
          ),
        );

    // Sequence 2: Title
    _titleFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
          ),
        );

    // Sequence 3: Form Fields
    _formFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
    );
    _formSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
          ),
        );

    // Sequence 4: Button
    _buttonFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    );
    _buttonScale = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOutBack),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _buttonController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _userIdFocusNode.dispose();
    _passwordFocusNode.dispose();
    _buttonFocusNode.dispose();
    super.dispose();
  }

  // ── D-Pad handler ──────────────────────────────────────────────────
  void _moveFocus(int newIndex) {
    setState(() => _focusIndex = newIndex.clamp(0, 2));
    switch (_focusIndex) {
      case 0:
        _userIdFocusNode.requestFocus();
        break;
      case 1:
        _passwordFocusNode.requestFocus();
        break;
      case 2:
        // Unfocus text fields (dismiss keyboard) then focus button
        FocusScope.of(context).unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _buttonFocusNode.requestFocus();
        });
        break;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveFocus(_focusIndex + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(_focusIndex - 1);
      return KeyEventResult.handled;
    }
    // DPAD_CENTER / Enter / Select on the button → trigger login
    if (_focusIndex == 2 &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
      if (!_isLoggingIn) _handleLogin();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }



  // ── Login logic ────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    await _buttonController.reverse();
    await _buttonController.forward();

    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('${getBaseUrl()}/loginvalidationview'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'api_key':
                  '933cdb13cb54e31e694f82bf7f75f0144a9495036db0243b85dd855be53c06f2',
              'user_id': _userIdController.text.trim(),
              'password': _passwordController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      print(getBaseUrl());
      print(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool success =
            data is Map &&
            (data['status']?.toString().toLowerCase() == 'success' ||
                data['Success']?.toString().toLowerCase() == 'success');

        if (success) {
          final userInfo = data['data'];
          String name = "User";
          String role = "Admin";

          if (userInfo is Map) {
            name =
                userInfo['user_name']?.toString() ??
                userInfo['username']?.toString() ??
                userInfo['name']?.toString() ??
                userInfo['user_id']?.toString() ??
                _userIdController.text.trim();
            role = userInfo['role_name'] ?? userInfo['role'] ?? "Admin";
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userName', name);
          await prefs.setString('userRole', role);
          await prefs.setString('loginTime', DateTime.now().toString());

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const HomeScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        } else {
          setState(() {
            _errorMessage =
                data['message'] ?? "Invalid credentials. Please try again.";
          });
        }
      } else {
        setState(() {
          if (response.statusCode == 0) {
            _errorMessage =
                "Network error or CORS policy blocking the request. Please check your connection.";
          } else {
            _errorMessage = "Server error: ${response.statusCode}";
          }
        });
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('Failed to fetch') || msg.contains('XMLHttpRequest')) {
        _showError(
          'Connection blocked by CORS or Network issue. Ensure you are using the HTML renderer.',
        );
      } else {
        _showError('Connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(24),
      ),
    );
  }

  // ── Responsive helpers ─────────────────────────────────────────────
  /// Returns a scale factor relative to a 1080p baseline (height 1080).
  /// Clamped so it never shrinks too much or grows too large.
  double _scale(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return (h / 1080).clamp(0.55, 1.3);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final scale = _scale(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          children: [
            // Deep Base Layer
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                    Color(0xFF020617),
                  ],
                ),
              ),
            ),

            // Enhanced Interactive Background
            const AnimatedBackground(),

            // Ambient Glows
            Positioned(
              top: screenHeight * 0.2,
              left: -100,
              child: _buildAmbientGlow(
                400,
                const Color(0xFF3B82F6).withOpacity(0.08),
              ),
            ),
            Positioned(
              bottom: 100,
              right: -100,
              child: _buildAmbientGlow(
                500,
                const Color(0xFF10B981).withOpacity(0.05),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 16 * scale,
                  vertical: 12 * scale,
                ),
                child: _buildLoginCard(scale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmbientGlow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  Widget _buildLoginCard(double scale) {
    final cardMaxWidth = (380 * scale).clamp(280.0, 440.0);
    final cardPadding = (28 * scale).clamp(16.0, 40.0);
    final logoPad = (14 * scale).clamp(8.0, 18.0);
    final logoHeight = (48 * scale).clamp(32.0, 64.0);
    final logoFallbackSize = (36 * scale).clamp(24.0, 44.0);
    final titleFontSize = (20 * scale).clamp(14.0, 26.0);
    final subtitleFontSize = (12 * scale).clamp(10.0, 15.0);
    final sectionGap = (20 * scale).clamp(10.0, 36.0);
    final fieldGap = (12 * scale).clamp(6.0, 20.0);
    final buttonGap = (20 * scale).clamp(10.0, 36.0);

    return GlassCard(
      constraints: BoxConstraints(maxWidth: cardMaxWidth),
      padding: EdgeInsets.all(cardPadding),
      opacity: 0.04,
      blur: 25,
      border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo Staggered
            FadeTransition(
              opacity: _logoFade,
              child: SlideTransition(
                position: _logoSlide,
                child: Hero(
                  tag: 'app_logo',
                  child: Container(
                    padding: EdgeInsets.all(logoPad),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: logoHeight,
                      errorBuilder: (c, e, s) => Icon(
                        Icons.display_settings_rounded,
                        size: logoFallbackSize,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: sectionGap),

            // Title Staggered
            FadeTransition(
              opacity: _titleFade,
              child: SlideTransition(
                position: _titleSlide,
                child: Column(
                  children: [
                    Text(
                      'SRIHER DISPLAY',
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      'Management System Portal',
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: Colors.white.withOpacity(0.5),
                        letterSpacing: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: sectionGap),

            // Form Fields Staggered
            FadeTransition(
              opacity: _formFade,
              child: SlideTransition(
                position: _formSlide,
                child: Column(
                  children: [
                    if (_errorMessage != null) ...[
                      _buildErrorDisplay(scale),
                      SizedBox(height: fieldGap),
                    ],
                    _buildTextField(
                      scale: scale,
                      controller: _userIdController,
                      label: 'User ID',
                      hint: 'Enter your credentials',
                      icon: Icons.person_outline_rounded,
                      focusNode: _userIdFocusNode,
                      textInputAction: TextInputAction.next,
                      autofocus: true,
                      onSubmitted: (_) => _moveFocus(1),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'User ID is required'
                          : null,
                    ),
                    SizedBox(height: fieldGap),
                    _buildTextField(
                      scale: scale,
                      controller: _passwordController,
                      label: 'Password',
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      focusNode: _passwordFocusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _moveFocus(2),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Password is required'
                          : null,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: buttonGap),

            // Button Staggered
            FadeTransition(
              opacity: _buttonFade,
              child: ScaleTransition(
                scale: _buttonScale,
                child: _buildSignInButton(scale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDisplay(double scale) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: const Color(0xFFF87171),
            size: (18 * scale).clamp(14.0, 22.0),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: const Color(0xFFF87171),
                fontSize: (12 * scale).clamp(10.0, 15.0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInButton(double scale) {
    final btnHeight = (48 * scale).clamp(36.0, 58.0);
    final btnFontSize = (14 * scale).clamp(11.0, 18.0);
    final btnIconSize = (18 * scale).clamp(14.0, 22.0);
    final btnRadius = (14 * scale).clamp(10.0, 18.0);

    return ScaleTransition(
      scale: _buttonController,
      child: SizedBox(
        width: double.infinity,
        height: btnHeight,
        child: AnimatedBuilder(
          animation: _buttonFocusNode,
          builder: (context, child) {
            final isFocused = _buttonFocusNode.hasFocus;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(btnRadius),
                gradient: LinearGradient(
                  colors: isFocused
                      ? [const Color(0xFF60A5FA), const Color(0xFF2563EB)]
                      : [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: isFocused
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6)
                        .withOpacity(isFocused ? 0.8 : 0.4),
                    blurRadius: isFocused ? 25 : 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                focusNode: _buttonFocusNode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(btnRadius - 2),
                  ),
                ),
                onPressed: _isLoggingIn ? null : _handleLogin,
                child: _isLoggingIn
                    ? SizedBox(
                        width: 22 * scale,
                        height: 22 * scale,
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'SIGN IN',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: btnFontSize,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(width: 10 * scale),
                          Icon(Icons.arrow_forward_rounded, size: btnIconSize),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required double scale,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
    bool autofocus = false,
  }) {
    final labelSize = (10 * scale).clamp(8.0, 13.0);
    final inputSize = (14 * scale).clamp(11.0, 17.0);
    final hintSize = (13 * scale).clamp(10.0, 16.0);
    final iconSize = (18 * scale).clamp(14.0, 22.0);
    final vertPad = (14 * scale).clamp(8.0, 20.0);
    final horizPad = (14 * scale).clamp(10.0, 20.0);
    final borderRadius = (14 * scale).clamp(10.0, 18.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 6, bottom: 4 * scale),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: labelSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
        TextFormField(
          autofocus: autofocus,
          validator: validator,
          controller: controller,
          focusNode: focusNode,
          obscureText: isPassword && _isObscure,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          style: TextStyle(
            color: Colors.white,
            fontSize: inputSize,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: hintSize,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.only(right: 8),
              child:
                  Icon(icon, color: Colors.white.withOpacity(0.4), size: iconSize),
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _isObscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white.withOpacity(0.3),
                      size: iconSize,
                    ),
                    onPressed: () => setState(() => _isObscure = !_isObscure),
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide:
                  const BorderSide(color: Color(0xFF3B82F6), width: 3),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: horizPad,
              vertical: vertPad,
            ),
          ),
        ),
      ],
    );
  }
}
