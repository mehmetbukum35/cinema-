# "Senin Listen" Hayalet Kartı + Kaynak Ölçümü — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Misafir kullanıcının kendi beğendiği yapımlardan oluşan "listesi", Keşfet'teki "Popüler Listeler" rayının başında —yayında olmadığı belirtilerek— görünsün; ve hangi davet yüzeyinin kayıt ürettiği ölçülebilsin.

**Architecture:** Ray kartı tamamen yerel veriden çizilir (`DatabaseHelper().getRatings()`), sunucuya istek yoktur. Ölçüm için kayıt kaynağı davete dokunulduğunda `SharedPreferences`'a yazılır, başarılı kimlik doğrulamadan sonra bir kez tüketilip yeni bir uca gönderilir ve `users.signup_source` kolonuna yazılır.

**Tech Stack:** Flutter / Dart, Riverpod 3 (`Notifier`), sqflite, PHP 8.4 + MySQL, PHPUnit, `flutter_test`.

**Spec:** [docs/superpowers/specs/2026-08-10-guest-to-member-invitation-design.md](../specs/2026-08-10-guest-to-member-invitation-design.md) — Faz 1 ve Faz 3. Faz 0 tamamlandı (`c7c97a7`). Faz 2 bu planda **yok**.

## Spec'ten bilinçli sapma (kart neyi gösteriyor)

Spec, kartın **Top 20 favorilerinden** çizilmesini ve `favorites.length >= 3`
koşulunu söylüyor. Bu plan bunun yerine **beğenilen yapımları** (rating ≥ 2,
gizli değil) kullanıyor.

Sebep spec yazılırken bilinmiyordu: sunucudaki gerçek profil kartlarının afiş
önizlemesi Top 20'den değil, `WHERE r.rating >= 2 AND r.deleted = 0 AND
r.is_private = 0` sorgusundan geliyor (`ProfilesPublicTrait.php`). Kartın tüm
fikri "seninki de onların yanında dursun" olduğuna göre, iki kart farklı
ölçütle doldurulursa kıyas yalan olur. Ayrıca Top 20'ye hiç dokunmamış ama
onlarca yapım puanlamış bir misafir, spec'in koşuluyla daveti hiç görmezdi.

Eşik yine 3.

## Global Constraints

- Dil: kod yorumları ve kullanıcıya görünen metinler Türkçe; l10n anahtarları İngilizce snake_case.
- `lib/l10n/tr.dart` ve `lib/l10n/en.dart` **aynı anahtar kümesine** sahip olmalı — `test/l10n_test.dart` doğruluyor.
- Riverpod: `StateNotifier`/`StateProvider` kullanma; kod tabanında sıfır kalıntı var.
- Yeni bir DB kolonu **hem** yeni migration dosyasına **hem** `backend/migrations/database.sql`'e eklenir — CI `database.sql`'i MySQL 8'e karşı doğruluyor ve ikisi ayrışırsa taze kurulum ile migrate edilmiş kurulum farklı şema taşır.
- Sunucuya giden serbest metin **beyaz listeye** tabidir; istemciden geleni doğrudan kolona yazma.
- Kod yorumları **nedeni** anlatır, ne yaptığını değil.
- Her commit öncesi: `dart format .` → `flutter analyze` (sıfır uyarı) → ilgili testler. Backend'e dokunan task'larda ayrıca `php backend/vendor/bin/phpunit --configuration backend/phpunit.xml` ve `composer --working-dir=backend phpstan`.
- Commit mesajları Conventional Commits, gövde İngilizce. Doğrudan `main`'e commit; dal açma; push etme.

---

### Task 1: Kayıt kaynağı kolonu ve ucu (backend)

İstemcinin göndereceği yer önce var olmalı.

**Files:**
- Create: `backend/migrations/030_signup_source.sql`
- Modify: `backend/migrations/database.sql` (users tablosu)
- Modify: `backend/src/Auth.php` (yeni metot)
- Modify: `backend/api/index.php` (yeni rota)
- Test: `backend/tests/AuthTest.php`

**Interfaces:**
- Produces: `POST /auth/signup-source` — gövde `{"source": "<ghost_card|couch_wall|profile_card>"}`, Bearer zorunlu, `200 {"ok":true}`; geçersiz kaynakta `400` + `code=invalid_signup_source`
- Produces: `Auth::recordSignupSource(int $uid, array $body): void`

- [ ] **Step 1: Migration dosyasını oluştur**

`backend/migrations/030_signup_source.sql`:

```sql
-- Migration 030: which invitation surface produced a signup.
ALTER TABLE users
  ADD COLUMN signup_source VARCHAR(32) NULL AFTER email_verified;
