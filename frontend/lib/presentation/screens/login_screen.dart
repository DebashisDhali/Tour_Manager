import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/data/providers/app_providers.dart';
import 'package:frontend/presentation/widgets/no_internet_sheet.dart';
import 'package:frontend/presentation/widgets/sync_handler.dart';
import 'tour_list_screen.dart';
import 'register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController(); 
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  List<Map<String, String>> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load a single last remembered account for default fill
    final savedLogin = prefs.getString('remembered_login');
    final savedPass = prefs.getString('remembered_password');
    final isRemembered = prefs.getBool('remember_me') ?? false;

    // Load multiple accounts list
    final accountsJson = prefs.getString('saved_accounts_list');
    if (accountsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(accountsJson);
        setState(() {
          _savedAccounts = decoded.map((e) => Map<String, String>.from(e)).toList();
        });
      } catch (e) {
        debugPrint("Error decoding accounts: $e");
      }
    }

    if (isRemembered && savedLogin != null) {
      setState(() {
        _loginController.text = savedLogin;
        _passwordController.text = savedPass ?? '';
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    // Proactive Connectivity Check
    final isOnline = await SyncHandler.isConnected();
    if (!isOnline) {
      if (mounted) {
        NoInternetSheet.show(context, onRetry: _login);
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = await ref.read(authServiceProvider).login(
            _loginController.text.trim(),
            _passwordController.text.trim(),
          );

      // Save credentials if Remember Me is checked
      final prefs = await SharedPreferences.getInstance();
      final loginInfo = _loginController.text.trim();
      final password = _passwordController.text.trim();

      if (_rememberMe) {
        await prefs.setString('remembered_login', loginInfo);
        await prefs.setString('remembered_password', password);
        await prefs.setBool('remember_me', true);

        // Update multiple accounts list
        final List<Map<String, String>> newList = List.from(_savedAccounts);
        // Remove if exists to re-add at front (or just update)
        newList.removeWhere((acc) => acc['login'] == loginInfo);
        newList.insert(0, {'login': loginInfo, 'password': password});
        
        // Keep only last 5 accounts
        if (newList.length > 5) newList.removeRange(5, newList.length);
        
        await prefs.setString('saved_accounts_list', jsonEncode(newList));
      } else {
        await prefs.remove('remembered_login');
        await prefs.remove('remembered_password');
        await prefs.setBool('remember_me', false);
      }

      // Start background sync
      ref.read(syncServiceProvider).startSync(user.id).catchError((e) => debugPrint("Auto Sync failed: $e"));
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TourListScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().toLowerCase();
        if (errorMsg.contains('internet') || errorMsg.contains('network') || errorMsg.contains('server communication')) {
           NoInternetSheet.show(context, onRetry: _login, message: e.toString().replaceAll("Exception: ", ""));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll("Exception: ", "")), 
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Very light slate/blue
      body: Stack(
        children: [
          // Subtle background decorative elements
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFEFF6FF).withOpacity(0.6), // Lightest blue
                    const Color(0xFFF8FAFC).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Elegant Logo/Header Area
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.12),
                              blurRadius: 25,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Icon(Icons.account_balance_wallet_rounded, 
                          size: 50, color: Colors.blue.shade600),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        "Welcome Back",
                        style: TextStyle(
                          fontSize: 34, 
                          fontWeight: FontWeight.w800, 
                          color: Colors.blueGrey.shade900,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Sign in to access your tour analytics",
                        style: TextStyle(
                          fontSize: 16, 
                          color: Colors.blueGrey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Saved Accounts Suggestions
                      if (_savedAccounts.isNotEmpty) ...[
                        SizedBox(
                          height: 48,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _savedAccounts.length,
                            itemBuilder: (context, index) {
                              final acc = _savedAccounts[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: CircleAvatar(
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(acc['login']![0].toUpperCase(), 
                                        style: TextStyle(color: Colors.blue.shade800, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  label: Text(acc['login']!, style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    setState(() {
                                      _loginController.text = acc['login']!;
                                      _passwordController.text = acc['password']!;
                                      _rememberMe = true;
                                    });
                                  },
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    side: BorderSide(color: Colors.blue.shade100),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 32),
                      ] else ...[
                        const SizedBox(height: 56),
                      ],
                      
                      // Login Fields
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildModernTextField(
                              controller: _loginController,
                              label: "Email or Phone",
                              hint: "Enter your identifier",
                              icon: Icons.alternate_email_rounded,
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 24),
                            _buildModernTextField(
                              controller: _passwordController,
                              label: "Password",
                              hint: "••••••••",
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                  color: Colors.blueGrey.shade400,
                                  size: 22,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              validator: (v) => v == null || v.isEmpty ? "Required" : null,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      activeColor: Colors.blue.shade600,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Remember Me",
                                    style: TextStyle(
                                      color: Colors.blueGrey.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {},
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.blue.shade600,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Text(
                                      "Forgot Password?",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            
                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade600,
                                  foregroundColor: Colors.white,
                                  elevation: 8,
                                  shadowColor: Colors.blue.withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: _isLoading 
                                  ? const SizedBox(
                                      width: 24, 
                                      height: 24, 
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "Login Now",
                                      style: TextStyle(
                                        fontSize: 17, 
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 15),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (_) => const RegisterScreen())
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                            ),
                            child: const Text(
                              "Sign Up",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.blueGrey.shade800,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(color: Colors.blueGrey.shade900, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.blueGrey.shade400, size: 22),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blueGrey.shade200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.blue.shade500, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.red.shade500, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          ),
        ),
      ],
    );
  }
}
