# cinema+ (Ne İzlesem?) — Kapsamlı Uygulama Analizi

*Tarih: 5 Temmuz 2026 — Yöntem: kaynak kodun statik incelemesi, git geçmişi taraması, repodaki `UI_UX_ANALIZ.md` (2 Temmuz 2026) bulgularının kod üzerinde doğrulanması.*

**Yöntem ve sınırlar (dürüstlük notu):** Ekran görüntüsü verilmediği için görsel değerlendirme kod üzerinden yapıldı; çalışma zamanı performansı (FPS, bellek) ölçülmedi — bu alanlardaki tespitler kod desenlerinden çıkarımdır ve öyle işaretlendi. Son commit'in (9666f63) `UI_UX_ANALIZ.md`'deki bazı maddeleri zaten düzelttiği doğrulandı; düzeltilmiş şeyler tekrar eleştirilmedi.

---

## 1. Genel Mimari — 78/100

**İyi olanlar:**
- Katmanlama net: `models / providers / services / screens / theme / widgets`. Servisler Riverpod provider'ları üzerinden erişiliyor (`lib/services/providers.dart`) — DI fiilen var, testlerde mock'lanabiliyor (13 test dosyası bunu kanıtlıyor).
- TMDB proxy mimarisi doğru bir karar: API anahtarı yalnızca sunucuda (`backend/src/Tmdb.php`), client'ta sıfır secret.
- İki yönlü delta sync tasarımı (`sync_service.dart` ↔ `backend/src/Sync.php`) offline-first için sağlam: transaction'lı uygulama, eşzamanlı sync çağrılarının tek Future'a coalesce edilmesi (`sync_service.dart:12-28`).
- Backend'de framework'süz minimalist router bilinçli bir tercih (paylaşımlı hosting kısıtı, `Jwt.php:3`'teki yorum bunu açıklıyor) ve mevcut ölçek için savunulabilir.

**Kötü olanlar:**
- 🟠 **God-class ekranlar:** `movie_detail_sheet.dart` 2.128, `profile_screen.dart` 2.012, `match_screen.dart` 1.762, `browse_screen.dart` 1.656 satır. Ekran katmanı toplam ~15.5k satır ve iş mantığı, UI ve formatlama iç içe. Provider'lar temizken ekranlar dev.
- 🟠 **`Social.php` monoliti:** 667 satır, 19 public metod; arkadaşlık, aktivite akışı, öneri, puanlama, web render tetikleme tek sınıfta. Shotgun surgery riski.
- 🟡 Widget deseni karışık: 15 ekran `StatefulWidget`, 13'ü `ConsumerWidget/ConsumerStatefulWidget`. Seçim kuralı görünmüyor.
- 🟡 `api/index.php` 275 satırlık switch-router (28 route). Bugün okunabilir; 50+ route'ta bakım sorunu olur. Middleware kavramı yok — CORS, istek loglama, response zarfı eklemek her route'a dokunmayı gerektirir.

---

## 2. Kod Kalitesi — 70/100

- 🔴 **Sessiz hata yutma — en yaygın kod sorunu:** `lib/` altında **26 adet `catch (_)`**, bunların **10'u tamamen boş** (`catch (_) {}`). Örnek: `api_service.dart`'ta logout sırasında ağ hatası sessizce yutuluyor; `notification_service.dart`'ta foreground bildirim gösterimi başarısız olursa iz yok. *Neden problem:* prod'da "bildirim gelmiyor" şikâyeti teşhis edilemez. *Çözüm:*
  ```dart
  } catch (e, st) {
    debugPrint('notif foreground fail: $e');
    // ileride: crashlytics.recordError(e, st);
  }
  ```
  Bilinçli best-effort ise en azından yorumla gerekçelendirin.
- 🟠 **117 adet inline `isTr ? '...' : '...'` üçlüsü** — 649 satırlık düzgün bir `localization_service.dart` varken iki çeviri deseni yarışıyor. Yeni dil eklemek şu an fiilen imkânsız (üçlüler ikili). Tek `get()` desenine toplanmalı.
- 🟡 Magic number'lar: cache TTL'leri milisaniye sabiti (43200000 yerine `const Duration(hours: 12)`), oy eşiği 15/3, rating skalası 0-3 hem Dart'ta hem PHP'de (`Social.php:506`) sabit — paylaşılan sözleşme tek yerde tanımlı değil.
- 🟡 `Movie.fromJson` (`movie.dart:28-64`) `isTV` için 1/'1'/true/param dört biçimi kontrol ediyor — API sözleşmesinin gevşek olduğunun belirtisi. Backend'in tek tip döndürmesi kökten çözüm.
- ✅ Artı: kod tabanında **gerçek TODO/FIXME neredeyse yok**; ölü kod izine rastlanmadı; PHP tarafında `declare(strict_types=1)` tutarlı.
- 🟡 Kalıntı kod: `results_screen.dart:582` ve `search_screen.dart:256`'da artık geçersiz olan `TMDB_API_KEY` hata mesajı kontrolleri duruyor (anahtar artık client'ta yok) — yanıltıcı, silinmeli. `CONTRIBUTING.md` de hâlâ eski dart-define akışını anlatıyor.

