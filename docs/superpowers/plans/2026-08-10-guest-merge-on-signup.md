# Misafir Verisini Kayıtta Sessizce Birleştirme — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hiç giriş yapmamış bir misafir kaydolduğunda "Hesap Çakışması" diyaloğu çıkmasın; yerel verisi sessizce hesabına taşınsın ve ne taşındığı kendisine söylensin.

**Architecture:** Tek bir koşul değişikliği (`lib/providers/auth/session.dart` içindeki `_finalizeAuth`) çakışmayı yalnızca gerçek hesap değişimine indirger. Ardından `AuthResult`, taşınan kayıt sayılarını taşıyacak küçük bir değer nesnesi kazanır ve giriş ekranı bunu tek satırlık bir toast olarak gösterir.

**Tech Stack:** Flutter / Dart, Riverpod 3 (`Notifier`), sqflite, `flutter_test`.

**Spec:** [docs/superpowers/specs/2026-08-10-guest-to-member-invitation-design.md](../specs/2026-08-10-guest-to-member-invitation-design.md) — Faz 0.

## Global Constraints

- Dil: kod yorumları ve kullanıcıya görünen metinler Türkçe; l10n anahtarları İngilizce snake_case.
- `lib/l10n/tr.dart` ve `lib/l10n/en.dart` **aynı anahtar kümesine** sahip olmalı — `test/l10n_test.dart` bunu doğruluyor, anahtar eklerken ikisine birden ekle.
- Riverpod: `StateNotifier`/`StateProvider` kullanma; kod tabanında sıfır kalıntı var, öyle kalmalı.
- Kod yorumları **nedeni** anlatır, ne yaptığını değil. Bu kod tabanının yerleşik alışkanlığı.
- Her commit öncesi: `dart format .` → `flutter analyze` (sıfır uyarı) → ilgili testler.
- Commit mesajları Conventional Commits (`fix(auth): ...`), gövde İngilizce.
- Doğrudan `main`'e commit ediliyor; dal açma.

---

### Task 1: Misafir kaydında çakışmayı kaldır

Çekirdek düzeltme. Tek başına gönderilebilir ve tek başına bir hatayı kapatır.

**Files:**
- Modify: `lib/providers/auth/session.dart:59-82` (`_finalizeAuth`)
- Test: `test/auth_provider_test.dart:603-627` (mevcut testin **beklentisi değişiyor**)

**Interfaces:**
- Consumes: `PrefsAuthStorage.getLastAuthenticatedUserId()` → `Future<String?>`, `DatabaseHelper().hasAnyLocalData()` → `Future<bool>`
- Produces: `_finalizeAuth` davranışı — misafir + yerel veri → `AuthStatus.success`; gerçek hesap değişimi + yerel veri → `AuthStatus.conflict`

> **DİKKAT:** `test/auth_provider_test.dart` içinde şu an **hatalı davranışı kilitleyen** bir test var:
> `'should trigger conflict when guest registers and local data exists'` (satır 603).
> Bu test bilerek değiştirilecek. Testi "kırıldı" diye implementasyonu geri alma.

- [ ] **Step 1: Mevcut testi yeni davranışa çevir**

`test/auth_provider_test.dart` içindeki testi (satır 603-627) tamamen şununla değiştir:

```dart
    test(
      'guest registration merges local data instead of raising a conflict',
      () async {
        final notifier = container.read(authProvider.notifier);

        // Misafir: cihazda daha önce hiç oturum açılmamış.
        await PrefsAuthStorage.setLastAuthenticatedUserId(null);
        await PrefsLibraryFacade.saveRating(
          movieId: 123,
          isTV: false,
          rating: 3,
          metadataLocale: 'tr',
        );

        final result = await notifier.register(
          'guest_reg@example.com',
          'secret123',
        );

        // Çakışacak ikinci hesap yok: veri sahibine kavuşur.
        expect(result.status, AuthStatus.success);
        expect(container.read(authProvider).isAuthenticated, isTrue);

        // Çekirdek vaat: misafirken verilen puan kaybolmaz.
        final rating = await PrefsLibraryFacade.getRating(123, false);
        expect(rating, isNotNull);
        expect(rating!['rating'], 3);
      },
    );
```

- [ ] **Step 2: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `flutter test test/auth_provider_test.dart --plain-name "guest registration merges local data"`
Expected: FAIL — `Expected: <AuthStatus.success> Actual: <AuthStatus.conflict>`

