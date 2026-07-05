# cinema+

**cinema+** (Ne Izlesem?), film ve dizi karar felcini azaltmak icin tasarlanmis, swipe arayuzlu modern bir mobil kesif ve sosyal paylasim uygulamasidir.

Bu depo, hem Flutter mobil uygulamasini hem de PHP backend API servisini barindiran bir monorepodur.

## Proje Yapisi

- `/` - Flutter mobil uygulamasi (Android/iOS/Web/Desktop hedefleri).
- `/backend` - MySQL/MariaDB veritabani ile delta senkronizasyonu saglayan PHP backend API servisi.

## One Cikan Ozellikler

- **Swipe arayuzu**: Hizli ve dinamik kart kaydirma arayuzu ile film/dizi puanlama.
- **Detayli arama ve filtreleme**: Yil araligi, puan, orijinal dil ve yayin servisi filtreleri.
- **Film/dizi detaylari**: Fragman, oyuncu kadrosu, yorumlar ve yayin platformlari.
- **Istatistikler**: Tur tercihleri ve puan dagilimi.
- **Sosyal akis**: Arkadas ekleme, arkadas aktiviteleri ve ortak izleme listeleri.
- **Iki yonlu delta sync**: Cevrimdisi degisiklikleri yerel SQLite'tan PHP backend'e senkronize eder.

## Kurulum ve Calistirma

### Frontend (Flutter)

Bagimliliklari kurun:

```bash
flutter pub get
```

Uygulama TMDB isteklerini artik dogrudan degil, backend/ altindaki PHP API'nin `GET /tmdb/*` proxy ucu uzerinden yapiyor (bkz. backend/src/Tmdb.php). TMDB API anahtari yalnizca sunucudaki `Config.php` icinde (`tmdb_api_key`) tutulur; Flutter tarafinda **artik TMDB_API_KEY dart-define'ina gerek yoktur**. Backend adresi ortam bazli degistirilebilir.

```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-domain.example/cinema/api \
  --dart-define=WEB_PROFILE_BASE_URL=https://your-domain.example/cinema/profile
```

`API_BASE_URL` ve `WEB_PROFILE_BASE_URL` verilmezse uygulama varsayilan production adreslerini kullanir.

Testleri calistirma:

```bash
flutter test
```

### Backend (PHP)

PHP backend API'si PHP 8.2+ ve MySQL/MariaDB kullanir.

Bagimliliklari kurun:

```bash
cd backend
composer install
```

Yerel gelistirme sunucusu:

```bash
php -S localhost:8000 -t api
```

Backend testleri:

```bash
composer test
```

## Teknik Mimari

- **State management**: Riverpod
- **Yerel veri**: SQLite (sqflite) ve Shared Preferences
- **Network ve sync**: HTTP, JWT token rotasyonu ve delta senkronizasyonu
- **Backend**: PHP 8.2+, minimalist router ve MySQL/MariaDB

## Kalite Kontrolleri

```bash
flutter analyze
flutter test
cd backend && composer test
```
