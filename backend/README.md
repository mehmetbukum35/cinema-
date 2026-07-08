# Ne Izlesem? - Backend (PHP + MySQL/MariaDB)

Paylasimli LiteSpeed hosting icin tasarlanmis REST API.
Mimari: `Flutter app -> bu PHP API -> MySQL/MariaDB`. Ana veri akisi tek `/sync` ucuyla, nadir/tekil islemler (hesap, parola, gecmis temizleme) klasik uclarla ilerler.

## Kurulum (cPanel / LiteSpeed)

1. **Veritabanı oluştur** (cPanel > MySQL Databases): bir DB + bir kullanıcı, kullanıcıyı DB'ye tam yetkiyle ekle.
2. **Şemayı yükle**: phpMyAdmin > İçe Aktar > `migrations/database.sql`.
3. **Config hazırla**: `src/Config.sample.php` → `src/Config.php` olarak kopyala, DB bilgileri ve `jwt_secret` doldur.
   `jwt_secret` üretmek için (terminalde): `php -r "echo bin2hex(random_bytes(32));"`
4. **Dosyaları yükle**:
   - `api/` klasörünün içeriği → sitenin **public** kökü (ör. `public_html/api/`).
   - `src/` ve `migrations/` → public kök **DIŞINA** taşımak en güvenlisi. Mümkün değilse en azından `src/Config.php`'yi `.htaccess` ile koru.
5. **SSL'i aktif et** (pakette ücretsiz var). `.htaccess` zaten HTTP→HTTPS yönlendiriyor.
6. **Test**: `https://alanadi.com.tr/api/health` → `{"ok":true,...}` dönmeli.

## Yerel gelistirme

```bash
composer install
php -S localhost:8000 -t api
composer test
```

## Uçlar

Tüm korumalı uçlar istek başlığında `Authorization: Bearer <access_token>` gerektirir.

### Kimlik Doğrulama ve Hesap Yönetimi (Auth)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| POST | `/auth/register` | E-posta ve şifre ile yeni kullanıcı kaydı | – |
| POST | `/auth/login` | Klasik kullanıcı girişi | – |
| POST | `/auth/google` | Google OAuth token ile giriş/kayıt | – |
| POST | `/auth/forgot-password` | Şifremi unuttum e-postası tetikleme | – |
| POST | `/auth/verify-reset-code` | Şifre sıfırlama kodunu doğrulama | – |
| POST | `/auth/reset-password` | Yeni şifre belirleme | – |
| POST | `/auth/refresh` | Access token yenileme (refresh token rotasyonlu) | – |
| POST | `/auth/logout` | Oturumu sonlandırma (refresh token iptal) | – |
| POST | `/auth/change-password` | Mevcut şifreyi değiştirme (tüm oturumları düşürür) | Bearer |
| GET | `/me` | Giriş yapmış kullanıcı profil bilgilerini getirir | Bearer |
| DELETE | `/me` | Kullanıcı hesabını ve tüm ilişkili verileri siler | Bearer |

### Senkronizasyon (Sync - Offline First)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| GET | `/sync?since=<ms>` | Belirtilen zamandan sonra değişen tüm verileri çeker | Bearer |
| POST | `/sync` | Yerel veri değişikliklerini sunucuya iter (çakışmada son yazan kazanır) | Bearer |
| DELETE | `/sync` | Kullanıcının sunucudaki tüm senkronizasyon verilerini sıfırlar | Bearer |
| DELETE | `/search-history` | Arama geçmişini temizler (tekil uç) | Bearer |

### Sosyal Ağ ve Arkadaşlar (Social)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| POST | `/social/profile/setup` | Sosyal profil ayarlarını (kullanıcı adı, gizlilik vb.) günceller | Bearer |
| GET | `/social/friends` | Arkadaş listesini (bekleyen, gönderilen, kabul edilen) getirir | Bearer |
| POST | `/social/friends/request` | Başka bir kullanıcıya arkadaşlık isteği gönderir | Bearer |
| POST | `/social/friends/accept` | Gelen arkadaşlık isteğini kabul eder | Bearer |
| POST | `/social/friends/reject` | Arkadaşlık isteğini reddeder veya iptal eder | Bearer |
| GET | `/social/friends/activity` | Arkadaşların aktivite akışını getirir | Bearer |
| GET | `/social/friends/signals` | Yeni bildirimleri/sinyalleri getirir | Bearer |