---

## 3. Performans Analizi — 65/100 *(statik çıkarım, ölçüm değil)*

| Sorun | Etki | Öncelik | Çözüm |
|---|---|---|---|
| `CinematicBackground`: 7 ekranda 14 sn sonsuz döngülü tam ekran `CustomPaint`; `MainShell` `IndexedStack` kullandığı için **5 sekmenin ticker'ı aynı anda çalışıyor** (`cinematic_background.dart`) | Pil tüketimi, her karede uyanan controller'lar | 🟠 | Sekme dışı ekranlarda `TickerMode(enabled: false)`; `disableAnimations`'ta `animate:false` |
| Fragman aramada TR→EN iki ardışık istek (`tmdb_service.dart:354-407`), sonuç cache'lenmiyor | Detay her açılışta 2 istek | 🟡 | Tek istekle çöz veya sonucu TTL cache'e yaz |
| `browse_screen`'de `SingleChildScrollView` içine gömülü çok sayıda `ListView.builder` (385, 431, 463, 498...) | Layout maliyeti; liste büyürse jank | 🟡 | `CustomScrollView` + `SliverList` |
| `social_screen.dart:757, 1089`'da `Image.network` — projenin geri kalanı `CachedNetworkImage` | Önbelleksiz tekrar indirme | 🟢 | CachedNetworkImage'a geçir |
| Keyword vektörü her `init()`'te yeniden kuruluyor, Future'larda timeout yok (`swipe_provider.dart:122-150`) | Bir istek asılırsa öneri hesabı bloklanır | 🟢 | Memoize + `Future.timeout` |

✅ Artılar ciddi: TTL katmanlı cache + **stale-while-revalidate** (`tmdb_service.dart:665-775`) bu ölçekte bir uygulama için sofistike; token refresh coalescing gereksiz paralel refresh'i engelliyor; sync coalescing var.

---

## 4. Güvenlik Analizi — 78/100

