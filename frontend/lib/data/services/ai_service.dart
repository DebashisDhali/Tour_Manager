import 'package:dio/dio.dart';

class AiService {
  final Dio dio;
  final String baseUrl;

  AiService(this.dio, this.baseUrl);

  Future<String> getTourInsights(String tourId, String message) async {
    try {
      final response = await dio.post(
        '$baseUrl/ai/$tourId/insights',
        data: {'message': message},
      );

      if (response.statusCode == 200) {
        if (response.data is Map) {
          return response.data['reply'] ?? "No response generated.";
        }
        return response.data.toString();
      } else {
        throw Exception('AI generation failed with status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['error'] != null) {
        throw Exception(e.response?.data['error']);
      }
      throw Exception('Failed to connect to AI server: ${e.message}');
    } catch (e) {
      throw Exception('Failed to get AI insights: $e');
    }
  }
}
