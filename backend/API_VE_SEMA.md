# Ne İzlesem? — Backend Şeması ve API Sözleşmesi

Hedef ortam: **Paylaşımlı LiteSpeed hosting + PHP + MySQL/MariaDB**
Mimari: `Flutter app → PHP REST API → MySQL`. DB bilgileri **asla** uygulamada tutulmaz; sadece sunucudaki config'te.

İlke: Mevcut yerel SQLite tabloları (`ratings`, `watchlist`, `favorites`, `watched_seasons`, `search_history`) sunucuda **kullanıcı bazlı** karşılığıyla aynalanır. SQLite, **yerel cache** olarak kalır (offline-first); sunucu kaynak otoritedir.

---

## 1. MySQL Şeması

> Not: `genre_ids` için JSON kullanıldı (MariaDB 10.2+/MySQL 5.7+ destekler). Hosting'de eski sürüm varsa `TEXT` yapıp JSON'ı string olarak sakla.
> Tüm zaman damgaları `BIGINT` (Unix ms) — Flutter tarafındaki `created_at` ile uyumlu.

```sql
-- Karakter seti: utf8mb4 (Türkçe + emoji güvenli)
SET NAMES utf8mb4;

-- ─── Kullanıcılar (users) ────────────────────────────────────────
CREATE TABLE users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)    NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,   -- bcrypt/argon2 (asla düz metin)
  display_name  VARCHAR(100)    NULL,
  username      VARCHAR(50)     NULL,       -- Benzersiz kullanıcı adı (Sosyal özellikler için)
  is_public     TINYINT(1)      NOT NULL DEFAULT 1, -- Profil herkese açık mı?
  taste_dna     TEXT            NULL,       -- Sinema DNA snapshot'ı (JSON formatında)
  taste_dna_at  BIGINT          NOT NULL DEFAULT 0, -- Sinema DNA'nın oluşturulma zaman damgası
  google_sub    VARCHAR(255)    NULL,       -- Google Sign-In benzersiz kullanıcı kimliği
  email_verified TINYINT(1)     NOT NULL DEFAULT 0, -- Kayıt e-postası kodla doğrulandı mı? (0 iken giriş yapılamaz)
  created_at    BIGINT          NOT NULL,
  updated_at    BIGINT          NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_username (username),
  UNIQUE KEY idx_users_google_sub (google_sub)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Yenileme token'ları (refresh_tokens) ─────────────────────────
CREATE TABLE refresh_tokens (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NOT NULL,
  token_hash  CHAR(64)        NOT NULL,    -- SHA-256 hash, ham token saklanmaz
  expires_at  BIGINT          NOT NULL,
  created_at  BIGINT          NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_rt_hash (token_hash),
  KEY idx_rt_user (user_id),
  CONSTRAINT fk_rt_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Arkadaşlık İlişkileri (friends) ──────────────────────────────
CREATE TABLE friends (
  user_id      BIGINT UNSIGNED NOT NULL,
  friend_id    BIGINT UNSIGNED NOT NULL,
  status       VARCHAR(20)     NOT NULL DEFAULT 'pending', -- 'pending' | 'accepted'
  created_at   BIGINT          NOT NULL,
  updated_at   BIGINT          NOT NULL,
  PRIMARY KEY (user_id, friend_id),
  CONSTRAINT fk_friends_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Puanlar (ratings) ───────────────────────────────────────────
CREATE TABLE ratings (
  user_id      BIGINT UNSIGNED NOT NULL,
  movie_id     INT             NOT NULL,
  is_tv        TINYINT(1)      NOT NULL,
  rating       INT             NOT NULL,    -- Puan (0: Berbat, 1: Eh, 2: İyi, 3: Harika) — Sync.php 0..3 doğrular
  genre_ids    JSON            NULL,
  title        VARCHAR(512)    NULL,
  poster_path  VARCHAR(255)    NULL,
  backdrop_path VARCHAR(255)   NULL,
  overview     TEXT            NULL,
  vote_average DOUBLE          NULL,
  release_date VARCHAR(20)     NULL,
  popularity   DOUBLE          NULL,
  comment      TEXT            NULL,        -- Kullanıcının yorumu (sunucuda 280'e kırpılır, URL'ler sökülür)
  is_spoiler   TINYINT(1)      NOT NULL DEFAULT 0, -- Yorum sürprizbozan içeriyor mu?
  is_private   TINYINT(1)      NOT NULL DEFAULT 0, -- Gizli puan/yorum: sosyal görünümlere çıkmaz
  is_hidden    TINYINT(1)      NOT NULL DEFAULT 0, -- Moderasyon gizlemesi (SYNC EDİLMEZ; sunucu tarafı)
  created_at   BIGINT          NOT NULL,
  updated_at   BIGINT          NOT NULL,   -- delta-sync için
  deleted      TINYINT(1)      NOT NULL DEFAULT 0,  -- soft delete
  PRIMARY KEY (user_id, movie_id, is_tv),
  KEY idx_ratings_sync (user_id, updated_at),
  KEY idx_ratings_title (movie_id, is_tv),  -- başlık bazlı yorum/skor sorguları
  CONSTRAINT fk_ratings_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Yorum şikayetleri (review_reports) ──────────────────────────
-- Yorumlar ratings satırıdır; şikayet hedefi (reported_user_id, movie_id, is_tv).
-- status: open → moderatör aksiyonuyla resolved/dismissed.
CREATE TABLE review_reports (
  reporter_id      BIGINT UNSIGNED NOT NULL,
  reported_user_id BIGINT UNSIGNED NOT NULL,
  movie_id         INT             NOT NULL,
  is_tv            TINYINT(1)      NOT NULL,
  reason           VARCHAR(40)     NOT NULL DEFAULT 'other',
  status           VARCHAR(20)     NOT NULL DEFAULT 'open',
  created_at       BIGINT          NOT NULL,
  PRIMARY KEY (reporter_id, reported_user_id, movie_id, is_tv),
  KEY idx_reports_review (reported_user_id, movie_id, is_tv),
  KEY idx_reports_status (status, created_at),
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_reported FOREIGN KEY (reported_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Kullanıcı engelleme (user_blocks) ───────────────────────────
CREATE TABLE user_blocks (
  user_id         BIGINT UNSIGNED NOT NULL,
  blocked_user_id BIGINT UNSIGNED NOT NULL,
  created_at      BIGINT          NOT NULL,
  PRIMARY KEY (user_id, blocked_user_id),
  KEY idx_blocks_blocked (blocked_user_id),
  CONSTRAINT fk_blocks_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_blocks_blocked FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── İzleme listesi (watchlist) ──────────────────────────────────
CREATE TABLE watchlist (
  user_id      BIGINT UNSIGNED NOT NULL,
  id           INT             NOT NULL,
  is_tv        TINYINT(1)      NOT NULL,
  title        VARCHAR(512)    NOT NULL,
  poster_path  VARCHAR(255)    NULL,
  backdrop_path VARCHAR(255)   NULL,
  overview     TEXT            NULL,
  vote_average DOUBLE          NULL,
  release_date VARCHAR(20)     NULL,
  genre_ids    JSON            NULL,
  created_at   BIGINT          NOT NULL,
  updated_at   BIGINT          NOT NULL,
  deleted      TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id, is_tv),
  KEY idx_watchlist_sync (user_id, updated_at),
  CONSTRAINT fk_watchlist_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Favoriler (favorites) ───────────────────────────────────────
CREATE TABLE favorites (
  user_id      BIGINT UNSIGNED NOT NULL,
  id           INT             NOT NULL,
  is_tv        TINYINT(1)      NOT NULL,
  title        VARCHAR(512)    NOT NULL,
  poster_path  VARCHAR(255)    NULL,
  backdrop_path VARCHAR(255)   NULL,
  overview     TEXT            NULL,
  vote_average DOUBLE          NULL,
  release_date VARCHAR(20)     NULL,
  genre_ids    JSON            NULL,
  created_at   BIGINT          NOT NULL,
  updated_at   BIGINT          NOT NULL,
  deleted      TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, id, is_tv),
  KEY idx_favorites_sync (user_id, updated_at),
  CONSTRAINT fk_favorites_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── İzlenen sezonlar (watched_seasons) ──────────────────────────
CREATE TABLE watched_seasons (
  user_id       BIGINT UNSIGNED NOT NULL,
  tv_id         INT             NOT NULL,
  season_number INT             NOT NULL,
  updated_at    BIGINT          NOT NULL,
  deleted       TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, tv_id, season_number),
  KEY idx_ws_sync (user_id, updated_at),
  CONSTRAINT fk_ws_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Arama geçmişi (search_history) ──────────────────────────────
CREATE TABLE search_history (
  user_id    BIGINT UNSIGNED NOT NULL,
  query      VARCHAR(255)    NOT NULL,
  created_at BIGINT          NOT NULL,
  updated_at BIGINT          NOT NULL,
  deleted    TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, query),
  KEY idx_sh_sync (user_id, updated_at),
  CONSTRAINT fk_sh_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Şifre Sıfırlama İstekleri (password_resets) ───────────────────
CREATE TABLE password_resets (
  email      VARCHAR(255)    NOT NULL,
  code_hash  VARCHAR(255)    NOT NULL,    -- 6 haneli kodun bcrypt hash'i
  attempts   INT             NOT NULL DEFAULT 0, -- Maksimum 3 deneme
  expires_at BIGINT          NOT NULL,    -- 15 dakika geçerlilik süresi
  created_at BIGINT          NOT NULL,
  PRIMARY KEY (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Kayıt Doğrulama Kodları (email_verifications) ─────────────────
-- password_resets ile aynı desen; kayıt sırasında e-posta sahipliğini kanıtlar.
CREATE TABLE email_verifications (
  email      VARCHAR(255)    NOT NULL,
  code_hash  VARCHAR(255)    NOT NULL,    -- 6 haneli kodun bcrypt hash'i
  attempts   INT             NOT NULL DEFAULT 0, -- Maksimum 3 deneme
  expires_at BIGINT          NOT NULL,    -- 15 dakika geçerlilik süresi
  created_at BIGINT          NOT NULL,
  PRIMARY KEY (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Cihaz Tokenları (device_tokens) ───────────────────────────────
CREATE TABLE device_tokens (
  token      VARCHAR(255)    NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  platform   VARCHAR(20)     NULL,        -- 'android' | 'ios' | 'web'
  created_at BIGINT          NOT NULL,
  updated_at BIGINT          NOT NULL,
  PRIMARY KEY (token),
  KEY idx_device_tokens_user (user_id),
  CONSTRAINT fk_device_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Arkadaşa Öneriler (recommendations) ────────────────────────────
CREATE TABLE recommendations (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  from_user_id BIGINT UNSIGNED NOT NULL,
  to_user_id   BIGINT UNSIGNED NOT NULL,
  movie_id     INT             NOT NULL,
  is_tv        TINYINT(1)      NOT NULL,
  title        VARCHAR(512)    NOT NULL,
  poster_path  VARCHAR(255)    NULL,
  note         VARCHAR(280)    NULL,        -- Opsiyonel kişisel not
  seen         TINYINT(1)      NOT NULL DEFAULT 0,
  created_at   BIGINT          NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_rec_once (from_user_id, to_user_id, movie_id, is_tv),
  KEY idx_rec_inbox (to_user_id, created_at),
  CONSTRAINT fk_rec_from FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_rec_to FOREIGN KEY (to_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ─── Hız Sınırları (rate_limits) ───────────────────────────────────
CREATE TABLE rate_limits (
  ip_bucket     VARCHAR(100)    NOT NULL,
  window_time   INT             NOT NULL,
  request_count INT             NOT NULL DEFAULT 1,
  PRIMARY KEY (ip_bucket, window_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
```

