# Misafirden üyeye: davet tasarımı

**Tarih:** 2026-08-10 · **Durum:** onaylandı, plana hazır

## Problem

Anonim kullanıcı uygulamanın çoğunu kullanabiliyor: swipe, puanlama, izleme listesi,
Top 20, Sinema DNA, keşfet, arama — hepsi cihazdaki SQLite'ta. Üyelikle açılan şey
sosyal katman: Birlikte Seç, arkadaş akışı, öneri kutusu, genel profil.

Sorun bunların "az satılması" değil, **görünmez olması**. Kullanıcı Birlikte Seç'in
var olduğunu ancak Together sekmesine dokunup duvara çarparak öğreniyordu.
`803c32b` bunun bir kısmını kapattı (popüler profiller artık misafire de açık,
arkadaş akışı yerine teaser var). Bu tasarım geri kalanını ele alıyor.

## Hedef

**Sosyal özellikleri keşfedilebilir kılmak.** Veri kaybı korkusu ikincil bir
mesajdır, ana eksen değil.

## Hedef olmayanlar

- Veri güvenliği yüzdesi / ilerleme çubuğu
- Misafir ve üyeliği karşılaştıran özellik tablosu
- Puanlama eşiklerinde tekrarlayan açılır pencereler

Gerekçeleri "Reddedilen alternatifler" bölümünde.

## Temel fikir

> Kullanıcıya ne kazanacağını anlatma — zaten sahip olduğu şeyi, başkalarınınkinin
> yanında göster.

Kullanıcının kendi Top 20 listesi, halihazırda kaydırdığı "Popüler Listeler"
rayının başında, gerçek afişleriyle görünür. Diğer kartlardan tek farkı: onunki
yayında değil.

---

## Faz 0 — Önkoşul: misafir→hesap geçişini onar

**Bu faz diğerlerinden bağımsız olarak yapılmalı; tek başına bir hatayı kapatıyor.**

### Mevcut davranış (hatalı)

`lib/providers/auth/session.dart` içinde `_finalizeAuth`:

```dart
if (hasLocalData && (lastUserId == null || lastUserId != newUserId)) {
  return AuthResult(status: AuthStatus.conflict, ...);
}
```

Hiç giriş yapmamış misafirde `lastUserId == null` ve `hasLocalData == true` olur,
yani **her misafir kaydı çakışma döner.** Kullanıcı şu ekranı görür:

```
Başlık : "Hesap Çakışması"
        "Bu Hesapla Birleştir"
        "Cihazdakileri Sil & Buluttan Yükle"   ← yeni hesapta bulut BOŞTUR
        "Girişi İptal Et"
```

Yeni hesapta bulut boş olduğu için "Sil & Buluttan Yükle" seçeneği kullanıcının
tüm verisini kalıcı olarak siler ve yerine hiçbir şey koymaz.

### Hedef davranış

`lastUserId == null` **çakışma değildir** — ortada çakışacak ikinci hesap yoktur.
Çakışma yalnızca gerçek hesap değişiminde sorulur:

```dart
// Gerçek hesap değişimi = cihazda ÖNCEDEN başka bir hesap vardı.
// Hiç giriş yapmamış misafirin verisi çakışmaz; sahibine kavuşur.
final isAccountSwitch = lastUserId != null && lastUserId != newUserId;
if (hasLocalData && isAccountSwitch) { ...conflict... }
```

Misafir sessizce `ConflictResolution.merge` ile devam eder.

### Taşınanı göster

Birleştirmeden sonra, ne taşındığı tek satırla bildirilir:

> "14 puanın ve 2 listen hesabına taşındı."

Sayılar `PrefsLibraryFacade.getRatingCount()` ve favori listelerinden okunur.
Bu, uygulamanın en korkutucu anını en güven verici anına çevirir.

### Testler

- Misafir (hiç giriş yapmamış) + yerel veri + giriş → `AuthStatus.success`,
  çakışma **yok**, puanlar korunur
- Cihazda A hesabı varken B hesabıyla giriş → çakışma **hâlâ** döner
- Birleştirme sonrası özet sayıları gerçek veriyle eşleşir

---

## Faz 1 — "Senin Listen" hayalet kartı

### Yerleşim

"Popüler Listeler" rayının **ilk** kartı, sıralanmış profillerden önce.
Kesik çizgili kenarlık, sıra numarası yok.

```
┌──────────────────────────────┐   ┌─────────────────┐
│  ○   Senin Listen            │   │ #1  @ayse       │
│      yayında değil           │ → │     ❤ 42        │
│  ▓▓  ▓▓  ▓▓  ▓▓              │   │ ▓▓ ▓▓ ▓▓ ▓▓     │
│  Giriş yap ve yayınla →      │   └─────────────────┘
└──────────────────────────────┘
```

CTA metni "Yayınla" değil **"Giriş yap ve yayınla"** olmalı: dokunuş yayınlamıyor,
giriş ekranını açıyor. Kısa CTA daha çekici ama ilk dokunuşta verdiği sözü tutmuyor
ve Faz 0'da kazanılan güveni burada geri veriyor.

Afişler kullanıcının **gerçek** favorileridir — `PrefsLibraryFacade.getFavoriteMovies()`
ile yerelden okunur. Sunucuya istek yok.

### Görünme koşulu

`favorites.length >= 3`. Altındaysa kart hiç çizilmez ve **hiçbir davet gösterilmez.**
Gösterilecek bir şey yokken davet de yoktur.

### Davranış