**Doğrulanmış güçlü temeller** (birçok üretim uygulamasından iyi):
- JWT: `hash_equals` ile timing-safe imza kontrolü + `exp` kontrolü (`Jwt.php:22,25`). Algoritma karışıklığı saldırısına da kapalı — header'daki `alg` hiç okunmuyor, imza her zaman HS256 ile hesaplanıyor.
- Parolalar bcrypt; refresh token'lar DB'de SHA-256 hash + kullanımda rotasyon + parola değişiminde iptal (`Auth.php:76-97, 139, 341`).
- SQL injection fiilen kapalı: her yerde PDO prepared statement, `ATTR_EMULATE_PREPARES=false` (`Db.php:16`).
- XSS: kullanıcı verileri `htmlspecialchars` ile escape (`SocialWebRenderer.php:49-50`, template'ler).
- Forgot-password'de user-enumeration'a karşı sabit-cevap + arka planda işleme (`Auth.php:152-177`).
- Client'ta token'lar `flutter_secure_storage`'da; eski plaintext'ten migration yazılmış (`prefs_service.dart:493-533`).
- **Git geçmişi tarandı: `Config.php`, keystore, service-account hiçbir zaman commit edilmemiş.** Gitignore doğru kurulmuş.

**Riskler:**

| Risk | Seviye | Detay |
|---|---|---|
| Rate limit dosyaları `sys_get_temp_dir()`'de (`Helpers.php:48`) | 🟠 Orta | Paylaşımlı hosting'de izolasyon garantisi yok; başka süreç silebilir/okuyabilir. DB tablosuna taşıyın. |
| JWT secret rotasyonu yok, `kid` desteği yok | 🟡 Orta | Secret sızarsa tüm oturumları öldürmeden rotasyon imkânsız. Header'a key-id ekleyin. |
| Prod URL Flutter'da default (`app_config.dart:3-5`) | 🟡 Orta | dart-define unutulan dev build prod DB'ye yazar. Debug modda default'u boş bırakıp fail-fast yapın. |
| CSRF | 🟢 Düşük | API token-based olduğu için klasik CSRF yüzeyi dar; public web profil sayfaları salt-okunur olduğu sürece sorun değil. |
| Hassas veri loglama | 🟢 | Belirgin bir token/parola loglama izi görülmedi. |

---

## 5. Hata Yönetimi — 60/100

- ✅ `ApiException` ile durum kodu + mesaj eşlemesi, 401→sessiz refresh→retry döngüsü (`api_service.dart:59-135`) iyi tasarım.
- ✅ Backend'de transaction + rollback disiplini var (`Sync.php:72-86`).
- 🔴 26 sessiz catch (yukarıda) — en büyük eksik.
- 🟠 `swipe_provider.dart`'ta `rate()`/`loadMore()` başarısızlığında **kullanıcıya hiçbir geri bildirim yok**: kullanıcı puan verir, sync sessizce düşer, kullanıcı bilmez. En azından SnackBar + otomatik retry kuyruğu gerekli (offline kuyruk zaten SQLite'ta var, eksik olan görünürlük).
- 🟠 Backend'de merkezi loglama yok; `error_log()` bağlamsız (kullanıcı id, route, correlation id yok). Basit bir `Logger::error($route, $uid, $e)` sarmalayıcısı bile büyük fark yaratır.
- 🟡 `db_helper.dart:50`: SQLite açılamazsa **sessizce in-memory mock'a düşüyor** — kırık migration prod'da fark edilmez, kullanıcı verisi uçucu belleğe yazılır. Bu fallback yalnızca test/web için sınırlandırılmalı, mobilde hata fırlatmalı.
- Timeout/offline: HTTP timeout'larının varlığı doğrulanmadı — **emin değilim**, kontrol edilmeli (`http` paketi default'ta timeout'suz).

---

## 6–7. UI & UX Analizi — UI 72/100, UX 70/100

*(Ekran görüntüsü yok; repodaki WCAG-hesaplı denetim + kod doğrulamasına dayanıyor. Not: 5 Temmuz'daki 9666f63 commit'i puan butonu kontrastını ve bazı lokalizasyonları düzeltmiş — doğrulandı, tekrar sayılmıyor.)*

**Hâlâ geçerli olanlar:**
- 🔴 **textScaler `1.15`'e kilitli** (`main.dart:127`). Taşmayı önlüyor ama `UI_UX_ANALIZ.md`'nin önerdiği 1.3 yerine 1.15 seçilmiş — %130+ sistem yazısı kullanan yaşlı/az gören kullanıcıya fiilen "büyük yazı yok" deniyor. Sabit yükseklikler (`height: 64/48/275`) responsive yapılıp clamp 1.3'e çıkarılmalı; 9-11px fontlar (58 yer) tasfiye edilmeli.
- 🟠 **Dokunma geri bildirimi kapalı:** `splashFactory: NoSplash` + transparan highlight + yaygın `GestureDetector`. Haptic kapalı cihazda "bastım mı?" belirsizliği. 80-120ms `AnimatedScale` pressed durumu ekleyin.
- 🟠 **Swipe jest-renk uyumsuzluğu:** sağa kaydırma `rate(2)` (İyi/turuncu) veriyor ama overlay yeşil "LIKED" gösteriyor (`swipe_screen.dart:637,1078`). Kullanıcı Harika verdiğini sanıyor — **veri kalitesini de bozan** bir UX hatası (öneri motoru yanlış sinyal alıyor).
- 🟡 Dokunma hedefleri: browse başlık ikonları 36px + 2px aralık (`browse_screen.dart:604-757`), arama temizle ikonu ~18px. Standart: ≥44-48px.
- 🟡 Açık temada `browse_screen._skeleton()` koyu tema sabitleri kullanıyor → iskelet simsiyah bloklar (`browse_screen.dart:326-464`).
- 🟡 `matchScore` rozeti bağlamsız yeşil sayı — yeni kullanıcı "87 ne?" der. İlk kullanımda tooltip/coach-mark hak ediyor.
- 🟢 `login_screen`'de `autofillHints` yok — parola yöneticileri çalışmıyor; iki satırlık iş.