---

## 2. Kimlik Doğrulama (Auth) & Şifre Yönetimi

JWT tabanlı. **Access token** ömrü **2 saat**, **refresh token** ömrü **30 gün**dür.

### POST `/auth/register`
Hesabı `email_verified = 0` olarak açar ve e-postaya 6 haneli doğrulama kodu gönderir.
**Token vermez** — oturum `/auth/verify-email` ile açılır. Aynı e-postayla doğrulanmamış
bir kayıt varsa 409 dönmez; parola/isim yeni istekle güncellenir (hesabı kodu doğrulayan kazanır).
```json
// İstek
{ "email": "a@b.com", "password": "min8karakter", "display_name": "Mehmet" }
// 200 Yanıt
{ "ok": true, "pending_verification": true, "email": "a@b.com" }
// 409: e-posta doğrulanmış bir hesaba ait
```

### POST `/auth/verify-email` (Kayıt Kodu Doğrulama)
Kayıtta gönderilen kodu doğrular; başarılıysa hesap doğrulanır ve oturum açılır (Max 3 deneme, 15 dk geçerlilik).
```json
// İstek
{ "email": "a@b.com", "code": "123456" }
// 200 Yanıt
{ "user": { "id": 1, "email": "a@b.com", "display_name": "Mehmet", "username": null, "google_sub": null },
  "tokens": { "access_token": "eyJ...", "refresh_token": "f3a9...", "expires_in": 7200 } }
```

