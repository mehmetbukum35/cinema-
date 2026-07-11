import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ne_izlesem/models/social.dart';
import 'package:ne_izlesem/services/api_service.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';

void setupAppFlowSecureStorageMock() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> values = {};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'write':
            final args = methodCall.arguments as Map;
            values[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            final args = methodCall.arguments as Map;
            return values[args['key'] as String];
          case 'delete':
            final args = methodCall.arguments as Map;
            values.remove(args['key'] as String);
            return null;
          case 'deleteAll':
            values.clear();
            return null;
          case 'readAll':
            return values;
          default:
            return null;
        }
      });
}

class MockIntegrationApiService implements ApiService {
  @override
  void Function()? onSessionExpired;

  bool loginCalled = false;
  bool pushCalled = false;
  bool pullCalled = false;

  Map<String, dynamic> loginResponse = {
    'tokens': {'access_token': 'mock_access', 'refresh_token': 'mock_refresh'},
    'user': {
      'id': 100,
      'email': 'integration@neizlesem.com',
      'username': 'integration',
      'display_name': 'Integration User',
      'is_public': 1,
    },
  };

  Map<String, dynamic> pullResponse = {
    'ratings': [],
    'watchlist': [],
    'server_time': 5000,
  };

  Map<String, dynamic> pushResponse = {'applied': true, 'server_time': 6000};

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    loginCalled = true;
    return loginResponse;
  }

  @override
  Future<Map<String, dynamic>> push(Map<String, dynamic> payload) async {
    pushCalled = true;
    return pushResponse;
  }

  @override
  Future<Map<String, dynamic>> pull(int since) async {
    pullCalled = true;
    return pullResponse;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<Map<String, dynamic>> getFriends() async => {
    'friends': [],
    'pending_received': [],
    'pending_sent': [],
  };

  @override
  Future<List<dynamic>> getActivityFeed({int? friendId}) async => [];

  @override
  Future<Map<String, dynamic>> getRecommendations() async => {
    'recommendations': [],
    'unseen': 0,
  };

  @override
  Future<Map<String, dynamic>> getTopProfiles() async => {'profiles': []};

  @override
  Future<FriendSignals> getFriendSignals() async => const FriendSignals();

  @override
  Future<void> publishTasteDna(Map<String, dynamic> payload) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TmdbService createMockTmdbService() {
  final mockMovies = {
    'results': [
      {
        'id': 1001,
        'title': 'Swipe Integration Test Movie',
        'overview': 'Incredible integration test overview.',
        'vote_average': 8.7,
        'release_date': '2026-06-23',
        'genre_ids': [28],
        'poster_path': '/mock_poster.jpg',
        'vote_count': 100,
      },
    ],
  };
  final mockTv = {'results': []};
  const emptyProviders = {
    'results': {
      'TR': {'flatrate': [], 'rent': [], 'buy': []},
    },
  };

  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.contains('/watch/providers')) {
      return http.Response(jsonEncode(emptyProviders), 200);
    }
    if (path.contains('/3/tv/popular') ||
        path.contains('/3/discover/tv') ||
        path.contains('/3/trending/tv')) {
      return http.Response(jsonEncode(mockTv), 200);
    }
    if (path.contains('/3/movie/popular') ||
        path.contains('/3/discover/movie') ||
        path.contains('/3/trending/movie') ||
        path.contains('/3/trending/all') ||
        path.contains('/3/movie/now_playing') ||
        path.contains('/3/movie/upcoming')) {
      return http.Response(jsonEncode(mockMovies), 200);
    }
    if (path.contains('/3/')) {
      return http.Response(jsonEncode({'results': []}), 200);
    }
    return http.Response('Not Found', 404);
  });

  return TmdbService(client: client);
}