**İyi olanlar:** tasarım token disiplini (`ThemePalette` + `context.c`), 150-320ms easeOut animasyon tutarlılığı, gerçek skeleton ekranlar, ayrımlı hata ekranları (bağlantı/401/genel + retry), swipe'ın buton alternatifi olması, bilinçli haptic dili. Bunlar sektör ortalamasının üstünde.

---

## 8. Tutarsızlıklar

1. İki çeviri deseni (`get()` vs 117 inline üçlü) — kod standardı tutarsızlığının en büyüğü.
2. `Image.network` vs `CachedNetworkImage` karışık kullanımı.
3. Emoji ('🎬','📺','🌐') vs ikon karışımı — "premium sinematik" kimlikle çelişiyor.
4. `movie_detail_sheet.dart:384` 'Dizi' rozeti `Colors.blue` — palette olmayan tek yabancı renk.
5. Marka: `MaterialApp.title` "Ne İzlesem?", repo/README "cinema+", paket adı `ne_izlesem` — üç isim dolaşıyor.
6. StatefulWidget/ConsumerWidget seçimi kuralsız.
7. Backend'de input trim bazı uçlarda var (`Auth.php:25,54`) bazılarında yok (`Social.php:18,93`).

---

## 9. Ürün Analizi

**Ne iyi:** "Karar felci" problemi gerçek ve swipe + sosyal sinyal (arkadaş aktivitesi, ortak izleme listesi, taste-match) kombinasyonu doğru tez. Delta sync ile offline çalışma, bu kategorideki çoğu rakipte yok.

**Eleştiriler:**
- **Dönüşümü en çok düşürecek nokta:** puanlama hatasının sessiz kaybı + swipe renk karışıklığı → öneri motoru yanlış beslenirse ürünün çekirdek vaadi ("sana ne izleyeceğini söyleyeyim") çöker.
- Sosyal özellikler arkadaş gerektiriyor; **cold-start** (arkadaşsız yeni kullanıcı) deneyimi kritik — arkadaş davet akışının (davet linki/deep link) sürtünmesizliği ağ etkisi için belirleyici.
- "Nerede izlenir?" bilgisi var — JustWatch'ın tüm değer önerisi bu. Daha görünür olmalı (kart üstünde platform rozeti).
- Eksik olabilecekler: bildirim tercihleri granülaritesi, izleme geçmişi dışa aktarma. Terk riski: swipe destesi bitince boş durum stratejisi kritik.

---

## 10. Görsel İyileştirme Önerileri

- Sarı/turuncu dolgulu butonlarda koyu metin (siyah/sarı 15:1) — kısmen yapıldı, açık temadaki altın metinler için `#7A5A20` seviyesine inin.
- Emoji rozetleri → `Icons.movie_outlined / tv_outlined` + tema rengi.
- Detay sheet'te ekstralar yüklenirken spinner yerine sabit yükseklikli bölüm iskeleti (içerik zıplamasını keser).
- Arama boş durumuna popüler arama chip'leri.
- Match skoru için ilk-kullanım coach-mark'ı + ikon.

---

## 11. Erişilebilirlik — 55/100 (en zayıf alan)

