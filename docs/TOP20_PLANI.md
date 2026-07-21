# Top 20 — Kişisel Panteon + Topluluk Popüler Listeleri (Uygulama Planı)

> Durum: **Faz 1 + Faz 2 uygulandı.** Kişisel Top 20 (Film + Dizi) ve topluluk
> "Popüler Top 20" (cron önhesaplı) hazır. **Dağıtım için kalan:** sunucuda
> migration `022_popular_titles.sql` çalıştırılmalı; cron zaten `maintenance.php`'yi
> çağırdığı için ek cron kaydı gerekmez (recompute o adıma bindi).

## Kararlar (kesin)

- **İki ayrı liste:** Top 20 **Film** + Top 20 **Dizi** (sekmeli).
- **Depolama:** yeni tablo yok — mevcut `favorites` altyapısı genişletilir.
- **Topluluk sıralaması:** basit **favori sayımı** (başlığı Top 20'sine ekleyen
  benzersiz kullanıcı sayısı). Sıra-ağırlıklı puan v2'ye bırakıldı.
- **Sıra:** önce Faz 1 (kişisel), sonra Faz 2 (topluluk). Faz 2, Faz 1 veriyi
  büyüttüğü için anlamlı olur.

---

## Neden ucuz: altyapı zaten var

Mevcut `favorites` tablosu (istemci: `lib/services/db_helper.dart:144`, sunucu:
`backend/migrations/database.sql:29`) şunları hâlihazırda yapıyor:

- `is_tv` ile film/dizi ayrımı → iki Top 20 = `is_tv=0` / `is_tv=1`.
- `created_at`'i **sıra indeksi** olarak yazar (`saveFavorites` her öğeye `i`
  verir, `db_helper.dart:1038`) → sıralama zaten depolanır.
- Çift yönlü **delta-sync**'e dahil (`sync_service.dart:225` push,
  `sync_service.dart:391` pull) → sync tarafına dokunulmaz.
- Sunucuda `titles` tablosu (`017_central_titles.sql`) kanonik metadata'yı
  locale + `und` fallback ile verir.

Onboarding'deki 3 favori zaten buraya yazılıyor (`prefs_service.dart:234`).

---

## FAZ 1 — Kişisel Top 20 (Film + Dizi)

### Önce çözülecek iki bağımlılık (yoksa sessizce bozulur)

1. **Onboarding clobber riski.** "Zevk Analizini Yeniden Başlat" → onboarding →
   `saveFavorites` tüm listeyi silip yeniden yazar. 18 filmlik Top 20, onboarding
   tekrar açılınca 3'e düşer.
   **Çözüm:** onboarding favoriler doluysa üstüne yazmasın (yalnızca boşsa
   tohumlasın) ya da seçimi mevcut listeyle birleştirsin.
2. **Öneri motoru beslemesi.** `getFavoritesRaw()` favorilerin `genre_ids`'ini
   öneri ağırlıklarına katar (`sync_service.dart:495` çevresi + `recommendation_engine`).
   3 yerine 20 favori = daha güçlü sinyal. **Karar: katsın** (varsayılan). İstenirse
   motora yalnız ilk N verilir.

### İş kalemleri

1. **Depolama yardımcıları** (`db_helper.dart` + `prefs_service.dart`)
   - Var olan `saveFavorites`/`getFavorites` yeterli. Tekil işlemler
     (`addFavorite`, `removeFavorite`, `reorderFavorites`) değiştirilmiş listeyi
     `saveFavorites`'a vererek çalışır (tam liste yeniden yazımı).
   - `PrefsService.getFavoriteMovies()` / `getFavoriteTvShows()` okuma sarmalayıcıları.

2. **Provider** (`lib/providers/top_list_provider.dart` — yeni)
   - `watchlist_provider` deseni (`lib/providers/watchlist_provider.dart:53`).
   - `family(isTV)` veya iki provider; metotlar: `load`, `add` (20 sınırı, doluysa
     `false`), `remove`, `reorder(oldIndex, newIndex)`.
   - Her mutasyon sonrası `saveFavorites` + arka planda `performSync()`.

