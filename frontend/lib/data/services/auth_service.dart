import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  final Dio dio;
  final AppDatabase db;
  final String baseUrl;

  AuthService(this.dio, this.db, this.baseUrl);

  Future<void> login(String loginInfo, String password) async {
    try {
      final isEmail = loginInfo.contains('@');
      final response = await dio.post('$baseUrl/auth/login', data: {
        if (isEmail) 'email': loginInfo else 'phone': loginInfo,
        'password': password,
      });

      if (response.statusCode == 200) {
        final token = response.data['token'];
        final userData = response.data['user'];

        await _saveAuthData(token, userData);
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Login failed');
    }
  }

  Future<void> register(String name, String email, String phone, String password) async {
    try {
      final response = await dio.post('$baseUrl/auth/register', data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      });

      if (response.statusCode == 201) {
        final token = response.data['token'];
        final userData = response.data['user'];

        await _saveAuthData(token, userData);
      }
    } on DioException catch (e) {
      throw Exception(e.response?.data['error'] ?? 'Registration failed');
    }
  }

  Future<void> _saveAuthData(String token, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);

    // Update local database user as "me"
    await db.createUser(User(
      id: userData['id'],
      name: userData['name'],
      email: userData['email'],
      phone: userData['phone'],
      isMe: true,
      isSynced: true,
      updatedAt: DateTime.now(),
    ));

    // Ensure all other users in local DB have isMe = false
    await (db.update(db.users)..where((u) => u.id.isNotValue(userData['id'])))
        .write(UsersCompanion(isMe: Value<bool>(false)));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');

    // Update local DB all as not me
    await (db.update(db.users)).write(UsersCompanion(isMe: Value<bool>(false)));
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
}