### POST `/auth/resend-verification` (Kodu Yeniden Gönder)
Doğrulanmamış hesaba yeni kod e-postalar. E-posta varlığını sızdırmamak için her durumda 200 döner.
```json
{ "email": "a@b.com" }
// 200 Yanıt
{ "ok": true }
```

### POST `/auth/login`
```json
// İstek
{ "email": "a@b.com", "password": "..." }
// 200 Yanıt
{ "user": {...}, "access_token": "eyJ...", "refresh_token": "f3a9..." }
// 403: parola doğru ama e-posta doğrulanmamış ("E-posta adresi doğrulanmamış.")
//      → istemci doğrulama ekranını açar (resend-verification + verify-email)
```

### POST `/auth/google` (Google Sign-In)
Google üzerinden oturum açar veya hesap bağlar. İmza doğrulamasını yerel JWKS/RS256 ile gerçekleştirir.
```json
// İstek
{ "id_token": "eyJ..." }
// 200 Yanıt
{ "user": {...}, "access_token": "eyJ...", "refresh_token": "f3a9..." }
```

> **Gelecek (nonce akışı):** Replay saldırılarını daha sıkı önlemek için planlanan
> `GET /auth/google/nonce` ucu sunucu tarafında tek kullanımlık nonce üretecek;
> istemci Google Sign-In başlatmadan önce bu nonce'u alıp ID token isteğine ekleyecek.
> Şu an nonce doğrulaması uygulanmıyor; tam akış bir sonraki sürümde eklenecek.

