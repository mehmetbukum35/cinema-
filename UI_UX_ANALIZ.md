# cinema+ Arayüz Analizi (Detaylı UI/UX Denetimi)

*Tarih: 2 Temmuz 2026 — Yöntem: kod tabanının tamamının statik incelemesi + WCAG kontrast hesaplamaları + `ui-ux-pro-max` kural setiyle karşılaştırma.*

Genel arayüz puanı: **7/10**. Görsel dil (sinematik koyu tema, altın/kırmızı aksanlar, aurora arkaplan) tutarlı ve iddialı; animasyon disiplini (150–320 ms, easeOut eğrileri) profesyonel. Zayıf noktalar erişilebilirlik kontrastı, metin ölçekleme dayanıklılığı ve yarım kalmış lokalizasyon.

---

## 1. KRİTİK — Erişilebilirlik kontrastı (WCAG başarısız)

Hesaplanan gerçek kontrast oranları (minimum 4.5:1 olmalı):

| Yer | Renk çifti | Oran | Durum |
|---|---|---|---|
| Puan butonu "Eh" | Beyaz metin / #FDD835 sarı | **1.40:1** | Ağır ihlal — metin neredeyse okunmuyor |
| Puan butonu "İyi" | Beyaz / #FB8C00 turuncu | **2.37:1** | İhlal |
| Puan butonu "Harika" | Beyaz / #43A047 yeşil | **3.30:1** | İhlal |
| Puan butonu "Berbat" | Beyaz / #E53935 kırmızı | 4.23:1 | Sınırda (bold 12-14px için kabul edilebilir ama riskli) |
| ElevatedButton'lar | Beyaz / marka kırmızısı #E94560 | **3.83:1** | İhlal (Retry, kaydet butonları) |
| Açık tema altın metin | #B8893E / #FAF6EF zemin | **2.92:1** | İhlal — uyum rozeti, overline başlıklar, altın vurgular açık temada zayıf |

Uygulamanın EN merkezi etkileşimi (puanlama butonları) en kötü kontrasta sahip. Öneri: buton metnini koyu renge çevir (örn. sarı/turuncu üstünde `Colors.black87` — siyah/sarı 15:1 verir), veya dolgu yerine koyu zemin + renkli kenarlık/ikon kullan. Açık temada altın için `goldDeep #9C7430` bile yetmez; metin olarak kullanılacaksa `#7A5A20` civarı gerekir.

İyi olanlar: `dim` (7.1:1), `bodyMedium` (13.7:1), koyu temada altın (10.9:1) — nötr metin hiyerarşisi sağlam.

## 2. KRİTİK — Sistem yazı boyutu (textScaler) dayanıklılığı yok

Kod tabanında hiçbir `textScaler`/`textScale` işleme yok ve arayüz sabit yüksekliklerle dolu: nav bar `height: 64` içinde 11px etiket, arama kutusu `height: 48`, kart rayları `height: 275/250/200`, chip rayı `height: 44`. Telefonunda "büyük yazı" kullanan bir kullanıcıda (Android %130+) bu düzenler taşar (overflow şeridi) veya metinler kırpılır. Ayrıca 58 yerde 9–11px font var — %100 ölçekte bile küçük, yaşlı kullanıcılar için zor.

Öneri: `MaterialApp.builder` içinde `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` ile en azından patlamayı önle; kritik yerlerde sabit yükseklikleri kaldırıp içeriğe göre büyümeye izin ver; 10px altı fontları 11-12'ye çek.

## 3. YÜKSEK — Basma (pressed) geri bildirimi tamamen kapalı

`main.dart` temasında `splashFactory: NoSplash.splashFactory` + `splashColor/highlightColor: transparent` ve ekranların çoğu `GestureDetector` kullanıyor. Sonuç: uygulamada dokunmanın **hiçbir görsel karşılığı yok** — sadece haptic var. Estetik bir tercih ama "dokundum mu?" belirsizliği yaratır (özellikle haptic kapalı cihazlarda). Öneri: ya kartlara 80-120ms'lik bir scale/opacity pressed durumu ekle (`AnimatedScale` + `onTapDown/Up`), ya da en azından `InkWell` + çok hafif özel bir splash factory kullan.

