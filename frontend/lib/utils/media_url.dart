import '../services/api_service.dart';

String? resolveMediaUrl(String? value) {
  if (value == null) return null;

  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') {
    return null;
  }

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

  final apiBase = ApiService.baseUrl;
  final backendBase = apiBase.endsWith('/api')
      ? apiBase.substring(0, apiBase.length - 4)
      : apiBase;

  if (trimmed.startsWith('/api/')) {
    return '$backendBase$trimmed';
  }

  if (trimmed.startsWith('/uploads/')) {
    return '$apiBase$trimmed';
  }

  if (trimmed.startsWith('uploads/')) {
    return '$apiBase/$trimmed';
  }

  return '$apiBase/uploads/$trimmed';
}
