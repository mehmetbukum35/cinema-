import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ne_izlesem/screens/social_screen.dart';
import 'mocks/secure_storage_mock.dart';
import 'helpers/widget_test_helpers.dart';

void main() {
  setupSecureStorageMock();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SocialScreen renders tab labels', (tester) async {
    await tester.pumpWidget(pumpApp(const SocialScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
  });
}
