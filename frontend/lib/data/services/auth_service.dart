import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';

class AuthService {
  final Dio dio;
  final AppDatabase db;
  final String baseUrl;

  AuthService(this.dio, this.db, this.baseUrl);

  Future<void> login(String loginInfo, String password) async {
    try {
      final isEmail = loginInfo.contains('@');
      final response = await dio.post(
        '$baseUrl/auth/login',
        data: {
          if (isEmail) 'email': loginInfo else 'phone': loginInfo,
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['token'] != null) {
        await _saveAuthData(data['token'] as String, data['user'] as Map<String, dynamic>);
      } else {
        final errMsg = data['error'] ?? data['message'] ?? 'Login failed. Check your credentials.';
        throw Exception(errMsg);
      }
    } on DioException catch (e) {
      if (e.response?.data != null) {
        final errMsg = e.response!.data['error'] ?? e.response!.data['message'] ?? 'Login failed';
        throw Exception(errMsg);
      }
      throw Exception('Cannot connect to server. Check your internet connection.');
    }
  }

  Future<void> register(String name, String email, String phone, String password) async {
    try {
      final response = await dio.post(
        '$baseUrl/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data;

      // Accept both 200 and 201 success codes
      if (response.statusCode == 201 || response.statusCode == 200) {
        // Registration successful. Do not auto-login to force user back to login screen.
        return;
      } else {
        final errMsg = data['error'] ?? data['message'] ?? 'Registration failed. Please try again.';
        throw Exception(errMsg);
      }
    } on DioException catch (e) {
      if (e.response?.data != null) {
        final errMsg = e.response!.data['error'] ?? e.response!.data['message'] ?? 'Registration failed';
        throw Exception(errMsg);
      }
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Connection timed out. The server may be starting up, please try again.');
      }
      throw Exception('Cannot connect to server. Check your internet connection.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Unexpected error: $e');
    }
  }

  Future<void> _saveAuthData(String token, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);

    // Backend may return snake_case or camelCase — handle both
    final userId = (userData['id'] ?? userData['_id'] ?? '') as String;
    final userName = (userData['name'] ?? 'Unknown') as String;
    final userEmail = userData['email'] as String?;
    final userPhone = userData['phone'] as String?;
    final avatarUrl = (userData['avatarUrl'] ?? userData['avatar_url']) as String?;

    if (userId.isEmpty) {
      throw Exception('Server returned invalid user data.');
    }

    // Save to local DB with isMe = true
    await db.createUser(User(
      id: userId,
      name: userName,
      email: userEmail,
      phone: userPhone,
      avatarUrl: avatarUrl,
      isMe: true,
      isSynced: true,
      updatedAt: DateTime.now(),
    ));

    // Ensure all other users in local DB have isMe = false
    await (db.update(db.users)..where((u) => u.id.isNotValue(userId)))
        .write(const UsersCompanion(isMe: Value(false)));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await (db.update(db.users)).write(const UsersCompanion(isMe: Value(false)));
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
}