- Semantics kapsaması adalı: swipe(4), browse(9), profile(6) var; **movie_detail_sheet, search, social, watchlist, login: 0**. İkon-only butonlar (paylaş, fragman, öner) TalkBack'te anlamsız. En ucuz çözüm: `tooltip` (hem görsel hem semantik çözer).
- `CinematicBackground` ve `Shimmer` `disableAnimations`'ı yok sayıyor (vestibüler hassasiyet); oysa `swipe_screen._rate/_undo` kontrol ediyor — bilinç var, tutarlılık yok.
- textScaler 1.15 kilidi + 58 yerde 9-11px font.
- Kontrast ihlallerinin bir kısmı düzeltildi, açık tema altın metinler bekliyor.

---

## 12. Code Smells

**God Class:** `movie_detail_sheet`, `profile_screen`, `match_screen`, `browse_screen`, `Social.php` · **Long Method:** `browse_screen._skeleton()` (~140 satır), 200+ satırlık build metodları · **Magic Number:** TTL'ler, rating 0-3, oy eşikleri · **Duplicate Code:** 117 inline çeviri üçlüsü; backend'de çifte rate-limit stratejisi (dosya-IP + DB-attempt) · **Primitive Obsession:** rating'in int olarak dolaşması (enum/`Rating` value-type yok) · **Dead Code:** TMDB_API_KEY hata yolu kalıntıları · **Data Clumps:** `movie_id, is_tv` çifti her yerde beraber dolaşıyor — bir `TitleRef` tipi hak ediyor.

---

## 13. Test Edilebilirlik — 68/100