### DELETE `/auth/google/link` *(Bearer)*
Bağlı Google hesabını kaldırır. Parola ile giriş mümkün olan hesaplarda mevcut parola zorunludur.
```json
// İstek
{ "password": "mevcut_parola" }
// 200 Yanıt
{ "ok": true }
```

### POST `/auth/forgot-password` (Şifremi Unuttum)
Kullanıcıya şifre sıfırlama kodu içeren bir e-posta gönderir (SMTP).
```json
{ "email": "a@b.com" }
// 200 Yanıt (Timing saldırılarını önlemek için kullanıcı olmasa da her zaman 200 döner)
{ "ok": true }
```

### POST `/auth/verify-reset-code` (Kod Doğrulama)
Sıfırlama kodunun geçerliliğini kontrol eder (Max 3 başarısız deneme).
```json
{ "email": "a@b.com", "code": "123456" }
// 200 Yanıt
{ "ok": true }
```

### POST `/auth/reset-password` (Şifre Sıfırlama)
Yeni şifreyi kaydeder ve kullanıcının tüm aktif refresh token'larını iptal eder.
```json
{ "email": "a@b.com", "code": "123456", "new_password": "yeni_parola_min8" }
// 200 Yanıt
{ "ok": true }
```

### POST `/auth/change-password` *(Bearer)*
Giriş yapmış kullanıcının şifresini değiştirir. Tüm aktif refresh token'ları siler.
```json
{ "old_password": "eski_parola", "new_password": "yeni_parola_min8" }
// 200 Yanıt
{ "ok": true }
```