### Sinema DNA ve Öneriler (Taste DNA & Recommendations)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| POST | `/social/dna` | Yerel olarak hesaplanan Sinema DNA snapshot'ını sunucuda yayınlar | Bearer |
| POST | `/social/recommend` | Bir arkadaşa film/dizi önerir (başlık ve not ile) | Bearer |
| GET | `/social/recommendations` | Gelen film/dizi önerilerini listeler (inbox) | Bearer |
| POST | `/social/recommendations/seen` | Tüm gelen önerileri okundu olarak işaretler | Bearer |
| GET | `/social/match/taste/{friend_id}` | Belirtilen arkadaşla Sinema DNA eşleşme skorunu getirir | Bearer |
| GET | `/social/match/watchlist-intersection/{friend_id}` | Ortak izleme listesi kesişimini getirir | Bearer |

### Yorumlar ve Skorlar (Reviews & Scores)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| GET | `/social/title-reviews/{type}/{id}` | Yapım için arkadaşların ve diğer kullanıcıların yorumlarını listeler | Bearer |
| GET | `/titles/{type}/{id}/score` | cinema+ topluluğunun bu yapım için verdiği puanların özetini getirir | Bearer |

### Yardımcı ve Dinamik Uçlar (Utility & Dynamic Routes)

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| GET | `/health` | API sağlık durumu kontrolü (Veritabanı bağlantısı dahil) | – |
| GET | `/profile/{username}` | Kullanıcının herkese açık web profil kartını render eder | – |
| GET | `/download` | Uygulama indirme yönlendirme sayfası (Web) | – |
| GET | `/tmdb/*` | Sunucu üzerinden rate-limit'li TMDB istek proxy'si | – |

## Güvenlik notları

- Parolalar `password_hash()` (bcrypt) ile. Refresh token'lar DB'de **SHA-256 hash'li** tutulur, ham hali saklanmaz.
- Tüm sorgular PDO **prepared statement** — SQL injection yok.
- `/auth/login` ve `/auth/register` dosya tabanlı basit **rate-limit** ile korunur (ölçeklenince Redis/DB'ye taşı).
- `Config.php` repoya girmez (`.gitignore`), web kökü dışında durmalı.
- TMDB görsellerini bu API üzerinden **proxy'leme** — 10 GB trafik kotanı korumak için posterler doğrudan TMDB CDN'inden gelsin.

## Hızlı manuel test (curl)

```bash
BASE=https://alanadi.com.tr/api

# Kayıt
curl -s -X POST $BASE/auth/register -H 'Content-Type: application/json' \
  -d '{"email":"a@b.com","password":"sifre1234","display_name":"Mehmet"}'

# Giriş → access_token al
curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"a@b.com","password":"sifre1234"}'

# Değişiklik it
curl -s -X POST $BASE/sync -H "Authorization: Bearer ACCESS" -H 'Content-Type: application/json' \
  -d '{"ratings":[{"movie_id":603,"is_tv":0,"rating":3,"genre_ids":[28,878],"title":"The Matrix","updated_at":1719579999000,"deleted":false}]}'

# Çek
curl -s "$BASE/sync?since=0" -H "Authorization: Bearer ACCESS"
```

## Production Smoke Testing & Verification

The PHP/MySQL backend is deployed and verified. To perform a production smoke test, run the following steps:

1. **Verify Health Endpoint:**
   Ensure the server is running and database connection is healthy:
   ```bash
   curl -s https://cinema.mbkm.com.tr/api/health
   # Expected response: {"ok":true,"time":1719580000000}
   ```

2. **Verify User Registration & Login:**
   Ensure registration and authentication flows are functional:
   ```bash
   # Register a test account
   curl -s -X POST https://cinema.mbkm.com.tr/api/auth/register \
     -H 'Content-Type: application/json' \
     -d '{"email":"test_smoke@example.com","password":"smoke_password123","displayName":"Smoke Test"}'

   # Login with the test account
   curl -s -X POST https://cinema.mbkm.com.tr/api/auth/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"test_smoke@example.com","password":"smoke_password123"}'
   ```

3. **Verify Sync Flow:**
   Push a movie rating and pull it back to confirm delta-sync database transactions:
   ```bash
   # Sync push (use access token returned from login)
   curl -s -X POST https://cinema.mbkm.com.tr/api/sync \
     -H "Authorization: Bearer <ACCESS_TOKEN>" \
     -H 'Content-Type: application/json' \
     -d '{"ratings":[{"movie_id":603,"is_tv":0,"rating":3,"genre_ids":[28,878],"title":"The Matrix","updated_at":1719579999000,"deleted":false}]}'

   # Sync pull
   curl -s "https://cinema.mbkm.com.tr/api/sync?since=0" \
     -H "Authorization: Bearer <ACCESS_TOKEN>"
   ```

4. **Verify Hosting Configuration:**
   - The fallback for `$SRC` directory structure inside `backend/api/index.php` dynamically checks `/home/mbkmcomt/etc/src` and falls back to `dirname(__DIR__) . '/src'`.
   - Ensure the server runs with PHP 8.2+ and has proper `.htaccess` configuration to route requests to `index.php`.