```

- [ ] **Step 2: Aynı kolonu database.sql'e ekle**

`backend/migrations/database.sql` içinde `CREATE TABLE \`users\`` bloğunu bul (satır ~240). `email_verified` satırının hemen ALTINA ekle:

```sql
  `signup_source` varchar(32) DEFAULT NULL,
```

Kolon sırası migration'daki `AFTER email_verified` ile aynı olmalı.

- [ ] **Step 3: Başarısız testi yaz**

`backend/tests/AuthTest.php` içine, `testLoginSuccess` metodunun ÜSTÜNE:

```php
    public function testRecordSignupSourceRejectsUnknownSource(): void
    {
        $auth = new Auth($this->db, $this->cfg);

        $this->expectException(TestExitException::class);
        try {
            $auth->recordSignupSource(7, ['source' => 'whatever_the_client_sent']);
        } finally {
            // Beyaz liste olmadan istemciden gelen her metin kolona yazılırdı.
            $this->assertSame(400, TestHelperRegistry::$lastStatus);
        }
    }

    public function testRecordSignupSourceWritesOnlyWhenStillUnset(): void
    {
        $stmt = $this->createMock(PDOStatement::class);
        $stmt->expects($this->once())
            ->method('execute')
            ->with(['ghost_card', 7]);

        $this->db->expects($this->once())
            ->method('prepare')
            // İlk atıf doğru olandır; sonraki girişler onu ezmemeli.
            ->with($this->stringContains('signup_source IS NULL'))
            ->willReturn($stmt);

        $auth = new Auth($this->db, $this->cfg);
        $auth->recordSignupSource(7, ['source' => 'ghost_card']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
    }
```

- [ ] **Step 4: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `php backend/vendor/bin/phpunit --configuration backend/phpunit.xml --filter AuthTest`
Expected: FAIL — `Call to undefined method Auth::recordSignupSource()`

- [ ] **Step 5: Metodu yaz**

`backend/src/Auth.php` içinde `optionalUser()` metodunun ALTINA:

```php
    /**
     * Davet yüzeyi ölçümü: hangi yüzey bu kaydı üretti.
     *
     * Yalnızca kolon HÂLÂ boşken yazılır. İlk atıf doğru olandır; kullanıcı
     * daha sonra başka bir yüzeyden tekrar giriş yaptığında ölçüm bozulmasın.
     *
     * @param array<string, mixed> $body
     */
    public function recordSignupSource(int $uid, array $body): void
    {
        $source = (string) ($body['source'] ?? '');
        // Beyaz liste: istemciden gelen serbest metni kolona yazmak hem
        // analitiği çöpe çevirir hem de kolona ne geldiğini denetlenemez kılar.
        if (!in_array($source, ['ghost_card', 'couch_wall', 'profile_card'], true)) {
            fail(400, 'Geçersiz kayıt kaynağı.', 'invalid_signup_source');
        }
        $st = $this->db->prepare(
            'UPDATE users SET signup_source = ? WHERE id = ? AND signup_source IS NULL'
        );
        $st->execute([$source, $uid]);
        json_out(200, ['ok' => true]);
    }
```

- [ ] **Step 6: Rotayı ekle**

`backend/api/index.php` içinde `case $route === 'POST /auth/logout':` bloğunun ALTINA:

```php
    // ── Kayıt kaynağı ölçümü (davet yüzeyi atfı) ───────────────────────────
    case $route === 'POST /auth/signup-source':
        $auth->recordSignupSource($auth->requireUser(), read_json());
        break;
```

- [ ] **Step 7: Testi çalıştır, YEŞİL olduğunu gör**