3. **Düzenleme ekranı** (`lib/screens/top_list_edit_screen.dart` — yeni)
   - `LibraryScreen` gibi `TabBar`: **Film · N/20** | **Dizi · N/20**.
   - Gövde: `ReorderableListView` — sürükle-bırak sıra, sol sıra rozeti (#1…#20),
     sağ tutamaç + çıkar.
   - "Ekle": `FavoritePickStep`'in arama mantığını yeniden kullanan sayfa/sheet
     (`lib/screens/onboarding/favorite_pick_step.dart:52`); `searchMulti` sonucu
     `isTV` filtresiyle. 20 doluyken "eklemek için birini çıkar".

4. **Profil rayları** (`profile_screen.dart` + yeni `Top20Rail` widget'ı)
   - `UserHeaderCard`'dan **sonra**, "Kütüphanen"in **üstüne** yeni sliver'lar
     (`lib/screens/profile_screen.dart:390` civarı).
   - `_railLabel` deseniyle "TOP 20'M · N/20" + "Düzenle" hapı; altında sıra
     rozetli yatay poster rayı. **İki ayrı ray** (Film / Dizi) en okunur olanı.
   - Boş durum: "Panteonunu oluştur" CTA'sı → düzenleme ekranı.

5. **l10n** (`lib/l10n/tr.dart` + `en.dart`)
   - `top_list_movies_title`, `top_list_tv_title`, `top_list_edit`, `top_list_add`,
     `top_list_full`, `top_list_empty_title/desc`, `top_list_reorder_hint`.

6. **Testler** (`test/top_list_provider_test.dart`)
   - `watchlist_provider_test.dart` deseni: ekle/çıkar/sırala, 20 sınırı,
     film-dizi izolasyonu, onboarding clobber regresyonu.

### Migration / sync
- **Gerekmez.** Şema aynı, sync aynı. Kapsam çoğunlukla UI.

### Faz 1 sırası
1. Onboarding clobber düzeltmesi + öneri motoru kararı.
2. `top_list_provider` + db/prefs yardımcıları + testler.
3. Düzenleme ekranı (reorder + arama-ekle).
4. Profil rayları + boş durum + l10n.

---

## FAZ 2 — Topluluk "Popüler Top 20 Film / Dizi"

### Kavramsal ayrım
Mevcut "Popüler Listeler" popüler **kullanıcı profillerini** gösterir
(`getTopProfiles`, profil beğenileri). Bu özellik popüler **başlıkları** gösterir —
yeni, tamamlayıcı bölüm. Ayrı başlık: "Topluluğun Favorileri" / "Popüler Top 20".

### Sıralama = basit favori sayımı (karar)

```sql
SELECT f.id, f.is_tv, COUNT(DISTINCT f.user_id) AS votes
FROM favorites f
WHERE f.deleted = 0 AND f.is_tv = ?
GROUP BY f.id, f.is_tv
HAVING votes >= :minVotes          -- tek kişilik listenin tepeye çıkmasını engeller
ORDER BY votes DESC, f.id ASC
LIMIT 20
```
Sonra `titles`'a locale join + `und` fallback ile poster/başlık.

### Mimari (karar): cron önhesaplar, endpoint sadece okur

Ağır `GROUP BY` **istek yolunda çalışmaz**. Mevcut cron
(`backend/maintenance.php` → `Maintenance::run()`) periyodik olarak hesaplar,
sonucu küçük bir tabloya yazar; endpoint yalnızca o 20 satırı okur → istek anında
sıfır toplama.

### Backend iş kalemleri

1. **Önhesap tablosu** (`backend/migrations/` — yeni migration)
   ```sql
   CREATE TABLE popular_titles (
     is_tv       TINYINT(1)   NOT NULL,
     rank        SMALLINT     NOT NULL,   -- 1..20
     tmdb_id     INT          NOT NULL,
     votes       INT          NOT NULL,
     computed_at BIGINT       NOT NULL,
     PRIMARY KEY (is_tv, rank)
   );
   ```
   **Locale-bağımsız** — sadece sıralama + oy sayısı. Metadata `titles`'tan
   serve anında gelir.

2. **Cron önhesap adımı** (`backend/src/Maintenance.php`)
   - `run()` içine yeni adım: her `is_tv` için `COUNT(DISTINCT user_id)` grubunu
     çalıştır, top 20'yi `popular_titles`'a REPLACE et (eskiyi truncate + yeni insert).
   - **Kendi transaction'ında** yap; `run()`'ın tek büyük transaction'ına
     (`Maintenance.php:40`) sokma — favoriler üzerindeki tam tablo gruplaması orada
     uzun kilit tutar. Yalnız favorites okur, popular_titles yazar.
   - Sıklık: favoriler yavaş değişir → mevcut cron programına biner (saatlik/günlük
     yeter); istenirse farklı cadence için ayrı cron kaydı. **Yeni mekanizma yok.**
   - `favorites (id, is_tv, deleted)` gruplama indeksi düşün (mevcut indeksler
     `user_id` odaklı, `database.sql:255`) — sorgu istek dışında koşsa da hızlansın.

3. **Endpoint** (`backend/api/index.php`)
   - `GET /titles/popular?type=movie|tv` (mevcut `/titles/.../score` dinamik
     rotasının yanına).
   - `popular_titles` → `titles` locale join + `und` fallback (`getTopProfiles`
     join deseni). Dönen: `[{tmdb_id, is_tv, title, poster_path, votes, rank}]`.

4. **Soğuk başlangıç & eşik.** `popular_titles` boşsa (cron henüz koşmadı) ya da
   satır sayısı azsa endpoint TMDB popülerlik / `vote_average` ile doldurur.
   Önhesapta `HAVING votes >= :minVotes` ile tek kişilik listeyi ele.

5. **Gizlilik.** Yalnızca toplu sayım döner, kimlik ifşası yok. İstenirse favoriye
   "sayıma dahil olma" opt-out'u (v2).

### İstemci iş kalemleri

6. **Provider** (`lib/providers/popular_titles_provider.dart` — yeni)
   - `family(isTV)`; endpoint çağrısı. Sunucu zaten önhesaplı olduğu için istemci
     önbelleği hafif tutulabilir (gün içi tekrar çağrıyı kesecek kısa TTL).

7. **Keşfet bölümü** (`browse_screen.dart` + `browse/` altında yeni ray widget'ı)
   - `BrowseSectionHeader` + `BrowseCard` yeniden kullanılır; sıra rozeti
     (#1 gold, gerisi crimson) buraya da gelir → kişisel Top 20 ile görsel akraba.
   - İki ray: "Popüler Top 20 Film" · "Popüler Top 20 Dizi". Kart → `MovieDetailSheet`.
     "Tümünü gör" → `results_screen` benzeri tam liste.

8. **l10n.** `popular_top_movies_title`, `popular_top_tv_title`, `popular_votes_label`
   ("{} kişi favoriledi"), soğuk/boş durum metni.

9. **Testler.** Backend: `MaintenanceTest` deseninde önhesap adımı (grup + eşik +
   top 20 yazımı) + endpoint locale fallback + soğuk başlangıç. İstemci: provider
   parse testi.

---

## Beslenme döngüsü
Şu an favoriler onboarding'de 3 ile sınırlı → topluluk havuzu zayıf. Faz 1 favori
verisini ~20 katına çıkarır → Faz 2 ancak o zaman anlamlı olur. Bu yüzden Faz 1 önce.

## Referans dosyalar
- İstemci depolama/sync: `lib/services/db_helper.dart`, `lib/services/sync_service.dart`,
  `lib/services/prefs_service.dart`
- Profil/kütüphane UI: `lib/screens/profile_screen.dart`, `lib/screens/watchlist_screen.dart`
  (LibraryScreen), `lib/screens/onboarding/favorite_pick_step.dart`
- Keşfet: `lib/screens/browse_screen.dart`, `lib/screens/browse/`
- Backend: `backend/api/index.php`, `backend/src/Social/ProfilesPublicTrait.php`,
  `backend/src/Maintenance.php`, `backend/migrations/017_central_titles.sql`