Dokununca doğrudan `LoginScreen`. Ara katman, tablo, açılır pencere yok —
`top_profile_card` ve `browse_top_profile_card`'da `7adb7b0` ile kurulan desenin aynısı.

### Dürüstlük şartı

Hesap açmak tek başına listeyi yayına çıkarmaz: kullanıcı adı + `is_public`
gerekir (`SocialApi.setupProfile`). `lib/utils/username_helper.dart` girişten sonra
kullanıcı adı istemeyi zaten otomatik yürütüyor, ama kart bunu gizlememeli.
Metin "giriş yap ve listeni yayınla" demeli, "giriş yap, listen yayında" değil.

### Teknik notlar

- `TopProfilePreview` yalnızca `title` + `posterPath` + `movieId` + `isTv` istiyor;
  hepsi `Movie`'den yereldir
- `BrowseTopProfilesSection` şu an `List<TopProfile>` alıyor. Sahte bir `TopProfile`
  üretmek yerine ayrı bir kart widget'ı yazılmalı — sahte model üretmek, ileride
  `is_me` / `like_count` gibi alanlarda gerçek veriyle karışır
- Sinema DNA misafirde de üretiliyor (`taste_dna_service` auth kontrolü içermiyor),
  ileride kartın ikinci satırında kullanılabilir; bu fazın kapsamında değil

---

## Faz 2 — Duvarları tek satıra indir

Karşılaştırma tablosu yerine, her duvar somut olarak neyin eksik olduğunu söyler.

| Anahtar | Şu an | Öneri |
|---|---|---|
| `couch_login_required` | "Birlikte Seç için giriş yapmalısın." | "Birlikte Seç iki telefon ister. Giriş yap, arkadaşını çağır." |
| `profile_not_logged_in` | "Bulut eşitleme aktif değil" | "{n} puanın yalnızca bu cihazda." |

İkincisi veri riskini **bir kez** ve **gerçek sayıyla** söyler. Risk gerçektir:
`android/app/src/main/res/xml/backup_rules.xml` veritabanını ve sharedpref'i Android
otomatik yedeklemesinden bilerek dışlar ("Cloud sync is authoritative"), `device-transfer`
dahil. Yani misafir için hiçbir kurtarma yolu yoktur. Bu gerçek, korku pazarlamasına
çevrilmeden bir kez söylenir — kırmızı çubuk, ünlem, yüzde yok.

---

## Faz 3 — Ölçüm

**Kapsam kararı:** gösterim (impression) sayacı kurulmayacak. Gereken tek bilgi
hangi yüzeyin kayıt ürettiğidir.

`RecommendationTelemetryService` bu iş için uygun değil: API'si `Movie` merkezli
(`recordShown(Iterable<Movie>)`, `recordAction(Movie, ...)`) ve olayları öneri
isabet analizine akıyor. Misafir davetini oraya sokmak öneri analitiğini kirletir.

Bunun yerine: davete dokunulduğunda kaynak etiketi (`ghost_card`, `couch_wall`,
`profile_card`) `SharedPreferences`'a yazılır; **başarılı kayıtta bir kez**
tüketilir ve `POST /auth/register` gövdesine `signup_source` alanı olarak gider.
Backend bunu `users.signup_source VARCHAR(32) NULL` kolonuna yazar (yeni migration).
Etiket tüketildikten sonra yerelden silinir.

Dönüşüm başına tek kayıt, gösterim başına değil. Yalnız yerel tutmak işe yaramaz —
okunamayan analitik analitik değildir; bu yüzden tek kolonluk migration'a değer.

---

## Reddedilen alternatifler

| Öneri | Ret gerekçesi |
|---|---|
| "%30 Veri Güvenliği" ilerleme çubuğu | Veri ya yedeklidir ya değildir. Yüzde, arkasında hesap olmayan uydurma kesinliktir — dark pattern. Elde gerçek sayı var: `getRatingCount()` |
| Misafir/üye karşılaştırma tablosu | Tasarlandığı haliyle üç satırı olmayan özellik satıyordu: rozet sistemi yok, profilde grafik yok, web'de kalıcılık yok (`db_helper.dart` `kIsWeb` → in-memory mock, CI'da web build de yok) |
| 5/15/30 puanlamada açılır pencere | İlk haftada beş ayrı kesinti demek; "bıkkınlık yaratmadan" ilkesiyle çelişir |
| `guest_actions_count` sayacı | SQLite zaten gerçeği tutuyor. İkinci sayaç senkron silme / `hardClearAllData` / hesap değişiminde ayrışır |
| Sosyal butonda karşılaştırma sayfası | Kullanıcı Match'e bastığında Match'i kullanmak ister. Duvarın önüne ikinci duvar koymak sürtünmeyi artırır |

## Riskler

- **Faz 1 tek başına dönüşüm getirmeyebilir.** Faz 3 olmadan bunu bilemeyiz; bu yüzden
  Faz 3, Faz 1 ile birlikte veya hemen ardından gelmeli.
- **Hayalet kart rayın başında yer kaplıyor.** Sosyal kanıtı (gerçek profilleri) bir
  kart geriye itiyor. Ölçüm ters sonuç verirse kartı ray sonuna almak denenebilir.

## Sıra

Faz 0 → Faz 1 + Faz 3 → Faz 2.

Faz 0 bir hata düzeltmesidir, diğerlerine bağlı değildir ve **ayrı bir uygulama
planı olarak yürütülmelidir** — davet tasarımı hiç yapılmasa bile tek başına
gönderilmelidir. Faz 1–3 tek plan olarak birlikte gider; Faz 3 olmadan Faz 1'in
işe yarayıp yaramadığı bilinemez.