### POST `/auth/refresh`
Refresh token kullanarak yeni access token ve rotated refresh token döner.
```json
{ "refresh_token": "f3a9..." }
```

### POST `/auth/logout`
Oturumu kapatır ve kullanılan refresh token'ı veritabanından siler.
```json
{ "refresh_token": "f3a9..." }
```

### GET `/me` *(Bearer)*
```json
{ "id": 1, "email": "a@b.com", "display_name": "Mehmet", "username": "mehmet", "is_public": 1 }
```

### DELETE `/me` *(Bearer)*
Kullanıcıyı ve `ON DELETE CASCADE` sayesinde tüm verilerini (ratings, watchlist vb.) kalıcı olarak siler.

---

## 3. Senkronizasyon (delta-sync)

### GET `/sync?since=<unix_ms>&ack_cursor=<unix_ms>&device_id=<uuid>` *(Bearer)*

`ack_cursor`, cihazın başarıyla uyguladığı önceki pull cursor'udur. Aktif tüm
cihazlar bir silme cursor'unu onayladıktan ve saklama süresi dolduktan sonra
tombstone fiziksel olarak temizlenebilir. Uzun süre pasif kalan cihazlar
`sync_reset_required` alır ve push yapmadan önce tam pull gerçekleştirir.
`since` zamanından sonra değişen tüm kayıtları döner (silmeler `deleted:true` ile).
```json
{
  "server_time": 1719580000000,
  "ratings":         [ { "movie_id":603, "is_tv":0, "rating":3, "comment":"Müthiş film", "is_spoiler":0, "updated_at":..., "deleted":false }, ... ],
  "watchlist":       [ ... ],
  "favorites":       [ ... ],
  "watched_seasons": [ ... ],
  "search_history":  [ ... ]
}
```

### POST `/sync` *(Bearer)*
Yerel değişiklikleri sunucuya iter. Çakışma kuralı: **En yüksek `updated_at` (LWW) kazanır**.

Yorum doğrulaması (sunucu tarafı, istemciye güvenilmez):
- `comment` 280 karaktere kırpılır; URL'ler sökülür; kontrol karakterleri temizlenir; boş kalan yorum `NULL` olur.
- Basit TR+EN küfür/spam listesine takılan yorum `ratings.is_hidden = 1` ile otomatik gizlenir: kullanıcının kendi cihazında görünmeye devam eder ama başkalarına gösterilmez. Yorum metni değişince yeniden değerlendirilir (küfür temizlenirse görünürlük döner); metin değişmeden yapılan güncellemeler moderatör gizlemesini KALDIRMAZ. `is_hidden` sync kolonu değildir, istemciden gelen değeri yok sayılır.
```json
{
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "ack_cursor": 1719579900000,
  "ratings":   [ { "movie_id":603, "is_tv":0, "rating":3, "genre_ids":[28,878], "comment":"Yorum", "is_spoiler":0, "updated_at":1719579999000, "deleted":false } ],
  "watchlist": [ ... ]
}
// 200 Yanıt
{ "server_time": 1719580001000, "applied": 1 }
```

---

## 4. Sosyal Ağ & Sinema DNA API

