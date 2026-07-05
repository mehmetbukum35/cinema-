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

| Yöntem | Yol | Açıklama | Auth |
|---|---|---|---|
| POST | `/auth/register` | Kayıt | – |
| POST | `/auth/login` | Giriş | – |
| POST | `/auth/refresh` | Access token yenile (refresh rotasyonlu) | – |
| POST | `/auth/logout` | Refresh token iptal | – |
| GET  | `/me` | Profil | Bearer |
| POST | `/auth/change-password` | Parola değiştir (tüm oturumları düşürür) | Bearer |
| DELETE | `/me` | Hesabı + tüm veriyi sil | Bearer |
| GET  | `/sync?since=<ms>` | since'ten sonra değişenleri çek | Bearer |
| POST | `/sync` | Yerel değişiklikleri it (last-write-wins) | Bearer |
| DELETE | `/search-history` | Arama geçmişini temizle (tekil uç) | Bearer |
| GET  | `/health` | Sağlık kontrolü | – |

Korumalı uçlarda başlık: `Authorization: Bearer <access_token>`

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

## Önemli uyarı

Bu kod, sözdizimi açısından gözden geçirildi ancak **çalışan bir PHP/MySQL ortamında henüz test edilmedi** (geliştirme sandbox'ında PHP yoktu). Sunucuya yükledikten sonra `/health` ve `register/login` akışını yukarıdaki curl'lerle doğrula; bir sorun çıkarsa logları paylaş, birlikte düzeltelim.
