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

-- ─── Kullanıcılar ────────────────────────────────────────────────
CREATE TABLE users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)    NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,   -- bcrypt/argon2 (asla düz metin)
  display_name  VARCHAR(100)    NULL,
  created_at    BIGINT          NOT NULL,
  updated_at    BIGINT          NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── Yenileme token'ları (refresh) ───────────────────────────────
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── Puanlar (ratings) ───────────────────────────────────────────
CREATE TABLE ratings (
  user_id      BIGINT UNSIGNED NOT NULL,
  movie_id     INT             NOT NULL,
  is_tv        TINYINT(1)      NOT NULL,
  rating       INT             NOT NULL,
  genre_ids    JSON            NULL,
  title        VARCHAR(512)    NULL,
  poster_path  VARCHAR(255)    NULL,
  backdrop_path VARCHAR(255)   NULL,
  overview     TEXT            NULL,
  vote_average DOUBLE          NULL,
  release_date VARCHAR(20)     NULL,
  popularity   DOUBLE          NULL,
  created_at   BIGINT          NOT NULL,
  updated_at   BIGINT          NOT NULL,   -- delta-sync için
  deleted      TINYINT(1)      NOT NULL DEFAULT 0,  -- soft delete (silmeyi de senkronla)
  PRIMARY KEY (user_id, movie_id, is_tv),
  KEY idx_ratings_sync (user_id, updated_at),
  CONSTRAINT fk_ratings_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Tasarım notları**
- Her tablo `(user_id, …)` ile başlayan composite PK kullanır — mevcut `(id, is_tv)` mantığının kullanıcı kapsamlı hali.
- `updated_at` + `deleted` (soft delete) ikilisi **delta senkronizasyonu** mümkün kılar: istemci "şu zamandan sonra değişenleri ver" der, silmeler de senkronlanır.
- Yabancı anahtarlar `ON DELETE CASCADE` — kullanıcı silinince tüm verisi temizlenir (KVKK/GDPR için pratik).

---

## 2. Kimlik Doğrulama (Auth)

JWT tabanlı. **Access token** kısa ömürlü (15 dk), **refresh token** uzun ömürlü (30 gün) ve DB'de hash'li tutulur.

### POST `/auth/register`
```json
// İstek
{ "email": "a@b.com", "password": "min8karakter", "display_name": "Mehmet" }
// 201 Yanıt
{ "user": { "id": 1, "email": "a@b.com", "display_name": "Mehmet" },
  "access_token": "eyJ...", "refresh_token": "f3a9..." }
// 409: email zaten kayıtlı
```

### POST `/auth/login`
```json
// İstek
{ "email": "a@b.com", "password": "..." }
// 200 Yanıt
{ "user": {...}, "access_token": "eyJ...", "refresh_token": "f3a9..." }
// 401: hatalı kimlik
```

### POST `/auth/refresh`
```json
{ "refresh_token": "f3a9..." }       // → yeni access (+ rotate edilmiş refresh)
```

### POST `/auth/logout`
```json
{ "refresh_token": "f3a9..." }       // refresh token'ı iptal eder
```

### GET `/me`  *(Bearer access token)*
```json
{ "id": 1, "email": "a@b.com", "display_name": "Mehmet" }
```

Tüm korumalı uçlar: `Authorization: Bearer <access_token>` başlığı zorunlu. Geçersiz/expired → `401`.

---

## 3. Senkronizasyon (delta-sync)

Tek tek CRUD yerine, offline-first için iki uçlu bir **çekme/itme** modeli en sağlamı.

### GET `/sync?since=<unix_ms>`  *(Bearer)*
`since` zamanından sonra değişen tüm kayıtları döner (silmeler `deleted:true` ile).
```json
{
  "server_time": 1719580000000,
  "ratings":         [ { "movie_id":603, "is_tv":0, "rating":3, "genre_ids":[28,878], "updated_at":..., "deleted":false }, ... ],
  "watchlist":       [ ... ],
  "favorites":       [ ... ],
  "watched_seasons": [ { "tv_id":1399, "season_number":1, "updated_at":..., "deleted":false }, ... ],
  "search_history":  [ ... ]
}
```
İstemci dönen `server_time`'ı saklar, bir sonraki `since` olarak kullanır.

### POST `/sync`  *(Bearer)*
İstemcideki yerel değişiklikleri sunucuya iter. Çakışma kuralı: **en yüksek `updated_at` kazanır** (last-write-wins; elinde zaten timestamp var).
```json
{
  "ratings":   [ { "movie_id":603, "is_tv":0, "rating":3, "genre_ids":[28,878], "updated_at":1719579999000, "deleted":false } ],
  "watchlist": [ { "id":603, "is_tv":0, "title":"The Matrix", "poster_path":"/x.jpg", "updated_at":..., "deleted":false } ],
  "favorites": [ ... ],
  "watched_seasons": [ ... ],
  "search_history":  [ { "query":"matrix", "created_at":..., "updated_at":..., "deleted":false } ]
}
// 200
{ "server_time": 1719580001000, "applied": 7 }
```

> Basit başlamak istersen, tablo başına ayrı uçlar da verilebilir (ör. `PUT /ratings`, `DELETE /ratings/{type}/{id}`). Ama tek `/sync` ucu offline senaryosunu (uçak modu → tekrar bağlanma) çok daha temiz yönetir.

---

## 4. Güvenlik kontrol listesi (hosting tarafı)

- [ ] **HTTPS zorunlu** — paketteki ücretsiz SSL'i aktif et, HTTP'yi HTTPS'e yönlendir (`.htaccess`).
- [ ] **Parola hash** — `password_hash()` / `PASSWORD_BCRYPT` (PHP yerleşik). Düz metin yok.
- [ ] **Parametreli sorgular** — yalnız PDO prepared statements. String birleştirme yok (SQL injection).
- [ ] **DB bilgileri web kök dizini dışında** bir `config.php`'de veya ortam değişkeninde. Repo'ya girmesin.
- [ ] **Rate limiting** — özellikle `/auth/login` ve `/auth/register` (brute-force'a karşı). LiteSpeed/`.htaccess` veya uygulama içi sayaç.
- [ ] **Girdi doğrulama** — email formatı, parola min uzunluk, rating aralığı (-2..3 vb.).
- [ ] **JWT secret** güçlü ve sunucuda gizli; rotasyon planı.
- [ ] **CORS** — sadece mobil istemci kullanıyorsa gevşek bırakma; gerekiyorsa kısıtla.
- [ ] **TMDB görsellerini proxy'leme** — trafik kotasını korumak için posterler doğrudan TMDB CDN'inden.

---

## 5. Önerilen klasör yapısı (PHP)

```
/api                      (web kök — public)
  index.php               (router / front controller)
  .htaccess               (HTTPS yönlendirme + tüm istekleri index.php'ye)
/src                      (web kök DIŞINDA)
  Config.php              (DB + JWT secret — gizli)
  Db.php                  (PDO bağlantısı, utf8mb4)
  Auth.php                (register/login/refresh/JWT)
  SyncController.php      (GET/POST /sync)
  Jwt.php                 (imzalama/doğrulama)
/migrations
  001_init.sql            (yukarıdaki şema)
```
```

Sonraki adım: bu sözleşmeye dayanan çalışan PHP iskeleti (auth + /sync).