### POST `/social/profile/setup` *(Bearer)*
Kullanıcı profil ayarlarını günceller.
```json
{ "username": "mehmet21", "is_public": true }
```

### GET `/social/friends` *(Bearer)*
Kabul edilmiş arkadaşları ve bekleyen (gelen/giden) istekleri döner.
```json
{
  "friends": [ { "id": 2, "display_name": "Ali", "username": "ali", "email": "ali@b.com" } ],
  "pending_received": [ ... ],
  "pending_sent": [ ... ]
}
```

### POST `/social/friends/request` *(Bearer)*
E-posta veya kullanıcı adına göre arkadaşlık isteği gönderir.
```json
{ "search_query": "ali" }
```

### POST `/social/friends/accept` / `/social/friends/reject` *(Bearer)*
Gelen arkadaşlık isteğini kabul eder veya reddeder.
```json
{ "friend_id": 2 }
```

### GET `/social/friends/activity` *(Bearer)*
Arkadaşların yaptığı son puanlama ve yorum aktivitelerini döner.
```json
[
  {
    "movie_id": 101,
    "is_tv": 0,
    "rating": 3,
    "title": "The Matrix",
    "poster_path": "/x.jpg",
    "comment": "Başyapıt.",
    "is_spoiler": 0,
    "updated_at": 1719580000000,
    "friend_id": 2,
    "friend_name": "Ali",
    "friend_username": "ali"
  }
]
```

### GET `/social/friends/signals` *(Bearer)*
Beğendiğiniz yapımları hangi arkadaşlarınızın da beğendiğine dair hızlı sinyalleri döner.
```json
{
  "signals": {
    "movie_101": ["Ali", "Mehmet"]
  }
}
```