- [ ] **Step 3: Koşulu düzelt**

`lib/providers/auth/session.dart` içinde `_finalizeAuth`'taki şu bloğu:

```dart
    if (hasLocalData && (lastUserId == null || lastUserId != newUserId)) {
      state = state.copyWith(loading: false);
      return AuthResult(
        status: AuthStatus.conflict,
        user: user,
        tokens: tokens,
      );
    }
```

şununla değiştir:

```dart
    // Çakışma yalnızca GERÇEK hesap değişiminde vardır: cihazda daha önce
    // BAŞKA bir hesap oturum açmış olmalı. Hiç giriş yapmamış misafirin
    // verisi kimseyle çakışmaz, sahibine kavuşur.
    //
    // Eskiden `lastUserId == null` de çakışma sayılıyordu ve sonuç şuydu:
    // kullanıcı veri kaybı korkusuyla kaydoluyor, ödül olarak "Hesap
    // Çakışması" başlıklı bir diyalog ve "Cihazdakileri Sil & Buluttan
    // Yükle" seçeneği görüyordu. Yeni hesapta bulut boş olduğu için o
    // seçenek her şeyi siliyor, yerine hiçbir şey koymuyordu.
    final isAccountSwitch = lastUserId != null && lastUserId != newUserId;
    if (hasLocalData && isAccountSwitch) {
      state = state.copyWith(loading: false);
      return AuthResult(
        status: AuthStatus.conflict,
        user: user,
        tokens: tokens,
      );
    }
```

- [ ] **Step 4: Testi çalıştır, YEŞİL olduğunu gör**

Run: `flutter test test/auth_provider_test.dart --plain-name "guest registration merges local data"`
Expected: PASS

- [ ] **Step 5: Hesap değişiminin HÂLÂ çakıştığını doğrula**

Bu testler zaten var ve değişmemeli. Çalıştır:

Run: `flutter test test/auth_provider_test.dart --plain-name "conflict"`
Expected: PASS — özellikle `'should trigger conflict when different user logins and local data exists'` yeşil kalmalı.

- [ ] **Step 6: Veri olmayan misafir için regresyon testi ekle**

Aynı `group` içine, az önce değiştirdiğin testin hemen altına ekle:

```dart
    test('guest registration with no local data still succeeds', () async {
      final notifier = container.read(authProvider.notifier);

      await PrefsAuthStorage.setLastAuthenticatedUserId(null);
      // Yerel veri YOK: hasLocalData false, çakışma dalı zaten çalışmamalı.

      final result = await notifier.register(
        'empty_guest@example.com',
        'secret123',
      );

      expect(result.status, AuthStatus.success);
      expect(container.read(authProvider).isAuthenticated, isTrue);
    });
```

- [ ] **Step 7: Tüm auth testlerini çalıştır**

Run: `flutter test test/auth_provider_test.dart`
Expected: PASS (tamamı)

- [ ] **Step 8: Biçim + analiz + commit**

```bash
dart format .
flutter analyze
flutter test test/auth_provider_test.dart
git add lib/providers/auth/session.dart test/auth_provider_test.dart
git commit -m "$(cat <<'EOF'
fix(auth): stop treating a first-time guest as an account conflict

_finalizeAuth read a null lastUserId as a conflict. For a guest that is
always true the moment they have any local data, so every guest signup
landed on the conflict dialog — titled "Hesap Çakışması", offering
"Cihazdakileri Sil & Buluttan Yükle". On a brand-new account the cloud is
empty, so that branch deleted everything the user had and restored nothing.

A conflict needs two accounts. Absence of a previous session is not a
conflict; it is a guest whose data now has an owner. Conflict is now raised
only when the device previously held a *different* account.

The existing test asserted the old behaviour and was rewritten rather than
deleted: it now proves the rating survives signup. Account-switch conflicts
are unchanged and still covered.
EOF
)"
```

---

### Task 2: Taşınan veriyi kullanıcıya söyle

Korkulan an, en güven verici ana dönüşür.

**Files:**
- Modify: `lib/providers/auth_provider.dart:36-43` (`AuthResult`)
- Modify: `lib/providers/auth/session.dart` (`_finalizeAuth` — sayıları yakala)
- Modify: `lib/l10n/tr.dart`, `lib/l10n/en.dart`
- Modify: `lib/screens/login_screen.dart:111-113` (`AuthStatus.success` dalı)
- Test: `test/auth_provider_test.dart`