Run: `php backend/vendor/bin/phpunit --configuration backend/phpunit.xml --filter AuthTest`
Expected: PASS

- [ ] **Step 8: Tüm backend süiti + statik analiz**

Run:
```bash
php backend/vendor/bin/phpunit --configuration backend/phpunit.xml
composer --working-dir=backend phpstan
```
Expected: tümü PASS; PHPStan "No errors".

- [ ] **Step 9: Commit**

```bash
git add backend/migrations/030_signup_source.sql backend/migrations/database.sql backend/src/Auth.php backend/api/index.php backend/tests/AuthTest.php
git commit -m "$(cat <<'EOF'
feat(auth): record which invitation surface produced a signup

Phase 1 puts an invitation in the Discover rail. Without attribution there is
no way to tell whether it works, and the recommendation telemetry service is
Movie-centric — routing invite events through it would pollute recommendation
analytics.

Adds users.signup_source (migration 030, mirrored into database.sql so a fresh
install and a migrated one agree) and POST /auth/signup-source. The value is
whitelisted rather than stored as sent, and written only while the column is
still NULL: the first attribution is the true one, and a later sign-in from a
different surface must not overwrite it.
EOF
)"
```

---

### Task 2: Kaynağı istemcide sakla ve kayıttan sonra gönder

**Files:**
- Create: `lib/services/prefs/signup_attribution.dart`
- Modify: `lib/services/api/auth_api.dart`
- Modify: `lib/providers/auth/session.dart` (`_finalizeAuth`)
- Modify: `lib/providers/auth_provider.dart` (import)
- Test: `test/auth_api_test.dart`, `test/auth_provider_test.dart`

**Interfaces:**
- Consumes: Task 1'in `POST /auth/signup-source` ucu
- Produces: `PrefsSignupAttribution.remember(String source)` → `Future<void>`; `PrefsSignupAttribution.consume()` → `Future<String?>` (okur ve siler); `ApiService.recordSignupSource(String source)` → `Future<void>`

- [ ] **Step 1: Depolama sınıfını yaz**

`lib/services/prefs/signup_attribution.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Hangi davet yüzeyinin kaydı ürettiğini taşır.
///
/// Dokunuş ile kayıt arasında bir giriş ekranı, muhtemelen bir e-posta
/// doğrulaması ve uygulamanın yeniden açılması olabilir; bu yüzden atıf
/// bellekte değil diskte bekler.
class PrefsSignupAttribution {
  static const _key = 'pending_signup_source';

  /// Davete dokunuldu. Kayıt gerçekleşene kadar saklanır.
  static Future<void> remember(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, source);
  }

  /// Bir kez okunur ve silinir: aynı atıf ikinci bir oturum açılışında
  /// tekrar gönderilirse ölçüm kaydı şişer.
  static Future<String?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_key);
    if (source != null) await prefs.remove(_key);
    return source;
  }
}
```

- [ ] **Step 2: API metodu için başarısız test yaz**

`test/auth_api_test.dart` içindeki en dıştaki `main()` gövdesine, mevcut son
`group(...)` bloğunun ALTINA ekle. Bu dosya isteği `recorder` üzerinden
yakalıyor (`recorder.last`, `recorder.paths`) ve gövde için `sentBody()`
yardımcısı var — `requests` diye bir liste YOK:

```dart
  group('AuthApi signup source', () {
    test('recordSignupSource posts the source with the bearer token', () async {
      final api = apiWith(200, {'ok': true});

      await api.recordSignupSource('ghost_card');

      expect(recorder.last!.url.path, '/api/auth/signup-source');
      expect(sentBody(), {'source': 'ghost_card'});
      expect(recorder.last!.headers.containsKey('Authorization'), isTrue);
    });
  });
```

- [ ] **Step 3: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `flutter test test/auth_api_test.dart --plain-name "recordSignupSource"`
Expected: FAIL — `The method 'recordSignupSource' isn't defined`

- [ ] **Step 4: API metodunu yaz**

`lib/services/api/auth_api.dart` içinde, `logout` metodunun ALTINA:

```dart
  /// Davet yüzeyi atfını sunucuya bildirir. Ölçüm amaçlıdır: başarısızlığı
  /// kullanıcıya yansımaz, çağıran `unawaited` ile çağırır.
  Future<void> recordSignupSource(String source) async {
    await _request(
      'POST',
      '/auth/signup-source',
      body: {'source': source},
    );
  }
```

- [ ] **Step 5: Testi çalıştır, YEŞİL olduğunu gör**

Run: `flutter test test/auth_api_test.dart --plain-name "recordSignupSource"`
Expected: PASS

- [ ] **Step 6: Kayıttan sonra tüketen testi yaz**

`test/auth_provider_test.dart` içinde, `'guest merge reports what moved to the account'` testinin ALTINA:

```dart
    test('a stored invite source is reported once after signup', () async {
      await PrefsSignupAttribution.remember('ghost_card');
      final notifier = container.read(authProvider.notifier);

      await notifier.register('attributed@example.com', 'secret123');
      await pumpEventQueue();

      expect(mockApi.recordedSignupSources, ['ghost_card']);
      // Tüketildi: ikinci bir oturum açılışı aynı atfı tekrar göndermemeli.
      expect(await PrefsSignupAttribution.consume(), isNull);
    });
```

Aynı dosyadaki `MockApiService` sınıfına ekle:

```dart
  final List<String> recordedSignupSources = [];

  @override
  Future<void> recordSignupSource(String source) async {
    recordedSignupSources.add(source);
  }
```

ve dosyanın import bloğuna:

```dart
import 'package:ne_izlesem/services/prefs/signup_attribution.dart';
```

- [ ] **Step 7: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `flutter test test/auth_provider_test.dart --plain-name "invite source is reported"`
Expected: FAIL — `Expected: ['ghost_card'] Actual: []`

- [ ] **Step 8: Tüketimi bağla**

`lib/providers/auth_provider.dart` import bloğuna ekle:

```dart
import '../services/prefs/signup_attribution.dart';
```

`lib/providers/auth/session.dart` içinde `_finalizeAuth`'ta, `await completeLogin(...)` çağrısının ALTINA, `return AuthResult(` satırının ÜSTÜNE:

```dart
    // Ölçüm, akışı bloklamaz ve başarısızlığı kullanıcıya yansımaz: atıf
    // kaybolursa bir satır veri eksilir, oturum etkilenmez.
    unawaited(_reportSignupSource());
```

Aynı dosyada `_finalizeAuth` metodunun ALTINA:

```dart
  /// Bekleyen davet atfını bir kez sunucuya bildirir.
  Future<void> _reportSignupSource() async {
    try {
      final source = await PrefsSignupAttribution.consume();
      if (source == null) return;
      await _apiService.recordSignupSource(source);
    } catch (e) {
      debugPrint('Signup source attribution failed (ignored): $e');
    }
  }
```

- [ ] **Step 9: Testleri çalıştır, YEŞİL olduğunu gör**

Run: `flutter test test/auth_provider_test.dart test/auth_api_test.dart`
Expected: PASS

- [ ] **Step 10: Biçim, analiz, commit**

```bash
dart format .
flutter analyze
flutter test
git add lib/services/prefs/signup_attribution.dart lib/services/api/auth_api.dart lib/providers/auth/session.dart lib/providers/auth_provider.dart test/auth_api_test.dart test/auth_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): carry the invite source from tap through to signup

The tap that starts a signup and the signup itself can be separated by a
login screen, an email verification round trip, and an app restart, so the
attribution waits on disk rather than in memory.

It is consumed exactly once: a second sign-in must not re-report the same
attribution and inflate the count. Reporting is fire-and-forget — losing an
attribution costs one analytics row, and must never cost a session.
EOF
)"
```

---

### Task 3: Hayalet kart widget'ı

**Files:**
- Create: `lib/screens/browse/browse_guest_list_card.dart`
- Modify: `lib/l10n/tr.dart`, `lib/l10n/en.dart`
- Test: `test/browse_screen_widget_test.dart`

