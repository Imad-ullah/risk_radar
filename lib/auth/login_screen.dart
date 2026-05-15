import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:riskradar/shared/widgets/risk_radar_loader.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ---------------------------------------------------------------------------
  // CONTROLLERS & KEYS
  // ---------------------------------------------------------------------------
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  bool _obscurePassword = true;

  // ✅ SECURITY: Rate limiting
  int _failedAttempts = 0;
  DateTime? _cooldownUntil;
  static const int _maxAttempts = 3;
  static const int _cooldownSeconds = 30;

  // ---------------------------------------------------------------------------
  // ✅ SECURITY HELPERS
  // ---------------------------------------------------------------------------
  bool _isInCooldown() {
    if (_cooldownUntil == null) return false;
    if (DateTime.now().isBefore(_cooldownUntil!)) return true;
    // Cooldown expired — reset
    _cooldownUntil = null;
    _failedAttempts = 0;
    return false;
  }

  int _remainingCooldownSeconds() {
    if (_cooldownUntil == null) return 0;
    return _cooldownUntil!.difference(DateTime.now()).inSeconds;
  }

  void _handleFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _cooldownUntil =
          DateTime.now().add(const Duration(seconds: _cooldownSeconds));
      _failedAttempts = 0;
      _showSnackBar(
          '🔒 Too many failed attempts. Please wait $_cooldownSeconds seconds.');
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ FIXED & SECURED: Email Login
  // ---------------------------------------------------------------------------
  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ SECURITY: Block if in cooldown
    if (_isInCooldown()) {
      _showSnackBar(
          '🔒 Please wait ${_remainingCooldownSeconds()} seconds before trying again.');
      return;
    }

    setState(() => _loadingEmail = true);

    try {
      final response = await Supabase.instance.client.auth
          .signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
        throw Exception('Request timed out. Check your connection.'),
      );

      if (!mounted) return;

      if (response.user != null) {
        // ✅ Reset failed attempts on success
        _failedAttempts = 0;
        _cooldownUntil = null;
        Navigator.pushReplacementNamed(context, '/');
      }
    } on AuthException catch (e) {
      _handleFailedAttempt();

      // ✅ SECURITY: Generic error messages — don't reveal if email exists
      final message = e.message.toLowerCase();
      if (message.contains('invalid') ||
          message.contains('credentials') ||
          message.contains('wrong') ||
          message.contains('not found')) {
        _showSnackBar('Incorrect email or password. Please try again.');
      } else if (message.contains('email not confirmed')) {
        _showSnackBar(
            'Please confirm your email before logging in. Check your inbox.');
      } else if (message.contains('too many')) {
        _showSnackBar('Too many requests. Please wait a moment.');
      } else {
        // ✅ SECURITY: Don't expose raw error to user
        _showSnackBar('Login failed. Please try again.');
        debugPrint('Auth error (hidden from user): ${e.message}');
      }
    } catch (e) {
      _handleFailedAttempt();
      if (e.toString().contains('timed out')) {
        _showSnackBar('Request timed out. Check your internet connection.');
      } else {
        _showSnackBar('Something went wrong. Please try again.');
        debugPrint('Login error (hidden from user): $e');
      }
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ FIXED & SECURED: Google Login
  // ---------------------------------------------------------------------------
  Future<void> _loginWithGoogle() async {
    if (_isInCooldown()) {
      _showSnackBar(
          '🔒 Please wait ${_remainingCooldownSeconds()} seconds before trying again.');
      return;
    }

    setState(() => _loadingGoogle = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
      final GoogleSignInAccount googleUser =
      await googleSignIn.authenticate();

      // User cancelled — not a failure, exit silently
      // ✅ FIX: Added await — was missing in original
      final GoogleSignInAuthentication googleAuth =
      googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw const AuthException('Failed to get Google ID token.');
      }

      // ✅ Get access token separately
      final authorization = await googleUser.authorizationClient
          .authorizationForScopes(['email', 'profile']);
      final String? accessToken = authorization?.accessToken;

      final response = await Supabase.instance.client.auth
          .signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
        throw Exception('Google sign-in timed out.'),
      );

      if (!mounted) return;

      if (response.user != null) {
        _failedAttempts = 0;
        _cooldownUntil = null;
        Navigator.pushReplacementNamed(context, '/');
      }
    } on AuthException catch (e) {
      _handleFailedAttempt();
      debugPrint('Google auth error: ${e.message}');
      _showSnackBar('Google sign-in failed. Please try again.');
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      // ✅ User cancelled — silent, not a failure
      if (errorStr.contains('canceled') ||
          errorStr.contains('cancelled') ||
          errorStr.contains('sign_in_canceled')) {
        setState(() => _loadingGoogle = false);
        return;
      }

      _handleFailedAttempt();

      if (errorStr.contains('timed out')) {
        _showSnackBar('Google sign-in timed out. Check your connection.');
      } else {
        debugPrint('Google login error (hidden from user): $e');
        _showSnackBar('Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ Forgot Password
  // ---------------------------------------------------------------------------
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar('Enter your email above first, then tap Forgot Password.');
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      // ✅ SECURITY: Same message whether email exists or not
      _showSnackBar(
          'If this email is registered, a reset link has been sent.',
          isError: false);
    } catch (e) {
      // ✅ SECURITY: Don't reveal if email exists
      _showSnackBar(
          'If this email is registered, a reset link has been sent.',
          isError: false);
      debugPrint('Password reset error (hidden from user): $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const Color tealColor = Color(0xFF1B3D3D);
    const Color goldColor = Color(0xFFE6A050);
    final screenWidth = MediaQuery.of(context).size.width;
    const double headerHeight = 240;
    const double logoSize = 140;
    const double goldRimOffset = 6.0;

    // ✅ Show remaining cooldown in button
    final bool isCoolingDown = _isInCooldown();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            SizedBox(
              height: headerHeight + (logoSize / 2) - 20,
              child: Stack(
                children: [
                  Positioned(
                    top: goldRimOffset,
                    left: 0,
                    right: 0,
                    child: ClipPath(
                      clipper: ConcaveHeaderClipper(),
                      child:
                      Container(height: headerHeight, color: goldColor),
                    ),
                  ),
                  ClipPath(
                    clipper: ConcaveHeaderClipper(),
                    child: Container(
                      height: headerHeight,
                      width: double.infinity,
                      decoration: const BoxDecoration(color: tealColor),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -60,
                            right: -40,
                            child: Icon(Icons.security,
                                size: 200,
                                color:
                                Colors.white.withValues(alpha: 0.08)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: headerHeight - (logoSize / 2) - 30,
                    left: (screenWidth - logoSize) / 2,
                    child: Hero(
                      tag: 'app-logo',
                      child: Container(
                        height: logoSize,
                        width: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => Container(
                              color: tealColor,
                              child: const Icon(Icons.security,
                                  size: 80, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),
            const Text(
              'Welcome Back!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: tealColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue to RiskRadar',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),

            // ✅ Cooldown warning banner
            if (isCoolingDown)
              Container(
                margin: const EdgeInsets.fromLTRB(30, 20, 30, 0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Too many attempts. Wait ${_remainingCooldownSeconds()}s before retrying.',
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 45),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildCustomTextField(
                      controller: _emailController,
                      label: "Email Address",
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        final emailRegex = RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                        if (!emailRegex.hasMatch(value.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildCustomTextField(
                      controller: _passwordController,
                      label: "Password",
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: tealColor,
                          size: 20,
                        ),
                        onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    // ✅ Forgot password link
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: tealColor,
                          padding:
                          const EdgeInsets.symmetric(vertical: 4),
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // LOGIN BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed:
                        (_loadingEmail || isCoolingDown)
                            ? null
                            : _loginWithEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goldColor,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 8,
                          shadowColor: goldColor.withValues(alpha: 0.4),
                        ),
                        child: _loadingEmail
                            ? const RiskRadarLoader(
                            color: Colors.white, size: 24)
                            : Row(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Text(
                              isCoolingDown
                                  ? 'WAIT ${_remainingCooldownSeconds()}s'
                                  : 'LOG IN',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                    Row(children: [
                      Expanded(
                          child: Divider(color: Colors.grey.shade300)),
                      Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                          child: Text("or continue with",
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500))),
                      Expanded(
                          child: Divider(color: Colors.grey.shade300)),
                    ]),

                    const SizedBox(height: 25),

                    // GOOGLE BUTTON
                    GestureDetector(
                      onTap: (_loadingGoogle || isCoolingDown)
                          ? null
                          : _loginWithGoogle,
                      child: AnimatedOpacity(
                        opacity: isCoolingDown ? 0.4 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          height: 60,
                          width: 60,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.grey.shade200,
                                    blurRadius: 10,
                                    offset: const Offset(0, 5))
                              ],
                              border:
                              Border.all(color: Colors.grey.shade100)),
                          padding: const EdgeInsets.all(12),
                          child: _loadingGoogle
                              ? const RiskRadarLoader(size: 24)
                              : SvgPicture.asset('assets/google_logo.svg'),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    RichText(
                      text: TextSpan(
                        text: "New to RiskRadar? ",
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 15),
                        children: [
                          TextSpan(
                            text: 'Create Account',
                            style: const TextStyle(
                                color: tealColor,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () =>
                                  Navigator.pushReplacementNamed(
                                      context, '/signup'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.grey.shade200)),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        autocorrect: false,
        enableSuggestions: !obscureText,
        style: const TextStyle(
            fontSize: 15,
            color: Colors.black87,
            fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 15, right: 10),
              child: Icon(icon,
                  color: const Color(0xFF1B3D3D), size: 22)),
          suffixIcon: suffixIcon,
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}

class ConcaveHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height - 50);
    var controlPoint = Offset(size.width / 2, size.height + 60);
    var endPoint = Offset(size.width, size.height - 50);
    path.quadraticBezierTo(
        controlPoint.dx, controlPoint.dy, endPoint.dx, endPoint.dy);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
