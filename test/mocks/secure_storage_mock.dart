import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupSecureStorageMock() {
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