## 4. YÜKSEK — Lokalizasyon yarım: EN kullanıcı Türkçe metin görüyor

Sistemli bir `AppLocalizations` altyapın var ama şu yerler onu atlıyor:

- `swipe_screen.dart:103-125` — filtre etiketleri: 'Kore Sineması', 'Hollywood', 'Tümü', 'Bilinmeyen' → EN'de de Türkçe.
- `swipe_screen.dart:1024` — kart rozeti `movie.isTV ? 'Dizi' : 'Film'` hardcoded.
- `profile_screen.dart:250,261` — Semantics/tooltip 'Hesap' hardcoded.
- `login_screen.dart:81,95,115` — form etiketleri 'Ad', 'E-posta', 'Parola' hardcoded.
- `movie_detail_sheet.dart:1074-1118` — bölüm başlıkları switch-case ile çevriliyor (çalışıyor ama kırılgan desen; yeni başlık eklenince unutulur — nitekim 'NEREDE İZLENİR?' anahtarı localization_service'te yok).
- Ayrıca iki farklı çeviri deseni yarışıyor: `tr?.get(key)` ve `isTr ? '...' : '...'` (yüzlerce inline üçlü). Tek desene (get) toplamak bakım yükünü ciddi azaltır.

## 5. YÜKSEK — Hareket azaltma (reduced motion) ve pil

- `CinematicBackground` 7 ekranda 14 sn'lik sonsuz döngüyle tam ekran CustomPaint çiziyor ve `disableAnimations`'ı hiç kontrol etmiyor (widget'ta `animate` parametresi var ama hiçbir çağrıda kullanılmamış). `MainShell` `IndexedStack` kullandığı için 5 sekmenin ticker'ı **aynı anda** çalışıyor — görünmeyen ekranlar boyanmasa da her karede controller uyanıyor. Vestibüler hassasiyeti olan kullanıcılar için de sorun.
  Öneri: `MediaQuery.disableAnimations` true ise `animate: false`; ayrıca `TickerMode`/görünürlükle sekme dışı ekranların controller'ını durdur.
- `Shimmer` da aynı şekilde reduced-motion'ı yok sayıyor.
- Buna karşılık `swipe_screen._rate/_undo` `disableAnimations`'ı kontrol ediyor — bu bilinç kod tabanında var, sadece tutarlı uygulanmamış. 

## 6. ORTA — Dokunma hedefleri tutarsız

Profil başlığındaki ikonlar 44×44'e çekilmiş (doğru yapılmış ✓) ama `browse_screen.dart:604-757` başlık ikonları hâlâ `minWidth/minHeight: 36` ve aralarındaki boşluk 2px (kural: ≥44px hedef, ≥8px aralık). Beş küçük ikon yan yana — yanlış basma riski en yüksek yer. Diğerleri: arama ekranındaki temizle (✕) ikonu ~18px (`search_screen.dart:180`, `match_screen.dart:351`), browse onboarding banner kapatma butonu `constraints: BoxConstraints()` ile daraltılmış (`browse_screen.dart:1334`), aktif filtre `InputChip` silme ikonu 32px şeritte.

## 7. ORTA — Ekran okuyucu (TalkBack/VoiceOver) kapsaması dengesiz

Semantics kullanımı var ama adalı: swipe (4), browse (9), profile (6) iyi; **movie_detail_sheet, search, social, watchlist, login: 0**. Detay sayfasındaki ikon-only butonlar (paylaş, arkadaşa öner, fragman) ekran okuyucuda anlamsız. Film kartları (browse/search/results) da `Semantics(button:true, label: film adı)` sarmalayıcısından yoksun. Öneri: en azından ikon-only butonlara `tooltip` veya `Semantics(label)` ekle — tooltip ikisini birden çözer.

## 8. ORTA — Açık tema pürüzleri

- `browse_screen._skeleton()` (326-464) palet yerine sabit `AppColors.card/surface/border` (koyu tema sabitleri) kullanıyor → **açık temada yükleme iskeleti simsiyah bloklar halinde** görünüyor. `c.card` vb. kullanılmalı.
- Altın metin kontrastı (bkz. madde 1) açık temada sistematik sorun.
- `movie_detail_sheet.dart:384` 'Dizi' rozeti `Colors.blue` — palette olmayan, iki temada da yabancı duran bir renk.

## 9. ORTA — Tutarlılık detayları

- **Swipe jest ↔ renk uyumsuzluğu:** sağa kaydırma `rate(2)` (İyi/turuncu) veriyor ama overlay **yeşil** "LIKED" gösteriyor (`swipe_screen.dart:637,1078`) — kullanıcı Harika verdiğini sanıyor. Ya overlay rengini rIyi yap ya sağa kaydırmayı 3'e bağla.
- **Emoji ikonlar:** '🎬', '📺' bölüm rozetleri, '🌐' filtre chip'leri, bayrak emojili dil etiketleri (skill kuralı: emoji yerine ikon). Küçük ama "premium" hedefiyle çelişiyor.
- **Görsel yükleme:** her yerde `CachedNetworkImage` + `PulsingPlaceholder` kullanılmışken `social_screen.dart:757,1089` `Image.network` — önbelleksiz ve placeholder'sız.
- **matchScore rozeti** (`_BrowseCard`, `_heroRow`) bağlamsız yeşil sayı — yeni kullanıcı "87 ne?" der. Bir ikon + tooltip/ilk kullanım ipucu hak ediyor.
- Match ekranı başlık/segment adları uyumsuz: "Film Eşleştir" ↔ "Film Tabanlı" gibi.

## 10. DÜŞÜK — Küçük dokunuşlar

- `login_screen` alanlarında `autofillHints` yok (AutofillHints.email/password) — parola yöneticileri devreye giremiyor.
- Segmented tab (match) 40px yükseklik; 44 olabilir.
- `MaterialApp.title` 'Ne İzlesem?' — marka 'cinema+' ile tutarlılık kontrol edilmeli.
- Boş durumlar (empty state) metin ağırlıklı ve iyi; ama arama boş durumunda popüler aramalar/öneri chip'leri dönüşümü artırırdı.
- Detay sheet'te ekstralar yüklenirken 20px spinner içerik zıplamasına yol açıyor — bölümler için sabit yükseklikli iskelet daha akıcı olur.

---

## Güçlü yönler (korunmalı)

1. **Tasarım token disiplini:** `ThemePalette` + `context.c` deseni, gradyan/gölge setleri — tema tutarlılığı üst düzey; açık/koyu tema mimarisi geleceğe hazır.
2. **Animasyon kalitesi:** nav indikatörü (320ms easeOutCubic), kart fade'leri (200ms), segmented tab kayması — skill'in 150-300ms kuralıyla birebir uyumlu.
3. **Haptic dili:** light/medium impact ayrımı bilinçli kullanılmış.
4. **Yükleme durumları:** browse ve search'te gerçek iskelet ekranlar (+Shimmer) var; öneri gönderiminde spinner + çift tıklama kilidi (`_RecommendSheet` — loading-buttons kuralına örnek uygulama).
5. **Hata durumları:** API anahtarı / bağlantı / 401 ayrımı yapan, yeniden dene butonlu açıklayıcı hata ekranları.
6. **Swipe erişilebilirliği:** jestin buton alternatifi zaten var; undo'nun Semantics `enabled` durumu doğru.

## Önerilen öncelik sırası

1. Puan butonu + kırmızı buton kontrastları (1 saatlik iş, en yüksek etki)
2. textScaler clamp + 10px altı fontların tasfiyesi
3. Browse başlık ikonlarını 44px'e çekmek + skeleton palet düzeltmesi
4. CinematicBackground'a reduced-motion ve TickerMode
5. Lokalizasyon kaçaklarını `get()`'e toplamak
6. İkon-only butonlara tooltip/Semantics
