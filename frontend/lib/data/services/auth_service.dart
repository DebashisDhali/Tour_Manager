import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';

class AuthService {
  final Dio dio;
  final AppDatabase db;
  final String baseUrl;

  AuthService(this.dio, this.db, this.baseUrl);

  Future<User> login(String loginInfo, String password) async {
    try {
      final isEmail = loginInfo.contains('@');
      final response = await dio.post(
        '$baseUrl/auth/login',
        data: {
          if (isEmail) 'email': loginInfo else 'phone': loginInfo,
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status != null && (status < 500 || status == 401 || status == 404),
          headers: {'Content-Type': 'application/json'},
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['token'] != null) {
        return await _saveAuthData(data['token'] as String, data['user'] as Map<String, dynamic>);
      } else {
        final errMsg = data['error'] ?? data['message'] ?? 'Login failed. Check your credentials.';
        throw Exception(errMsg);
      }
    } on DioException catch (e) {
      _handleDioError(e, 'Login');
      rethrow; // Should not reach here due to _handleDioError throwing
    } catch (e) {
       throw Exception('Unexpected error: $e');
    }
  }

  Future<void> register(String name, String email, String phone, String password) async {
    try {
      final response = await dio.post(
        '$baseUrl/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'phone': phone.trim(),
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          headers: {'Content-Type': 'application/json'},
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data;

      if (response.statusCode == 201 || response.statusCode == 200) {
        return;
      } else {
        final errMsg = data['error'] ?? data['message'] ?? 'Registration failed.';
        throw Exception(errMsg);
      }
    } on DioException catch (e) {
      _handleDioError(e, 'Registration');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Unexpected error: $e');
    }
  }

  void _handleDioError(DioException e, String context) {
    if (e.response?.data != null && e.response?.data is Map) {
      final errMsg = e.response!.data['error'] ?? e.response!.data['message'] ?? '$context failed';
      throw Exception(errMsg);
    }
    
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      throw Exception('Server is taking too long to respond. It might be waking up, please try again in a few seconds.');
    }
    
    if (e.type == DioExceptionType.connectionError) {
      throw Exception('Cannot reach the server. Please check if your internet or DNS is working correctly.');
    }

    if (e.error != null && e.error.toString().contains('SocketException')) {
       throw Exception('Network unreachable. Please check your data connection or Wi-Fi.');
    }

    throw Exception('Server communication error. Please try again later.');
  }

  Future<User> _saveAuthData(String token, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);

    // Robust ID handling (convert UUID or Int to String)
    final userId = (userData['id'] ?? userData['_id'] ?? '').toString();
    final userName = (userData['name'] ?? 'Unknown') as String;
    final userEmail = userData['email'] as String?;
    final userPhone = userData['phone'] as String?;
    final avatarUrl = (userData['avatarUrl'] ?? userData['avatar_url']) as String?;

    if (userId.isEmpty) {
      throw Exception('Server returned invalid user data.');
    }

    final newUser = User(
      id: userId,
      name: userName,
      email: userEmail,
      phone: userPhone,
      avatarUrl: avatarUrl,
      isMe: true,
      isSynced: true,
      isDeleted: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save to local DB with isMe = true
    await db.createUser(newUser);

    // Ensure all other users in local DB have isMe = false
    await (db.update(db.users)..where((u) => u.id.isNotValue(userId)))
        .write(const UsersCompanion(isMe: Value(false)));
        
    return newUser;
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
