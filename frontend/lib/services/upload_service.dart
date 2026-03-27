import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/constants.dart';
import 'auth_service.dart';

class UploadService {
  static String get baseUrl => AppConfig.baseUrl;

  static Future<Map<String, dynamic>> uploadAvatar(Object source) =>
      _uploadImage(source, 'avatar', '/uploads/avatar');

  static Future<Map<String, dynamic>> uploadImage(Object source) =>
      _uploadImage(source, 'image', '/uploads/image');

  static Future<Map<String, dynamic>> uploadAudio(Object source) =>
      _uploadBinary(
        source,
        'audio',
        '/uploads/audio',
        mediaType: 'audio',
        mimeMap: const {
          'mp3': 'mpeg',
          'm4a': 'mp4',
          'aac': 'aac',
          'wav': 'wav',
          'ogg': 'ogg',
          'webm': 'webm',
        },
      );

  static Future<Map<String, dynamic>> _uploadImage(
    Object source,
    String field,
    String endpoint,
  ) =>
      _uploadBinary(
        source,
        field,
        endpoint,
        mediaType: 'image',
        mimeMap: const {
          'jpg': 'jpeg',
          'jpeg': 'jpeg',
          'png': 'png',
          'gif': 'gif',
          'webp': 'webp',
        },
      );

  static Future<Map<String, dynamic>> _uploadBinary(
    Object source,
    String field,
    String endpoint, {
    required String mediaType,
    required Map<String, String> mimeMap,
    bool hasRetriedAuth = false,
  }) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Please sign in again.');
    }

    final prepared = await _prepareUpload(
      source,
      mediaType: mediaType,
      mimeMap: mimeMap,
    );

    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes(
          field,
          prepared.bytes,
          filename: prepared.filename,
          contentType: MediaType(mediaType, prepared.mimeSubtype),
        ),
      );

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = _decodeResponseBody(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw Exception(
            'Upload succeeded but returned an unexpected response.');
      }

      if (response.statusCode == 401 && !hasRetriedAuth) {
        final refreshed = await AuthService.refreshSession();
        if (refreshed) {
          return _uploadBinary(
            source,
            field,
            endpoint,
            mediaType: mediaType,
            mimeMap: mimeMap,
            hasRetriedAuth: true,
          );
        }
        await AuthService.clearSession();
        throw Exception('Please sign in again.');
      }

      throw Exception(_extractErrorMessage(response));
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('Upload failed. Please try again.');
    }
  }

  static Future<_PreparedUpload> _prepareUpload(
    Object source, {
    required String mediaType,
    required Map<String, String> mimeMap,
  }) async {
    final file = _resolveSource(source);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('The selected file is empty.');
    }

    final filename = _resolveFilename(file, fallbackMediaType: mediaType);
    final extension = _extractExtension(filename);
    final mimeSubtype = mimeMap[extension] ?? mimeMap.values.first;

    return _PreparedUpload(
      bytes: bytes,
      filename: filename,
      mimeSubtype: mimeSubtype,
    );
  }

  static XFile _resolveSource(Object source) {
    if (source is XFile) {
      return source;
    }
    if (source is String && source.trim().isNotEmpty) {
      return XFile(source);
    }
    throw Exception('Unsupported upload source.');
  }

  static String _resolveFilename(
    XFile file, {
    required String fallbackMediaType,
  }) {
    final name = file.name.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final path = file.path.trim();
    if (path.isNotEmpty) {
      final normalized = path.replaceAll('\\', '/');
      final segments = normalized.split('/');
      final candidate = segments.isNotEmpty ? segments.last.trim() : '';
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return 'upload.$fallbackMediaType';
  }

  static String _extractExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }

  static dynamic _decodeResponseBody(String body) {
    if (body.isEmpty) {
      return const <String, dynamic>{};
    }
    return json.decode(body);
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final body = _decodeResponseBody(response.body);
      if (body is Map) {
        final error = body['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String && error.trim().isNotEmpty) {
          return error;
        }
        if (body['message'] is String) {
          return body['message'] as String;
        }
      }
    } catch (_) {}

    return 'Upload failed with status ${response.statusCode}.';
  }
}

class _PreparedUpload {
  final Uint8List bytes;
  final String filename;
  final String mimeSubtype;

  const _PreparedUpload({
    required this.bytes,
    required this.filename,
    required this.mimeSubtype,
  });
}