**Interfaces:**
- Consumes: Task 1'in `AuthStatus.success` dalı; `PrefsLibraryFacade.getRatingCount()` → `Future<int>`, `PrefsLibraryFacade.getWatchlist()` → `Future<List<Movie>>`
- Produces: `MergedGuestData({required int ratingCount, required int watchlistCount})`; `AuthResult.mergedGuestData` → `MergedGuestData?` (yalnızca misafir birleştirmesinde dolu, aksi halde `null`)

- [ ] **Step 1: Başarısız testi yaz**

`test/auth_provider_test.dart`, Task 1'de eklediğin testlerin altına:

```dart
    test('guest merge reports what moved to the account', () async {
      final notifier = container.read(authProvider.notifier);

      await PrefsAuthStorage.setLastAuthenticatedUserId(null);
      await PrefsLibraryFacade.saveRating(
        movieId: 123,
        isTV: false,
        rating: 3,
        metadataLocale: 'tr',
      );
      await PrefsLibraryFacade.addToWatchlist(
        Movie(id: 999, title: 'Watch Me', overview: '', voteAverage: 7),
        metadataLocale: 'tr',
      );

      final result = await notifier.register(
        'summary_guest@example.com',
        'secret123',
      );

      expect(result.status, AuthStatus.success);
      expect(result.mergedGuestData, isNotNull);
      expect(result.mergedGuestData!.ratingCount, 1);
      expect(result.mergedGuestData!.watchlistCount, 1);
    });

    test('a returning user with no guest data reports no merge', () async {
      final notifier = container.read(authProvider.notifier);

      await PrefsAuthStorage.setLastAuthenticatedUserId(null);
      // Yerel veri yok → taşınan da yok → özet gösterilmemeli.

      final result = await notifier.register(
        'nothing_to_move@example.com',
        'secret123',
      );

      expect(result.status, AuthStatus.success);
      expect(result.mergedGuestData, isNull);
    });
```

`Movie` importu dosyada yoksa ekle:

```dart
import 'package:ne_izlesem/models/movie.dart';
```

- [ ] **Step 2: Testi çalıştır, KIRMIZI olduğunu gör**

Run: `flutter test test/auth_provider_test.dart --plain-name "guest merge reports what moved"`
Expected: FAIL — `The getter 'mergedGuestData' isn't defined for the type 'AuthResult'`

- [ ] **Step 3: Değer nesnesini ve alanı ekle**

`lib/providers/auth_provider.dart` içinde `AuthResult`'ın **üstüne** ekle:

```dart
/// Misafirken biriken ve girişte hesaba taşınan yerel verinin özeti.
/// Sayılar birleştirmeden ÖNCE okunur: `_postAuthSessionRestore` sync'i
/// tetikliyor ve sunucudan gelen kayıtlar sayıları değiştirebiliyor.
class MergedGuestData {
  final int ratingCount;
  final int watchlistCount;

  const MergedGuestData({
    required this.ratingCount,
    required this.watchlistCount,
  });

  bool get isEmpty => ratingCount == 0 && watchlistCount == 0;
}
```

Aynı dosyada `AuthResult`'ı şu hale getir:

```dart
class AuthResult {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? tokens;
  final String? errorMessage;

  /// Yalnızca misafir verisi hesaba taşındığında dolu; aksi halde null.
  final MergedGuestData? mergedGuestData;

  AuthResult({
    required this.status,
    this.user,
    this.tokens,
    this.errorMessage,
    this.mergedGuestData,
  });
}
```

- [ ] **Step 4: Sayıları birleştirmeden önce yakala**

`lib/providers/auth/session.dart`, `_finalizeAuth` — Task 1'de eklediğin `isAccountSwitch` bloğunun **altına**, `await completeLogin(...)` çağrısının **üstüne**:

```dart
    // Sayılar completeLogin'den ÖNCE okunur: o çağrı _postAuthSessionRestore
    // üzerinden sync tetikliyor ve sunucudan gelen kayıtlar sayıyı şişirirdi.
    // Kullanıcıya "senin taşıdığın" sayı söylenmeli, "sende toplam kaç var" değil.
    final merged = hasLocalData
        ? MergedGuestData(
            ratingCount: await PrefsLibraryFacade.getRatingCount(),
            watchlistCount: (await PrefsLibraryFacade.getWatchlist()).length,
          )
        : null;

    await completeLogin(
      user: user,
      tokens: tokens,
      resolution: ConflictResolution.merge,
    );
    return AuthResult(
      status: AuthStatus.success,
      mergedGuestData: merged != null && !merged.isEmpty ? merged : null,
    );
```

