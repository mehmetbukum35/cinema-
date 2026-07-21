part of '../api_service.dart';

/// Offline synchronization backend operations.
mixin SyncApi on ApiClient {
  Future<Map<String, dynamic>> pull(
    int since, {
    bool localReset = false,
  }) async {
    final deviceId = await PrefsService.getSyncDeviceId();
    final localResetQuery = localReset ? '&local_reset=1' : '';
    final response = await _request(
      'GET',
      '/sync?since=$since&ack_cursor=$since&device_id=${Uri.encodeQueryComponent(deviceId)}&locale=${Uri.encodeQueryComponent(PrefsService.activeLanguageCode)}$localResetQuery',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ??
            'Veri senkronizasyonu (pull) başarısız.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    final enrichedPayload = Map<String, dynamic>.from(payload);
    enrichedPayload['device_id'] ??= await PrefsService.getSyncDeviceId();
    enrichedPayload['ack_cursor'] ??= await PrefsService.getLastSyncTime();
    final response = await _request(
      'POST',
      '/sync',
      body: enrichedPayload,
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ??
            'Veri senkronizasyonu (push) başarısız.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> clearRemoteSearchHistory() async {
    final response = await _request(
      'DELETE',
      '/search-history',
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message:
            data['error'] as String? ?? 'Arama geçmişi sunucudan silinemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> clearRemoteSyncData() async {
    final response = await _request('DELETE', '/sync', requireAuth: true);
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Bulut verileri sıfırlanamadı.',
        code: data['code'] as String?,
      );
    }
  }
}
