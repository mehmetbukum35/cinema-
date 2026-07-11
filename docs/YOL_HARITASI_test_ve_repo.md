# cinema+ — Test Otomasyonu & Repo Hijyeni Yol Haritası

> Amaç: Genel notu 8.7'den 9+'a taşıyan iki başlığı kapatmak — **otomatik test** ve **repo hijyeni**.
> Bu doküman koddan bağımsız "çevre" işleri içindir. Her madde işaretlenebilir bir görevdir.

---

## BÖLÜM A — OTOMATİK TEST

### A0. Mevcut durum (envanter)

Zaten elinde olanlar (`test/`):

| Dosya | Kapsadığı |
|---|---|
| `movie_test.dart` | `Movie.fromJson`, türetilmiş alanlar (year, matchScore, posterUrl) |
| `prefs_service_test.dart` | Ağırlıklı tür sıralaması, rating kaydı |
| `tmdb_service_test.dart` | `searchMulti` parse + media_type filtreleme (MockClient) |
| `swipe_notifier_test.dart` | Swipe iş mantığı, izlenmiş filtreleme (MockClient) |
| `swipe_widget_test.dart` | SwipeScreen etkileşim/render |
| `widget_test.dart` | Onboarding + MainShell render |
| `mocks/secure_storage_mock.dart` | Test altyapısı |

**Sonuç:** İyi bir temel var ve doğru teknikler kullanılmış (HTTP mock, business-logic ayrımı). Eksik olan: (1) bazı ekran alanlarında widget testi (kısmen tamamlandı), (2) kapsam ölçümü hedeflerinin tam karşılanması, (3) README ve repo cilası.

---

### A1. Kapsam boşluklarını kapat (öncelik sırasına göre)

Hiç testi olmayan ve risk taşıyan modüller — yukarıdan başla:

- [x] **`services/sync_service.dart`** — EN KRİTİK. Delta-sync'in last-write-wins kuralı, `since` zamanı yönetimi, soft-delete senkronu burada. Bir veri kaybı hatası en çok burada canını yakar.
  - Test et: yerelden daha yeni kayıt sunucuyu ezer mi; sunucudan gelen `deleted:true` yereli siler mi; `server_time` doğru saklanıp bir sonraki `since` olarak kullanılıyor mu; boş/çakışan payload davranışı.
- [x] **`providers/social_provider.dart`** — arkadaş ekleme/kabul/ret state geçişleri, `pendingReceived` sayacı, hata durumunda state.
- [x] **`providers/watchlist_provider.dart`** — ekleme/çıkarma, optimistic update, invalidate sonrası yeniden yükleme.
- [x] **`providers/auth_provider.dart`** — login/logout state, token saklama (mock secure storage zaten var).
- [x] **`services/api_service.dart`** — endpoint URL/gövde doğruluğu, 401/4xx/5xx hata eşlemesi (MockClient).
- [x] **`services/db_helper.dart`** — SQLite CRUD; `sqflite_common_ffi` ile bellek-içi DB kullan (aşağıda).

### A2. Genişletilmesi gereken mevcut testler

- [ ] `tmdb_service_test.dart`: sadece `searchMulti` var. Ekle → `discoverByGenres`, `getRecommendations`, `getTrending`, hata/timeout yolu, boş sonuç.
- [ ] `swipe_notifier_test.dart`: undo, dil/platform filtresi, "içerik kalmadı" durumu, `loadMore`.
- [ ] Widget testleri: en az bir testte **açık tema** ile render (regresyon yakalar).
- [x] Widget smoke testleri: `profile_screen`, `browse_screen`, `social_screen`, `movie_detail_sheet` (`test/*_widget_test.dart`).

### A3. Backend testleri (PHP — şu an sıfır)

Flutter tarafı iyi ama `backend/src/*.php` hiç test edilmiyor. Sosyal mantık ve auth kritik.

- [x] `composer init` + `composer require --dev phpunit/phpunit`
- [x] SQLite in-memory PDO ile test fixture'ı kur (şemayı `database.sql`'den yükle).
- [x] Öncelikli sınıflar: `Social` (arkadaşlık akışı, karşılıklı kabul, kesişim yetkisi, feed eşiği), `Jwt` (imzala/doğrula/expired), `Auth` (register çakışma, login yanlış şifre).
- [x] Klasör: `backend/tests/`, `backend/phpunit.xml`.

### A4. Kapsam ölçümü (coverage)

- [ ] Flutter: `flutter test --coverage` → `coverage/lcov.info`.
- [ ] Yerel rapor: `genhtml coverage/lcov.info -o coverage/html` (lcov kurulu olmalı).
- [ ] Hedef koy: kritik `services/` ve `providers/` için **%70+ satır kapsamı**. UI %100 şart değil.

### A5. "Otomatik" kısmı — CI kurulumu (en yüksek getiri)

Testler ancak her push'ta kendiliğinden çalışırsa "otomatik" olur. GitHub kullanıyorsan:

- [x] `.github/workflows/ci.yml` oluştur (taslak aşağıda).
- [ ] PR'larda zorunlu kontrol yap (branch protection → "require status checks").
- [ ] Rozet ekle: README'ye build/test badge.

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage
  php:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: shivammathur/setup-php@v2
        with: { php-version: '8.4' }
      - run: composer install --working-dir=backend
      - run: backend/vendor/bin/phpunit --configuration backend/phpunit.xml
