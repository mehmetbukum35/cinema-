# cinema+ — Kapsamlı Uygulama Analizi (2. Tur)

*Tarih: 14 Temmuz 2026 — Yöntem: kaynak kodun statik incelemesi (Flutter servis/provider katmanı satır satır, backend tüm src/), 5 Temmuz raporundaki bulguların kod üzerinde tek tek doğrulanması, `flutter analyze` + tam test takımlarının çalıştırılması.*

**Doğrulama durumu:** `flutter analyze` → 0 sorun. Flutter testleri → **199/199 geçti**. PHP testleri → **165/165 geçti** (551 assertion). Çalışma zamanı performansı (FPS/bellek) yine ölçülmedi; o alandaki tespitler kod deseninden çıkarımdır.

> **Güncelleme (aynı gün):** Bölüm 8'deki öncelik listesinin 1-6. maddeleri + ölü kod temizliği (madde 8), e-posta marka düzeltmesi ve `/me`'ye `apple_sub` eklenmesi (madde 9) uygulandı — ayrıntılar `CHANGELOG.md` [Unreleased] bölümünde. Test durumu düzeltmeler sonrası: Flutter 200/200, PHP 167/167.

---

## 0. 5 Temmuz Raporunun Karnesi — Ne Kapatıldı?

Önceki raporun **kritik ve yüksek öncelikli maddelerinin tamamına yakını kapatılmış** ve düzeltmeler kodda doğrulandı:

| Eski bulgu | Durum |
|---|---|
| 26 sessiz `catch (_)` (10'u boş) | ✅ **5'e indi** (1 boş kaldı — `my_reviews_screen.dart:49`); kalanlar gerekçeli best-effort |
| Swipe overlay yeşil/turuncu uyumsuzluğu | ✅ Overlay artık `c.rIyi`/`c.rBerbat` puan renklerini kullanıyor |
| `rate()` hatasında geri bildirim yok | ✅ `swipe_screen._rate` SnackBar gösteriyor |
| `db_helper` mobilde sessiz in-memory fallback | ✅ Android/iOS'ta `rethrow` (db_helper.dart:55-58) |
| Rate-limit `/tmp` dosyaları | ✅ DB tablosuna taşındı (`Helpers.php::rate_limit`) |
| Backend merkezi loglama yok | ✅ `cinema_error()` (uid+route+IP bağlamlı) |
| 117 inline `isTr ?` çeviri üçlüsü | ✅ **3'e indi** (kalanlar URL dil parametresi — meşru); `lib/l10n/tr.dart` + `en.dart` katmanı kuruldu |
| textScaler 1.15 kilidi | ✅ 1.3'e çıkarıldı (main.dart:151-154) |
| HTTP timeout belirsizliği | ✅ ApiService 20 sn, TmdbService 12 sn timeout |
| `TMDB_API_KEY` kalıntı hata yolları | ✅ Silindi |
| `Image.network` karışık kullanımı | ✅ Kalmadı |
| IndexedStack altında 5 eşzamanlı ticker | ✅ Her sekme `TickerMode(enabled: _tab == n)` ile sarıldı; `CinematicBackground`/`Shimmer` artık `disableAnimations`'a saygılı |
| Prod URL'nin sessiz default'u | ✅ `AppConfig.warnIfProductionApiWithoutDefine()` |
| God-class ekranlar | 🟡 Kısmen: swipe (1085→ana dosya + 9 widget) ve search bölündü; `movie_detail_sheet` 1.235, `onboarding` 1.220, `results` 1.068 satır hâlâ büyük |
| `Social.php` monoliti | ✅ 9 trait'e bölündü (facade 32 satır) |
| Dev fragman TR→EN çift isteği | ✅ EN sonucu TR anahtarına cache'leniyor |
| `Colors.blue` yabancı renk, emoji rozetler | ✅ `Colors.blue` kalmadı |

Bu tempo ve isabet oranı dikkate değer: 9 günde ~40 commit, iki kritik veri-kalitesi hatası ve tüm görünürlük eksikleri kapanmış.

---

## 1. Puan Tablosu

| Metrik | 5 Tem | 14 Tem | Not |
|---|---|---|---|
| Mimari | 78 | **84** | Trait bölünmesi, ekran refactor'ları, l10n katmanı |
| Kod kalitesi | 70 | **81** | Sessiz catch'ler ve çeviri ikiliği bitti; ölü kod kalıntıları var |
| Performans *(statik)* | 65 | **74** | Ticker/SWR iyi; DNA zinciri ve sync-bloklu yükleme düşürüyor |
| Güvenlik | 78 | **80** | DB rate-limit + refresh grace + hesap devri akışı; e-posta sızıntısı ve JWT rotasyonu düşürüyor |
| Hata yönetimi | 60 | **78** | Kalan risk: hata yolundaki korumasız `jsonDecode` |
| Erişilebilirlik | 55 | **75** | Semantics kapsama commit'leri + 1.3 scaler (görsel doğrulama yapılmadı) |
| Test edilebilirlik | 68 | **80** | 199+165 test, hepsi yeşil |
| Bakım kolaylığı | 70 | **80** | Teknik borç ~3/10'a indi |
| **Genel** | **71** | **79** | |

---

## 2. 🔴 En Önemli Yeni Bulgu: DNA Yayınlama Zinciri (mantık hatası + performans kaybı)

**Zincir:** `RecommendationEngine.invalidateCache()` → `PrefsService.clearDnaCache()` → bu üç anahtarı da siler: `last_dna_json`, `last_dna_input_hash` **ve `last_published_dna_hash`** (prefs_service.dart:883-888).

`SyncService._performSync` her sync sonunda koşulsuz `invalidateCache()` çağırıyor (sync_service.dart:360) ve ardından `_autoPublishDnaBackground()` çalışıyor. Sonuç, **her sync'te**:

1. DNA cache'i silindiği için `TasteDnaService.generate()` sıfırdan hesaplıyor (DB taraması + 20'ye kadar seed'in keyword listesi),
2. `lastPublishedHash` silindiği için `currentHash != lastPublishedHash` her zaman doğru → **veri değişmese bile `POST /social/dna` sunucuya yeniden gönderiliyor**.

Sync ise sık tetikleniyor: her swipe (5 sn debounce), watchlist ekleme/çıkarma, watchlist/stats ekran yüklemeleri. Yani hash mekanizmasının tüm amacı ("değişmediyse yayınlama") fiilen devre dışı. Ek yük: cihazda gereksiz hesap, sunucuda gereksiz UPDATE, `social_dna` rate-limit bütçesinin (varsayılan 20/dk) boşa tüketilmesi.

**Çözüm:** `clearDnaCache()` yayın hash'ini silmesin (yalnızca `last_dna_json` + `last_dna_input_hash`); `last_published_dna_hash` yalnızca `clearAuthData()`'da temizlensin. Tek satırlık ayrım, zincirin tamamını düzeltir.

İlgili ikinci israf: `watchlistProvider.load()` her çağrıda `invalidateCache(isNegativeChange: false)` yapıyor (watchlist_provider.dart:22-24) — sync zaten invalidate ediyor; bu çağrı fazlalık.

---

## 3. Mantık Hataları ve Kırılgan Sözleşmeler

1. 🟠 **Hata sözleşmesi metin tabanlı:** İstemci, backend'in *Türkçe hata cümlelerini* birebir eşliyor (`auth_provider._mapBackendError` ~30 satırlık string switch; `api_service._throwRateLimited` aynı desen). En riskli örnek: `'E-posta adresi doğrulanmamış.'` cümlesi **doğrulama ekranına yönlendirme akışını** tetikliyor (auth_provider.dart:193-198). Backend'de bir yazım düzeltmesi bu akışı sessizce bozar. *Çözüm:* backend `['error' => msg, 'code' => 'email_unverified']` gibi makine anahtarı da dönsün; istemci yalnızca `code`'a baksın.

2. 🟠 **Hata yolunda korumasız `jsonDecode`:** `api_service.dart`'ta ~25 metod hata durumunda `jsonDecode(response.body) as Map<String, dynamic>` yapıyor. Paylaşımlı hosting 503/504'te **HTML** hata sayfası döndürdüğünde bu `FormatException` fırlatır — kullanıcı `ApiException`'ın okunur mesajı yerine ham format hatası görür. Güvenli `_decodeJsonMap` zaten yazılmış ama yalnızca 3 metodda kullanılıyor. *Çözüm:* tüm decode'ları `_decodeJsonMap`'e geçirin (mekanik, düşük riskli değişiklik).

3. 🟡 **`_sanitizeList`'in `forceEnforce` parametresi hiçbir şey yapmıyor** (tmdb_service.dart:1180 — gövdede hiç okunmuyor). `sanitizeListForTesting` bu parametreyi geçiriyor; test, var olmayan bir davranışı test ettiğini sanıyor. Ya davranışı gerçekten ekleyin ya parametreyi silin.

4. 🟡 **Cache'lenmiş `Movie` nesneleri paylaşımlı-mutable:** `TmdbService._similarCache/_recommendationsCache` aynı `Movie` **örneklerini** döndürür; `RecommendationEngine.fetchSeedCandidates` ve `pickExplorationCandidates` bu paylaşılan nesnelerin `recoReason/recoSource` alanlarını yerinde yazar (recommendation_engine.dart:366-377, 429-435). Swipe kuyruğundaki bir kartın rozet gerekçesi, sonradan çalışan bir browse sıralamasıyla değişebilir; telemetri kaynağı da (`recoSource`) yarışa açık. *Çözüm:* cache'ten dönerken kopya listesi (`List.of`) + atıf alanlarını kopyada yazmak, ya da atıfları `Movie` dışında bir `Map<key, Attribution>`'da taşımak.

5. 🟡 **`getWatchProviders` bölgeyi sabitliyor:** `resultsByRegion?['TR']` (tmdb_service.dart:529) — sınıfın `_region` alanı dururken. Bugün `_region` hep 'TR' olduğu için görünmez; EN kullanıcılar veya gelecekte bölge desteği eklendiğinde ilk kırılacak yer.

6. 🟡 **`buildUserKeywordVector`:** yorum "en son 25 oylama" diyor, kod 15 alıyor (recommendation_engine.dart:193-197). Küçük ama sözleşme kayması sinyali.

7. 🟡 **`sendFriendRequest` aramasında normalizasyon yok:** e-postalar DB'ye lowercase yazılıyor ama arama sorgusu lowercase'lenmiyor (FriendsTrait.php:9-14). MySQL'in ci collation'ı bugün örtüyor; SQLite testlerinde ve olası collation değişiminde davranış farklılaşır. `strtolower(trim(...))` yeterli.

---

## 4. Güvenlik / Gizlilik

**Güçlü kalanlar:** timing-safe JWT + refresh rotasyonu ve **60 sn grace penceresi** (Auth.php:574-583 — mobil için incelikli çözüm), bcrypt + sahte-hash timing eşitleme, doğrulanmamış hesabın Google/Apple girişinde güvenli devri (parola sıfırlama + oturum düşürme), iki katmanlı adult filtresi, küfür/spam filtresi + topluluk şikayeti + moderasyon paneli, sırların gitignore ile korunması (doğrulandı: `Config.php` ve `*-service-account.json` izlenmiyor).

**Yeni/kalan riskler:**

| Risk | Seviye | Detay |
|---|---|---|
| **`GET /social/friends` e-posta sızdırıyor** | 🟠 | `friends`, `pending_received` **ve `pending_sent`** listeleri `u.email` içeriyor (FriendsTrait.php:132-170). Saldırı: kullanıcı adını ara → istek gönder → pending_sent'ten hedefin e-postasını oku. **UI e-postayı hiçbir yerde göstermiyor** (grep doğrulandı) — alan yanıttan tamamen çıkarılabilir; KVKK açısından da doğrusu bu. |
| JWT secret rotasyonu / `kid` yok | 🟡 | 5 Temmuz'dan taşınan madde; hâlâ geçerli. |
| `/me` yanıtında `apple_sub` yok, Apple bağlantı kaldırma ucu yok | 🟡 | Google için ikisi de var (Auth.php:600-634). Apple girişli kullanıcı profil ekranında bağlantı durumunu /me'den tazeleyemez; simetri eksik. |
| `getFriends`/`activity` sayfalama yok | 🟢 | LIMIT'ler var; mevcut ölçekte yeterli. |

---

## 5. Performans Kayıpları

1. 🟠 **Watchlist/istatistik ekranı sunucu sync'ini BEKLİYOR:** `WatchlistNotifier.load()` önce `performSync()`'i `await` ediyor, yerel listeyi ancak ondan sonra okuyor (watchlist_provider.dart:16-31; `StatsNotifier.load` aynı). Yavaş ağda kullanıcı, cihazında hazır duran veriye 20 sn'ye kadar (timeout) spinner arkasından bakıyor. Offline-first mimarinin vaadinin tersi. *Çözüm:* önce yerelden `state = AsyncValue.data(list)`, sync arkada; dönünce tazele.

2. 🟠 **`loadTasteScores` N+1 HTTP:** her arkadaş için ayrı `GET /social/match/taste/{id}` — 20 arkadaş = seri 20 istek, her `loadFriends` sonrası (social_provider.dart:251-267). Backend'de `getFriends` yanıtına skorları gömmek ya da toplu `/social/match/taste` ucu tek istekte çözer.

3. 🟡 **İlk sync tek parça:** login sonrası `lastPush=0` → tüm yerel DB tek POST'ta gidiyor (overview metinleri dahil); sunucu tarafında kayıt başına SELECT+INSERT/UPDATE döngüsü (Sync.php:154-259, tablo başına 10k tavan). Binlerce puanı olan kullanıcıda paylaşımlı hosting `post_max_size`/zaman aşımı sınırına yaklaşır. Parça parça (ör. 500'lük) push güvenli olur.