- ✅ 13 Flutter test dosyası (provider/servis/model/widget), mock altyapısı, `sqflite_common_ffi`; backend'de 46 test metodu; **CI'de coverage eşiği zorunlu (Flutter mantık katmanı ≥%50, PHP ≥%60) + ratchet notu** — bu disiplin nadirdir.
- 🟠 Eksikler: JWT saldırı testleri yok (imza kurcalama, `alg:none`, exp sınırı, refresh-token yeniden kullanımı — `JwtTest`'te 8 metod var ama saldırı senaryoları değil), Flutter'da integration test yok (auth akışı, offline→online sync, çakışma çözümü), `SyncTest` sadece 2 metod (last-write-wins çakışması test edilmemiş).
- 🟡 2.000 satırlık ekranlar widget-test edilemez boyutta — bölmek test edilebilirliği de açar.

---

## 14. Bakım Kolaylığı — 70/100

- ✅ README/CONTRIBUTING/API_VE_SEMA.md/UI_UX_ANALIZ.md — dokümantasyon ortalamanın çok üstünde. PHP'de Türkçe açıklayıcı yorumlar gerekçeli.
- 🟠 Yeni geliştirici servis katmanını hızla kavrar ama 2.000 satırlık bir ekrana özellik eklemek mayın tarlası. CONTRIBUTING.md güncel değil (TMDB_API_KEY).
- **Teknik borç: 4.5/10** — borç var ama izole (ekran katmanı + lokalizasyon); çekirdek (sync, auth, cache) temiz olduğu için faiz düşük.

---

## 15. Gelecekte Sorun Çıkaracak Noktalar

1. **Dosya tabanlı rate-limit** kullanıcı artışında ilk kırılacak parça (tmp temizliği, yarış koşulları).
2. **Switch-router** 50+ route'ta; middleware ihtiyacı (CORS, versiyonlama) doğduğunda yeniden yazım baskısı.
3. **JWT rotasyonsuzluğu:** ilk güvenlik olayında tüm kullanıcıları logout etmek zorunda kalırsınız.
4. **Aktivite/rating tablolarının büyümesi:** `getFriendSignals` `LIMIT 1000` ile çekiyor (`Social.php:639`) — arkadaş sayısı arttıkça sorgu maliyeti; index stratejisi migrations'ta gözden geçirilmeli.
5. **TMDB API değişiklikleri:** proxy tek geçiş noktası olduğu için iyi konumdasınız — bu bir artı.
6. **`isTr` üçlüleri:** üçüncü dil istendiği gün 117 nokta elle taranacak.

---

## 16. Rakip Karşılaştırması *(genel bilgi, doğrulanmış ölçüm değil)*

| Rakip | Onlarda olup sizde zayıf olan |
|---|---|
| **Letterboxd** | Derin sosyal profil, listeler, inceleme kültürü — yorum/inceleme tarafı daha sığ |
| **TV Time** | Bölüm-bazlı dizi takibi ve "sonraki bölüm" hatırlatması — dizi takibi başlık seviyesinde |
| **JustWatch** | Platform bazlı fiyat/kiralama bilgisi ve platform-öncelikli keşif — "nerede izlenir" var ama ikincil |
| **Trakt** | Açık API/entegrasyon ekosistemi, scrobbling |

**Fark:** swipe keşif + arkadaş taste-match + offline-first sync kombinasyonu — üçü bir arada rakiplerde yok. Odak tavsiyesi: bölüm takibi gibi TV Time alanına girmek yerine "arkadaşınla ne izleyeceğine 2 dakikada karar ver" (together/match) hattını derinleştirmek.

---

## 17. Önceliklendirme

**🔴 Kritik**
1. Sessiz `catch (_)` bloklarına log + `rate()` başarısızlığında kullanıcı geri bildirimi (veri bütünlüğü + teşhis)
2. Swipe overlay renk/puan uyumsuzluğu (yanlış veri üretiyor)
3. `db_helper` sessiz in-memory fallback'inin mobilde kapatılması (veri kaybı riski)

**🟠 Yüksek**
4. Rate-limit'i `/tmp`'den DB'ye taşımak
5. Dev ekranların bölünmesi (önce `movie_detail_sheet`)
6. textScaler 1.3 + sabit yüksekliklerin esnetilmesi
7. Lokalizasyonun tek desene toplanması
8. Backend merkezi loglama

**🟡 Orta**
9. JWT key-id/rotasyon desteği; JWT saldırı testleri
10. Dokunma hedefleri + pressed feedback + Semantics/tooltip kapsaması
11. `CinematicBackground` TickerMode/reduced-motion
12. Flutter integration testleri (auth + sync)

**🟢 Düşük**
13. TMDB_API_KEY kalıntıları, CONTRIBUTING güncelleme, autofillHints, emoji→ikon, `Image.network`→cached, fragman çift isteği

---

## 18. Sonuç Raporu

**En başarılı yönler:** güvenlik temelleri (JWT/bcrypt/prepared statements/secure storage — hepsi kod üzerinde doğrulandı), TMDB proxy mimarisi, SWR'li cache, delta sync, CI coverage disiplini, tasarım token sistemi, dokümantasyon kültürü.

**En büyük problemler:** God-class ekranlar, sistematik sessiz hata yutma, yarım lokalizasyon, erişilebilirlik açıkları.

**Kullanıcı deneyimini en çok bozanlar:** puanlama hatasının sessiz kaybı, swipe renk karışıklığı, dokunma geri bildirimi yokluğu, büyük yazı kullanıcılarında 1.15 kilidi.

**En kritik güvenlik sorunu:** kritik seviyede açık **yok** (bu nadirdir); en önemlisi `/tmp` rate-limit ve JWT rotasyonsuzluğu — ikisi de orta seviye.

**En kritik performans sorunu:** IndexedStack altında 5 eşzamanlı animasyon ticker'ı (pil).

**İlk 10 düzeltme:** yukarıdaki 🔴1-3 + 🟠4-8 + JWT testleri + Semantics/tooltip.

| Metrik | Puan |
|---|---|
| Teknik borç | **4.5/10** (yönetilebilir, izole) |
| Kod kalitesi | **70** |
| Mimari | **78** |
| UI | **72** |
| UX | **70** |
| Performans | **65** *(statik çıkarım)* |
| Güvenlik | **78** |
| Erişilebilirlik | **55** |
| Bakım kolaylığı | **70** |
| **Genel** | **71/100** |

**Özet yargı:** Temelleri doğru atılmış, güvenlik ve altyapı kararları çoğu hobi projesinin (ve epey ticari projenin) üstünde bir kod tabanı. Zayıflıklar "yanlış mimari" değil, "büyüyen ekran katmanının disiplinsizleşmesi + görünürlük eksikliği (log/hata geri bildirimi) + erişilebilirliğin sona bırakılması" kategorisinde — hepsi kademeli, riski düşük refactor'larla kapatılabilir. En acil iş listesi bir sprint'lik: sessiz catch'ler, swipe rengi, rate hatası geri bildirimi ve rate-limit'in DB'ye taşınması.
