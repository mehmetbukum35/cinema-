import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/services/prefs_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group(
    'DNA eşik anı mantığı (pendingDnaMilestone / markDnaMilestoneShown)',
    () {
      test('ilk eşiğin altında hiçbir eşik dönmez', () async {
        expect(await PrefsService.pendingDnaMilestone(0), isNull);
        expect(await PrefsService.pendingDnaMilestone(4), isNull);
      });

      test(
        'eşiğe ulaşınca o eşik döner ve işaretlenince tekrar dönmez',
        () async {
          expect(await PrefsService.pendingDnaMilestone(5), 5);
          await PrefsService.markDnaMilestoneShown(5);
          expect(await PrefsService.pendingDnaMilestone(5), isNull);
          expect(await PrefsService.pendingDnaMilestone(24), isNull);
          // Bir sonraki eşik hâlâ bekliyor.
          expect(await PrefsService.pendingDnaMilestone(25), 25);
        },
      );

      test('her zaman gösterilmemiş en YÜKSEK eşik döner', () async {
        // Mevcut kullanıcı senaryosu: 60 puanla gelen kullanıcı 5 ve 25'in
        // kartlarını değil, doğrudan 50'ninkini görmeli.
        expect(await PrefsService.pendingDnaMilestone(60), 50);
      });

      test(
        'yüksek eşiği işaretlemek altındaki tüm eşikleri de kapatır',
        () async {
          await PrefsService.markDnaMilestoneShown(50);
          expect(await PrefsService.pendingDnaMilestone(60), isNull);
          expect(await PrefsService.pendingDnaMilestone(5), isNull);
          expect(await PrefsService.pendingDnaMilestone(25), isNull);
        },
      );

      test('düşük eşiği işaretlemek yüksek eşiği kapatmaz', () async {
        await PrefsService.markDnaMilestoneShown(5);
        expect(await PrefsService.pendingDnaMilestone(25), 25);
        await PrefsService.markDnaMilestoneShown(25);
        expect(await PrefsService.pendingDnaMilestone(49), isNull);
        expect(await PrefsService.pendingDnaMilestone(50), 50);
      });

      test('işaretleme idempotenttir', () async {
        await PrefsService.markDnaMilestoneShown(25);
        await PrefsService.markDnaMilestoneShown(25);
        final prefs = await SharedPreferences.getInstance();
        final shown = prefs.getStringList('dna_milestones_shown_v1')!;
        expect(shown.toSet().length, shown.length); // kopya kayıt yok
      });
    },
  );
}