Mevcut `await completeLogin(...)` + `return AuthResult(status: AuthStatus.success);` satırlarını bu blokla değiştir (iki kez `completeLogin` çağrısı kalmasın).

- [ ] **Step 5: Testleri çalıştır, YEŞİL olduğunu gör**

Run: `flutter test test/auth_provider_test.dart --plain-name "merge"`
Expected: PASS

- [ ] **Step 6: l10n anahtarını iki dile birden ekle**

`lib/l10n/tr.dart` içine, `'auth_conflict_title'` satırının hemen üstüne:

```dart
  'auth_guest_data_merged':
      '{} puanın ve {} izleme listesi kaydın hesabına taşındı.',
```

`lib/l10n/en.dart` içine, aynı göreli konuma:

```dart
  'auth_guest_data_merged':
      '{} ratings and {} watchlist items moved to your account.',
```

- [ ] **Step 7: l10n eşitliğini doğrula**

Run: `flutter test test/l10n_test.dart`
Expected: PASS — iki dosya aynı anahtar kümesine sahip olmalı.

- [ ] **Step 8: Giriş ekranında göster**

`lib/screens/login_screen.dart`, `_handleAuthResult` içindeki şu dalı:

```dart
    } else if (result.status == AuthStatus.success) {
      if (mounted) Navigator.of(context).pop();
    } else if (result.status == AuthStatus.conflict) {
```

şununla değiştir:

```dart
    } else if (result.status == AuthStatus.success) {
      // Toast kök Overlay'e çizildiği için (bkz. showAppSnackBar) bu ekran
      // pop edildikten sonra da ayakta kalır; pop'tan ÖNCE göstermek yeterli.
      final merged = result.mergedGuestData;
      if (merged != null && mounted) {
        final tr = AppLocalizations.of(context);
        showAppToast(
          context,
          (tr?.get('auth_guest_data_merged') ??
                  '{} puanın ve {} izleme listesi kaydın hesabına taşındı.')
              .replaceFirst('{}', '${merged.ratingCount}')
              .replaceFirst('{}', '${merged.watchlistCount}'),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } else if (result.status == AuthStatus.conflict) {
```

`localization_service.dart` bu dosyada zaten import edilmiş durumda (satır 9).
`app_toast.dart` **edilmemiş**; import bloğuna ekle:

```dart
import '../widgets/app_toast.dart';
```

- [ ] **Step 9: Biçim + analiz + tüm süit**

Run:
```bash
dart format .
flutter analyze
flutter test
```
Expected: `flutter analyze` → "No issues found!", tüm testler PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/providers/auth_provider.dart lib/providers/auth/session.dart lib/l10n/tr.dart lib/l10n/en.dart lib/screens/login_screen.dart test/auth_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(auth): tell the user what moved when guest data is merged

Signing up as a guest now silently merges local data, which leaves the user
with no evidence anything happened — the same silence that made the old
conflict dialog feel necessary. AuthResult carries a MergedGuestData summary
and the login screen reports it in one line.

The counts are read before completeLogin: that call triggers
_postAuthSessionRestore, whose sync pulls server rows and would inflate the
numbers. The user should be told what *they* brought, not what they now own.

The summary is null when there was nothing to move, so a returning user with
an empty device sees no toast.
EOF
)"
```

---

## Doğrulama (her iki task sonrası)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Üçü de temiz olmalı. Backend'e dokunulmadığı için PHPUnit/PHPStan çalıştırmaya gerek yok.

## Elle duman testi (opsiyonel ama önerilir)

Emülatörde:
1. Misafirken 2-3 film puanla, birini izleme listesine ekle
2. Profil → Giriş Yap → yeni bir hesapla kaydol
3. **Beklenen:** "Hesap Çakışması" diyaloğu **çıkmaz**; bunun yerine "2 puanın ve 1 izleme listesi kaydın hesabına taşındı." toast'ı görünür
4. Profil → puanların yerinde olmalı

## Kapsam dışı

Faz 1 (hayalet kart), Faz 2 (duvar metinleri) ve Faz 3 (`signup_source` ölçümü) bu planda **yok**. Spec'te tanımlılar ve ayrı bir planla gidecekler.