**Interfaces:**
- Consumes: `PrefsSignupAttribution.remember` (Task 2), `DatabaseHelper().getRatings()`
- Produces: `GuestListPreview({required List<Movie> posters, required int likedCount})`; `GuestListPreview.load()` → `Future<GuestListPreview?>` (3'ten az beğeni varsa `null`); `BrowseGuestListCard({required GuestListPreview preview})`

- [ ] **Step 1: l10n anahtarlarını iki dile ekle**

`lib/l10n/tr.dart` içinde `'top_lists_title'` satırının yakınına:

```dart
  'browse_guest_list_title': 'Senin Listen',
  'browse_guest_list_unpublished': 'yayında değil',
  'browse_guest_list_cta': 'Giriş yap ve yayınla',
```

`lib/l10n/en.dart` içinde aynı göreli konuma:

```dart
  'browse_guest_list_title': 'Your List',
  'browse_guest_list_unpublished': 'not published',
  'browse_guest_list_cta': 'Sign in and publish',
```

- [ ] **Step 2: Başarısız widget testini yaz**

`test/browse_screen_widget_test.dart` içine, mevcut misafir teaser testinin ALTINA:

```dart
  testWidgets('guest list card shows the user own posters and a publish CTA', (
    tester,
  ) async {
    final preview = GuestListPreview(
      posters: [
        Movie(id: 1, title: 'A', overview: '', voteAverage: 8, posterPath: '/a.jpg'),
        Movie(id: 2, title: 'B', overview: '', voteAverage: 8, posterPath: '/b.jpg'),
        Movie(id: 3, title: 'C', overview: '', voteAverage: 8, posterPath: '/c.jpg'),
      ],
      likedCount: 3,
    );

    await tester.pumpWidget(
      pumpApp(
        SizedBox(height: 200, child: BrowseGuestListCard(preview: preview)),
      ),
    );
    await tester.pump();

    expect(find.text('Your List'), findsOneWidget);
    expect(find.text('not published'), findsOneWidget);
    expect(find.text('Sign in and publish'), findsOneWidget);
  });
```

Dosyanın import bloğuna ekle:

```dart
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/screens/browse/browse_guest_list_card.dart';
```

- [ ] **Step 3: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `flutter test test/browse_screen_widget_test.dart --plain-name "guest list card"`
Expected: FAIL — dosya/sınıf yok.

- [ ] **Step 4: Widget'ı yaz**

`lib/screens/browse/browse_guest_list_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie.dart';
import '../../services/db_helper.dart';
import '../../services/localization_service.dart';
import '../../services/prefs/signup_attribution.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_cached_image.dart';
import '../login_screen.dart';

/// Misafirin kendi beğendiği yapımların önizlemesi.
///
/// Sunucudaki genel profil kartlarıyla AYNI ölçüt kullanılır (rating >= 2,
/// gizli değil) — kart yan yana durduğu gerçek listelerle aynı şeyi
/// göstermezse kıyas yalan olur.
class GuestListPreview {
  final List<Movie> posters;
  final int likedCount;

  const GuestListPreview({required this.posters, required this.likedCount});

  /// Gösterilecek bir şey yoksa `null` döner — ve o zaman davet de yoktur.
  static Future<GuestListPreview?> load() async {
    final ratings = await DatabaseHelper().getRatings();
    final liked = <Movie>[];
    for (final row in ratings) {
      final rating = row['rating'];
      final isPrivate = row['is_private'];
      if (rating is! int || rating < 2) continue;
      if (isPrivate is int && isPrivate == 1) continue;
      final movie = row['movie'];
      if (movie is! Movie) continue;
      if ((movie.posterPath ?? '').isEmpty) continue;
      liked.add(movie);
    }
    if (liked.length < 3) return null;
    return GuestListPreview(
      posters: liked.take(4).toList(),
      likedCount: liked.length,
    );
  }
}

/// "Popüler Listeler" rayının ilk kartı: kullanıcının kendi listesi, henüz
/// yayında değil. Sıra numarası yok; kesik çizgili kenarlık onu sıralamanın
/// bir parçası değil, bir davet yapar.
class BrowseGuestListCard extends StatelessWidget {
  const BrowseGuestListCard({super.key, required this.preview});

  final GuestListPreview preview;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tr = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Atıf dokunuşta yazılır: kayıt buradan saatler sonra tamamlanabilir.
        PrefsSignupAttribution.remember('ghost_card');
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.gold.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.radio_button_unchecked, size: 16, color: c.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr?.get('browse_guest_list_title') ?? 'Senin Listen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        tr?.get('browse_guest_list_unpublished') ??
                            'yayında değil',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (final movie in preview.posters) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: AppCachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        width: 38,
                        height: 58,
                        fit: BoxFit.cover,
                        preset: AppImageCachePreset.avatar,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr?.get('browse_guest_list_cta') ?? 'Giriş yap ve yayınla',
              style: TextStyle(
                color: c.gold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Widget'ın adı `AppCachedNetworkImage` (dosya adı `app_cached_image.dart` ama
sınıf adı farklı). `preset: AppImageCachePreset.avatar`, yan yana duracağı
`browse_top_profile_card.dart:211-216`'daki afiş çağrısıyla aynı olsun diye
verilir — aynı boyuttaki iki afiş farklı önbellek ayarıyla çizilmemeli.

- [ ] **Step 5: Testleri çalıştır, YEŞİL olduğunu gör**

Run: `flutter test test/browse_screen_widget_test.dart test/l10n_test.dart`
Expected: PASS

- [ ] **Step 6: Biçim, analiz, commit**

```bash
dart format .
flutter analyze
git add lib/screens/browse/browse_guest_list_card.dart lib/l10n/tr.dart lib/l10n/en.dart test/browse_screen_widget_test.dart
git commit -m "$(cat <<'EOF'
feat(browse): add the guest's own unpublished list card

The invitation is the user's own content, not a feature list: their liked
titles rendered in the same shape as the published profiles they are already
scrolling past, with the one difference stated plainly — theirs is not
published.

Previews use the same criterion the server uses for public profile previews
(rating >= 2, not private), so the card is comparable to the ones beside it
rather than flattering itself with a different measure.

load() returns null below three liked titles. With nothing to show there is
no invitation either, which is what keeps this from becoming a nag.
EOF
)"
```

---

### Task 4: Kartı raya bağla

**Files:**
- Modify: `lib/screens/browse/top_profiles_section.dart`
- Modify: `lib/screens/browse_screen.dart`
- Test: `test/browse_screen_widget_test.dart`

**Interfaces:**
- Consumes: Task 3'ün `GuestListPreview` ve `BrowseGuestListCard`'ı
- Produces: `BrowseTopProfilesSection({required List<TopProfile> profiles, Widget? leadingCard})`

- [ ] **Step 1: Rayı öncü kart alacak hale getir**

`lib/screens/browse/top_profiles_section.dart` — sınıfı şununla değiştir:

```dart
/// Keşfet: popüler profil listeleri yatay rayı.
class BrowseTopProfilesSection extends StatelessWidget {
  const BrowseTopProfilesSection({
    super.key,
    required this.profiles,
    this.leadingCard,
  });