4. 🟡 **`getTopProfiles` N+1 sorgu:** 20 profil × (2 korele alt sorgu + 1 poster sorgusu). Sınırlı olduğu için bugün sorun değil; yorum olarak işaretlemeye değer.

5. 🟡 **TmdbService bellek cache'leri sınırsız** (`_similarCache`, `_recommendationsCache`, `_keywordIdsCache`) — oturum boyu büyür. Uzun oturumda yüzlerce girdi olabilir; basit bir 200-girdi LRU tavanı yeter. TTL sabitleri de hâlâ ham milisaniye (43200000) — `Duration` sabitine çevrilmedi (eski 🟡 madde, duruyor).

6. 🟢 **Çifte sync coalescing:** hem `SyncService._syncFuture` hem `SyncNotifier._syncFuture` aynı korumayı yapıyor — zararsız ama tek yerde olmalı.

---

## 6. Gereksiz Durumlar / Ölü Kod

1. **`PrefsService.getMovieRating` ölü kod** (prefs_service.dart:836-846) — hiçbir yerden çağrılmıyor; üstelik tüm ratings'i çekip O(n) tarıyor (aynı iş için indeksli `getRating` var). Silin.
2. **`_apiKey => ''` mirası:** tmdb_service'te her parametre haritasına boş `'api_key'` ekleniyor, `_tmdbUri` geri atıyor; cache anahtarlarına da `api_key=` sızıyor (zararsız ama gürültü). Temizlik, cache anahtar sürümü v3 ile yapılabilir.
3. **`invalidateTasteVector`** geriye-uyumluluk sarmalayıcısı — çağıran kalmadıysa silinmeli.
4. **`SocialState.loading` tek bayrak, ~6 farklı işlemi temsil ediyor** (arkadaşlar, akış, kesişim, arkadaş aktivitesi, istekler…): bir ekranın yüklemesi diğerinin spinner'ını oynatabiliyor. `topProfilesLoading` için ayrışma zaten yapılmış — aynı desen geri kalanına da uygulanmalı.
5. **`AuthState.copyWith` tutarsız semantik:** `error` için sentinel deseni özenle kurulmuş, ama `user`/`accessToken` hâlâ `?? this` — null'a çekilemiyor (logout `state = AuthState()` ile dolanıyor). Aynı sınıf içinde iki farklı copyWith felsefesi kafa karıştırır.
6. **İki rakip tür-ağırlık modeli:** `getLikedGenreIds` (1/3/2 ağırlık, decay yok — discover filtresini besliyor) vs `getGenreWeights` (decay'li, negatif cezalı — benzerlik skorunu besliyor). Bilinçliyse bir yorumla belgelenmeli; değilse tek modele inilmeli.

---

## 7. Tutarsızlıklar

1. **Marka üçlemesi sürüyor:** paket `ne_izlesem`, uygulama "Cinema+ | What to Watch?", **doğrulama e-postaları hâlâ "Ne İzlesem Üyelik Doğrulama" başlığıyla gidiyor** (Auth.php:176, 741) — kullanıcıya dokunan en görünür tutarsızlık bu; e-posta şablonları öncelikli.
2. `matchScore` iki farklı ölçek gösteriyor: kişisel skor 40-98 sigmoid, fallback `voteAverage*10` 1-99 (movie.dart:79-80). Aynı rozette iki dağılım — kullanıcı 72'nin hangi anlama geldiğini bilemez.
3. `Tmdb::filterResponse` `json_encode`'u `JSON_UNESCAPED_UNICODE`'suz çağırıyor (Tmdb.php:134) — projenin geri kalanıyla çelişik; Türkçe karakterler \u escape'li gider (işlevsel zarar yok).
4. `rate_limit` anahtarı kullanıcı-bazlı kovalarda bile IP içeriyor (`sync_u5-1.2.3.4`) — mobilde IP değişince pencere sıfırlanıyor; "kullanıcı bazlı sınır" yorumuyla tam örtüşmüyor.
5. `respondThenContinue` deseni `register`/`resendVerification`'da ortak metod, `forgotPassword`'de kopya inline blok (Auth.php:681-690) — aynı iş iki üslup.

---

## 8. Öncelik Sırası

**🔴 Bu hafta**
1. `clearDnaCache`'ten `last_published_dna_hash`'i ayırın (Bölüm 2 — tek satır, her sync'teki gereksiz üretim + POST biter).
2. `GET /social/friends` yanıtından `email` alanını çıkarın (Bölüm 4 — istemci zaten kullanmıyor, kırılma yok).

**🟠 Bu sprint**
3. Backend hatalarına makine-okur `code` alanı + istemcide metin eşlemesinin emekliye ayrılması.
4. `api_service` hata yollarının `_decodeJsonMap`'e geçirilmesi.
5. Watchlist/stats: önce yerel veri, sync arkada.
6. Taste-match skorlarının tek istekte dönmesi.

**🟡 Sıradaki**
7. Movie atıf alanlarının paylaşımlı-mutasyon sorunu; cache kopyalama.
8. Ölü kod temizliği (getMovieRating, forceEnforce, invalidateTasteVector, _apiKey mirası).
9. E-posta şablonlarında marka güncellemesi; `/me`'ye apple_sub + Apple unlink ucu.
10. `movie_detail_sheet` / `onboarding` / `results` ekranlarının bölünmesi (kalan god-class'lar).
11. JWT `kid`/rotasyon desteği (taşınan madde).

---

## 9. Sonuç

İki tur arasındaki fark bir olgunlaşma hikâyesi: önceki raporun "görünürlük eksikliği" teması (sessiz hatalar, geri bildirimsiz kayıplar) fiilen kapanmış; test tabanı büyümüş ve tamamı yeşil; mimari borç (monolit ekranlar/sınıflar) sistemli biçimde eritiliyor. Bugünkü sorunlar artık "yanlış davranış" değil, ağırlıkla **verimsizlik ve sözleşme kırılganlığı** kategorisinde — en ciddi ikisi (DNA yayın zinciri, arkadaş listesindeki e-posta alanı) toplamda yarım günlük iş. Genel puan **71 → 79**; ilk iki 🔴 madde ve hata-kodu sözleşmesi kapanırsa 82-83 bandı gerçekçi.