```

> GitLab kullanıyorsan aynı adımları `.gitlab-ci.yml`'de `flutter:stable` image'ı ile kurarsın.

### A6. Test sırası (önerilen takvim)

1. **Hafta 1:** `sync_service` + `api_service` testleri (en yüksek risk).
2. **Hafta 1:** CI workflow'u devreye al — bundan sonrası otomatik korunur.
3. **Hafta 2:** Provider testleri (social, watchlist, auth).
4. **Hafta 2:** Backend PHPUnit (Social + Jwt + Auth).
5. **Hafta 3:** Mevcut testleri genişlet + coverage hedefini tuttur.

---

## BÖLÜM B — REPO HİJYENİ

### B1. README (şu an varsayılan Flutter şablonu)

`README.md` hâlâ "ne_izlesem / A new Flutter project" diyor. Aşağıdaki iskeletle değiştir:

- [ ] **Başlık + tek cümle pitch** — "cinema+: ruh haline göre film/dizi keşfi, swipe ile puanlama ve arkadaşlarınla sosyal öneri."
- [ ] **Ekran görüntüleri / GIF** — 3-4 ekran (Keşfet, Swipe, Sosyal, Profil). Görsel, README'nin en ikna edici kısmı.
- [ ] **Özellikler** — mood tabanlı keşif, 4'lü puanlama, eşleştir/birlikte modu, offline-first sync, sosyal ağ, TR/EN, koyu/açık tema.
- [ ] **Mimari** — `Flutter (Riverpod) → PHP REST API → MySQL`, offline-first SQLite cache. Bir diyagram cümlesi yeter.
- [ ] **Kurulum** — `flutter pub get`, TMDB API anahtarı nasıl verilir, `flutter run`.
- [ ] **Backend kurulumu** — `backend/README.md`'ye link + `config.php` ve migration adımı.
- [ ] **Test** — `flutter test`, coverage komutu.
- [ ] **Teknoloji yığını** — Flutter, Riverpod, sqflite, PHP 8.4, MariaDB, TMDB.
- [ ] **Lisans** — `LICENSE` dosyası ekle (MIT öneri).
- [ ] **CI rozeti** — workflow kurulunca.

### B2. Commit mesajı disiplini (Conventional Commits)

Mevcut geçmiş: `hata`, `duzelt`, `son hata`, `sayi balon`, `guncelle`. Bunlar geçmişi okunmaz yapıyor. Bundan sonrası için **Conventional Commits**:

```
<tip>(<kapsam>): <özet>     ← 50 karakteri geçme, emir kipi

<gövde: neden, ne değişti — opsiyonel>
```

Tipler: `feat` (yeni özellik), `fix` (hata), `refactor`, `perf`, `style` (biçim), `test`, `docs`, `chore`, `ci`.

Senin son commit'lerinin düzgün karşılığı:

| Eski | Doğrusu |
|---|---|
| `sayi balon` | `feat(social): istek sekmesine bekleyen sayı rozeti ekle` |
| `hata gider` | `fix(sync): last-write-wins çakışmasında silmeyi koru` |
| `guncelle` | `refactor(theme): renkleri AppColors token'larına taşı` |
| `social` | `feat(social): arkadaşlık ve aktivite akışı` |
| `guvenlik` | `fix(backend): friend request'i transaction'a al` |

- [x] Bu kuralı `CONTRIBUTING.md`'ye yaz (tek başına çalışsan bile gelecekteki sen için).
- [ ] İstersen `commitlint` + Husky ile zorunlu kıl (opsiyonel).

> Geçmişi geri yazma (`rebase`) tek başına bir projede gereksiz risk; kuralı **bundan sonrası** için uygula yeter.

### B3. Sürümleme & changelog

- [ ] **Semantic Versioning** — `pubspec.yaml`'daki `version: 1.0.0+1` ile uyumlu git tag'leri (`v1.0.0`).
- [ ] Yayın yaptıkça `git tag -a v1.x.x -m "..."`.
- [ ] `CHANGELOG.md` — "Keep a Changelog" formatı; `feat`/`fix` commit'lerden beslenir.

### B4. Dal (branch) stratejisi

- [ ] `main` daima yeşil (CI geçen) ve yayınlanabilir olsun.
- [ ] İş başına kısa ömürlü dal: `feat/social-block`, `fix/sync-delete`. PR ile birleştir.
- [ ] `main`'e branch protection: CI zorunlu + (varsa) review.

### B5. Repo temizliği

- [ ] `.gitignore` denetle — `build/`, `.dart_tool/`, `.idea/`, backend `config.php`, `coverage/` dışarıda mı? (Çalışma alanında `build/` ve `.dart_tool/` görünüyor, izlenmediğinden emin ol.)
- [ ] Kök dizindeki `flutter_01.png` (0 bayt) gibi artıkları sil.
- [ ] Sırlar repoda olmasın — TMDB anahtarı, JWT secret, DB bilgileri yalnız sunucu config'inde.
- [ ] `.github/` altına PR şablonu + (opsiyonel) issue şablonu.

### B6. (Opsiyonel) Otomasyon cilası

- [ ] **Pre-commit hook** — commit öncesi `dart format` + `flutter analyze`.
- [ ] **Dependabot** — bağımlılık güncellemeleri için.
- [ ] **Release workflow** — tag atınca otomatik APK/AAB build.
- [x] **Android release workflow** — `.github/workflows/android-release.yml` (manuel dispatch + `v*` tag).

---

## ÖZET KONTROL LİSTESİ (asgari "9+" paketi)

1. [x] `sync_service` + `api_service` testleri yazıldı
2. [x] CI workflow'u push/PR'da test+analyze çalıştırıyor
3. [x] Backend için en az `Social` + `Jwt` PHPUnit testi
4. [ ] README gerçek içerikle yeniden yazıldı (+ekran görüntüsü)
5. [x] Conventional Commits kuralı `CONTRIBUTING.md`'de, bundan sonra uygulanıyor
6. [ ] `LICENSE` + `.gitignore` denetimi + artık dosyalar silindi

Bu altısı tamamlanınca repo, koduyla aynı olgunluk seviyesine gelir.