  final List<TopProfile> profiles;

  /// Sıralamadan ÖNCE gelen kart (misafirin kendi listesi). Sıralamanın
  /// parçası olmadığı için rank numarası almaz ve profils sayımını kaydırır.
  final Widget? leadingCard;

  @override
  Widget build(BuildContext context) {
    final leading = leadingCard;
    final leadingCount = leading == null ? 0 : 1;

    return SliverToBoxAdapter(
      child: EntranceFade(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrowseSectionHeader(
              title:
                  AppLocalizations.of(context)?.get('top_lists_title') ??
                  'Popüler Listeler',
              gradient: CinemaGradients.crimson,
            ),
            SizedBox(
              height: 136,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: profiles.length + leadingCount,
                itemBuilder: (ctx, i) {
                  if (leading != null && i == 0) return leading;
                  final index = i - leadingCount;
                  return BrowseTopProfileCard(
                    profile: profiles[index],
                    rank: index + 1,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Browse ekranında önizlemeyi yükle**

`lib/screens/browse_screen.dart`:

(a) import ekle:

```dart
import 'browse/browse_guest_list_card.dart';
```

(b) `bool _phase2Pending = false;` satırının ALTINA alan ekle:

```dart
  /// Misafirin kendi listesi; girişliyken ya da yeterli beğeni yokken null.
  GuestListPreview? _guestPreview;
```

(c) `_load` içinde, `Future.microtask(() {` bloğunun ÜSTÜNE:

```dart
    // Misafirin kendi listesi tamamen yereldir; sunucuya istek yok.
    final guestPreview = isAuthenticated ? null : await GuestListPreview.load();
    if (!mounted || loadGeneration != _loadGeneration) return;
    setState(() => _guestPreview = guestPreview);
```

- [ ] **Step 3: Kartı raya geçir**

`lib/screens/browse_screen.dart` içinde şu bloğu:

```dart
          if (socialState.topProfiles.isNotEmpty)
            BrowseTopProfilesSection(profiles: socialState.topProfiles),
```

şununla değiştir:

```dart
          if (socialState.topProfiles.isNotEmpty || _guestPreview != null)
            BrowseTopProfilesSection(
              profiles: socialState.topProfiles,
              leadingCard: _guestPreview == null
                  ? null
                  : BrowseGuestListCard(preview: _guestPreview!),
            ),
```

- [ ] **Step 4: Ray testini yaz**

`test/browse_screen_widget_test.dart` içine ekle:

```dart
  testWidgets('the rail puts the guest card before the ranked profiles', (
    tester,
  ) async {
    final preview = GuestListPreview(
      posters: [
        Movie(id: 1, title: 'A', overview: '', voteAverage: 8, posterPath: '/a.jpg'),
        Movie(id: 2, title: 'B', overview: '', voteAverage: 8, posterPath: '/b.jpg'),
        Movie(id: 3, title: 'C', overview: '', voteAverage: 8, posterPath: '/c.jpg'),
      ],
      likedCount: 3,
    );

    await tester.pumpWidget(
      pumpApp(
        CustomScrollView(
          slivers: [
            BrowseTopProfilesSection(
              profiles: const [],
              leadingCard: BrowseGuestListCard(preview: preview),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BrowseGuestListCard), findsOneWidget);
    // Profil yokken bile ray çizilir: davet tek başına ayakta durur.
    expect(find.byType(BrowseTopProfileCard), findsNothing);
  });
```

Import bloğuna ekle:

```dart
import 'package:ne_izlesem/screens/browse/top_profiles_section.dart';
import 'package:ne_izlesem/screens/browse/browse_top_profile_card.dart';
```

- [ ] **Step 5: Testleri çalıştır**

Run: `flutter test test/browse_screen_widget_test.dart`
Expected: PASS

- [ ] **Step 6: Tüm süit, biçim, analiz**

Run:
```bash
dart format .
flutter analyze
flutter test
```
Expected: `flutter analyze` → "No issues found!", tüm testler PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/browse/top_profiles_section.dart lib/screens/browse_screen.dart test/browse_screen_widget_test.dart
git commit -m "$(cat <<'EOF'
feat(browse): place the guest's list first in the public profiles rail

The card sits before the ranked profiles rather than after them, so the
comparison lands immediately: your posters, then everyone else's published
lists. It takes no rank number — it is not part of the ranking, it is the
invitation to join it.

The rail now renders when there is a guest card even with no profiles yet, so
a guest on a cold catalog still sees the invitation.
EOF
)"
```

---

## Doğrulama (tüm task'lar sonrası)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
php backend/vendor/bin/phpunit --configuration backend/phpunit.xml
composer --working-dir=backend phpstan
```

## Elle duman testi

Emülatörde, **çıkış yapmış** halde:
1. 3+ yapımı "İyi" veya "Harika" puanla
2. Keşfet'i aşağı kaydır → "Popüler Listeler" rayının başında kendi afişlerinle "Senin Listen / yayında değil" kartı görünmeli
3. 2'den az beğenin varken kart **görünmemeli**
4. Karta dokun → giriş ekranı açılmalı
5. Kaydol → sunucuda `users.signup_source` `'ghost_card'` olmalı

## Kapsam dışı

- Faz 2 (duvar metinleri) — ayrı, küçük bir değişiklik
- `couch_wall` ve `profile_card` kaynak etiketleri: uç ve depolama onları kabul ediyor, ama o yüzeylere `remember(...)` çağrısı Faz 2'de eklenecek