### GET `/social/match/watchlist-intersection/{friend_id}` *(Bearer)*
Ortak izleme listesi (iki kullanıcının da watchlist'inde olan ve izlemediği yapımlar) kesişimini döner.

### GET `/social/match/taste/{friend_id}` *(Bearer)*
İki kullanıcının ortak puanladığı ve beğendiği yapımlara göre zevk uyumu yüzdesini (0-100) döner.

### POST `/social/dna` *(Bearer)*
Kullanıcının cihazda hesaplanmış Sinema DNA snapshot'ını (arketip, öne çıkan temalar vb.) sunucuya yükler.
```json
{
  "dna": {
    "archetype": "dark_chronicler",
    "themes": ["revenge", "dystopia"]
  }
}
```

### POST `/social/recommend` *(Bearer)*
Arkadaşa film/dizi önerir.
```json
{ "to_user_id": 2, "movie_id": 603, "is_tv": 0, "title": "The Matrix", "poster_path": "/x.jpg", "note": "Kesinlikle izlemelisin." }
```

### GET `/social/recommendations` *(Bearer)*
Kullanıcıya gelen önerileri listeler.

### POST `/social/recommendations/seen` *(Bearer)*
Gelen önerileri "görüldü" olarak işaretler.

### GET `/social/title-reviews/{type}/{id}` *(Bearer)*
Bir yapımın arkadaş ve topluluk yorumlarını döner. `is_hidden = 1` (moderasyon)
ve engellenen kullanıcıların (iki yönlü) yorumları filtrelenir. Her yorumda
şikayet/engelleme hedefi için `user_id` bulunur.
```json
{ "friends": [ { "user_id": 2, "rating": 3, "comment": "...", "is_spoiler": 0, ... } ], "community": [ ... ] }
```

### POST `/social/reviews/report` *(Bearer)*
Yorum şikayeti. Yorumlar `ratings` satırı olduğundan hedef `(user_id, movie_id, is_tv)` üçlüsüdür.
`reason`: `profanity | spam | spoiler | harassment | other`. Aynı kullanıcı aynı yorumu bir kez
şikayet edebilir; **3 farklı kullanıcıdan** açık şikayet birikince yorum otomatik gizlenir
(`ratings.is_hidden = 1`) ve yanıtta `auto_hidden: true` döner.
```json
{ "user_id": 2, "movie_id": 603, "is_tv": 0, "reason": "spam" }
```

### POST `/social/users/block` / `/social/users/unblock` *(Bearer)*
Kullanıcı engelleme: engellenenin yorumları/aktivitesi görünmez, mevcut arkadaşlık iki
yönde silinir. Gövde: `{ "user_id": 2 }`. Engel aktifken taraflar birbirine arkadaşlık
isteği de gönderemez — istek, engel bilgisini sızdırmamak için "Kullanıcı bulunamadı"
(404) ile reddedilir.

### GET `/social/users/blocked` *(Bearer)*
Engellenen kullanıcıların listesi.

### Birlikte Seç (canlı kanepe modu) — `/social/couch/*` *(Bearer)*
İki arkadaş kendi telefonlarından AYNI desteyi oylar; ilk karşılıklı beğenide
oturum `matched` olur. Canlılık websocket'le değil istemcinin ~2.5 sn'lik
poll'uyla sağlanır (paylaşımlı hosting). Karşı tarafın oy içeriği hiçbir uçta
dönmez — yalnızca ilerleme sayısı (`their_progress`) görünür.

- `POST /social/couch/create` — Gövde: `{ "friend_id": 2, "deck": [{"movie_id","is_tv","title","poster_path","vote_average"}] }`.
  Deste host istemcide kurulur (ortak izleme listesi + öneri motoru), 5-30 yapım.
  Her iki katılımcının açık oturumları iptal edilir (tek aktif oturum kuralı).
  Misafire `couch_invite` push'u gider. Dönen: `{ session }`.
- `GET /social/couch/active` — Katılımcısı olduğum en güncel canlı oturum
  (`pending|active|matched`); yoksa `{ "session": null }`.
- `GET /social/couch/{id}` — Poll ucu. Misafirin ilk teması `pending → active`.
- `POST /social/couch/{id}/vote` — Gövde: `{ "movie_id", "is_tv", "liked" }`.
  Oy kullanıcının kendi kolonuna yazılır (eşzamanlı oylar çakışmaz); yanıt
  güncel oturumu döner. Karşılıklı beğenide `status: "matched"` + `matched`
  yapımı; iki taraf desteyi bitirip eşleşme yoksa `status: "ended"`.
  Eşleşmede iki tarafa da `couch_match` push'u gider.
- `POST /social/couch/{id}/cancel` — Açık oturumda iptal; eşleşmiş oturumda
  kapanış (`ended`).

Oturum durumları: `pending → active → matched | ended` (+ `cancelled`).
Şema: `couch_sessions` (bkz. migration 014).

### GET/POST `/admin/moderation`
Moderasyon paneli (HTML): açık şikayetler, gizlenen yorumlar ve susturulan
kullanıcılar. Aksiyonlar (`POST /admin/moderation/action`): yorum bazlı gizle /
geri aç / şikayeti kapat; kullanıcı bazlı **sustur** (`ban_user`:
`users.review_banned = 1` — mevcut tüm yorumları gizler, sync'e gelen yeni
yorumlar da otomatik gizlenir, açık şikayetleri kapatır) ve **susturmayı kaldır**
(`unban_user`; eski yorumlar gizli kalır, tek tek geri açılır). Config'de
`admin_key` boşsa uç 404 döner.

---

## 5. Güvenlik & Migration Yöneticisi

- **HTTPS**: Tüm trafik HTTPS üzerinden geçmek zorundadır.
- **Veritabanı Güncelleme (Migration)**: Migration işlemleri web üzerinden çalıştırılamaz (`/run-migrations` ucu devre dışıdır). Veritabanını güncellemek için CLI üzerinden `php backend/migrate.php` betiği çalıştırılmalıdır.
  - `php migrate.php` -> Bekleyen SQL'leri sırayla uygular.
  - `php migrate.php --status` -> Mevcut migration durumunu listeler.
