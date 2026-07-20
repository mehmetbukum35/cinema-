import 'package:flutter/material.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// cinema+ • Sinematik & lüks görsel dil
/// Tüm uygulama bu token'lar üzerinden beslenir. Renk adları korunmuştur
/// (geriye dönük uyumluluk), değerler premium hisse göre rafine edilmiştir.
/// ──────────────────────────────────────────────────────────────────────────
class AppColors {
  // Zemin & yüzey katmanları (sıcak undertone'lu derin gece siyahı)
  static const bg = Color(0xFF0A0A0C);
  static const bgWarm = Color(0xFF120E10); // arkaplan glow'u için sıcak ton
  static const surface = Color(0xFF15151A);
  static const card = Color(0xFF1C1C22);
  static const cardHi = Color(0xFF24242C); // hover/elevated kart

  static const dim = Color(0xFF9A9AA4); // ikincil metin — AA kontrast (~7:1)
  static const textPassive = Color(0xFF9A9AA4);
  static const textFaint = Color(0xFF6E6E78); // sadece dekoratif/iri metin

  // Marka aksanları
  static const red = Color(0xFFE94560); // marka kırmızısı
  static const crimson = Color(0xFFC9304E); // gradyan için derin kırmızı
  static const ember = Color(0xFFFF6B81); // parlak vurgu

  static const gold = Color(0xFFE9B872); // şampanya altını
  static const goldSoft = Color(0xFFCBA45E);
  static const goldDeep = Color(0xFFB8893E);

  static const green = Color(0xFF4CAF50);
  static const blue = Color(0xFF4A90E2);

  // Nav & kenarlık
  static const navBg = Color(0xFF0E0E12);
  static const border = Color(0xFF26262E);
  static const borderSoft = Color(0xFF1E1E25);

  // Cam (glassmorphism) dolgusu
  static const glassFill = Color(0x14FFFFFF); // %8 beyaz
  static const glassStroke = Color(0x1FFFFFFF); // ince üst ışık kenarı

  // Değerlendirme renkleri
  // rBerbat: Material Red 800 — beyaz etiket WCAG AA (~5.1:1); eski #E53935 ~4.2:1 idi.
  static const rBerbat = Color(0xFFC62828);
  static const rEh = Color(0xFFFDD835);
  static const rIyi = Color(0xFFFB8C00);
  static const rHarika = Color(0xFF43A047);

  /// Puan dolgusu üstünde okunur etiket rengi (açık sarı/turuncu/yeşil → koyu;
  /// koyu kırmızı → beyaz).
  static Color onRatingFill(Color fill) =>
      fill.computeLuminance() > 0.22 ? const Color(0xFF121212) : Colors.white;
}

/// Sinematik gradyanlar.
class CinemaGradients {
  static const crimson = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.red, AppColors.crimson],
  );

  static const gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.gold, AppColors.goldDeep],
  );

  /// Kart/poster üstüne okunabilirlik için alttan koyulaşan örtü.
  static const posterScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000), Color(0xF2000000)],
    stops: [0.35, 0.78, 1.0],
  );

  /// Yüzeylere ince derinlik veren dikey gradyan.
  static const surfaceSheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF20202A), Color(0xFF14141A)],
  );
}

/// Yumuşak, sinematik gölge & glow setleri.
class CinemaShadows {
  static List<BoxShadow> get card => const [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 24,
      spreadRadius: -4,
      offset: Offset(0, 12),
    ),
  ];

  static List<BoxShadow> glow(Color color, {double strength = 0.45}) => [
    BoxShadow(
      color: color.withValues(alpha: strength),
      blurRadius: 28,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get redGlow => glow(AppColors.red);
  static List<BoxShadow> get goldGlow => glow(AppColors.gold, strength: 0.40);
}

/// Premium tipografi ölçeği (sistem fontu + rafine letter-spacing & ağırlık).
class CinemaText {
  static TextTheme theme(TextTheme base) => base.copyWith(
    displayLarge: const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.12,
      color: Colors.white,
    ),
    headlineMedium: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.18,
      color: Colors.white,
    ),
    titleLarge: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: Colors.white,
    ),
    titleMedium: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: Colors.white,
    ),
    bodyMedium: const TextStyle(
      fontSize: 14,
      height: 1.45,
      color: Color(0xFFD6D6DC),
    ),
    labelLarge: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2, // kibar tracking — lüks his
      color: AppColors.dim,
    ),
  );

  /// Bölüm başlıkları için (örn. "TREND", "SANA ÖZEL") — geniş tracking.
  static const overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    color: AppColors.gold,
  );

  /// Açık tema için tipografi (koyu metin renkleriyle). Koyu [theme] aynen korunur.
  static TextTheme lightTheme(TextTheme base) => base.copyWith(
    displayLarge: const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.12,
      color: AppColorsLight.ink,
    ),
    headlineMedium: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.18,
      color: AppColorsLight.ink,
    ),
    titleLarge: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: AppColorsLight.ink,
    ),
    titleMedium: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColorsLight.ink,
    ),
    bodyMedium: const TextStyle(
      fontSize: 14,
      height: 1.45,
      color: Color(0xFF3A352E),
    ),
    labelLarge: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: AppColorsLight.dim,
    ),
  );
}

/// ──────────────────────────────────────────────────────────────────────────
/// AÇIK TEMA — sıcak / sinematik beyaz palet.
/// Bu sınıf yalnızca EK'tir; koyu [AppColors] hiçbir şekilde değişmez.
/// Alan adları AppColors ile birebir aynıdır ki ileride ekran taşımaları
/// mekanik olsun. Marka kırmızısı ve altını korunur, yalnızca nötrler açılır.
/// ──────────────────────────────────────────────────────────────────────────
class AppColorsLight {
  // Zemin & yüzey (sıcak kağıt beyazı)
  static const bg = Color(0xFFFAF6EF); // sıcak kağıt zemin
  static const bgWarm = Color(0xFFF4ECE0); // glow için sıcak ton
  static const surface = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFDF8); // hafif sıcak beyaz kart
  static const cardHi = Color(0xFFFFFFFF);

  static const ink = Color(0xFF1C1813); // birincil metin (sıcak koyu)
  static const dim = Color(0xFF6B6660); // ikincil metin — AA kontrast
  static const textPassive = Color(0xFF6B6660);
  static const textFaint = Color(0xFFA8A095);

  // Marka aksanları (koyu tema ile aynı kimlik)
  static const red = Color(0xFFE94560);
  static const crimson = Color(0xFFC9304E);
  static const ember = Color(0xFFFF6B81);

  // Krem zeminde metin olarak kullanıldığında WCAG AA (~4.5:1+) için koyu bronz.
  static const gold = Color(0xFF7A5A20);
  static const goldSoft = Color(0xFF8A6520);
  static const goldDeep = Color(0xFF7A5A20);

  static const green = Color(0xFF2E7D32);
  static const blue = Color(0xFF1F6BBA);

  // Nav & kenarlık
  static const navBg = Color(0xFFFFFFFF);
  static const border = Color(0xFFE7DFD2);
  static const borderSoft = Color(0xFFF0E9DD);

  // Cam (açık zeminde ince koyu cam)
  static const glassFill = Color(0x0D1A1208);
  static const glassStroke = Color(0x14000000);

  // Değerlendirme renkleri (beyazda okunur tonlar)
  static const rBerbat = Color(0xFFC62828);
  static const rEh = Color(0xFFF4A720);
  static const rIyi = Color(0xFFFB8C00);
  static const rHarika = Color(
    0xFF2E7D32,
  ); // yeşil metin/çubuk AA; dolgu butonunda koyu etiket
}

/// Çalışma anında değiştirilebilir renk seti. Koyu/açık değerleri tek arayüzde
/// toplar; widget'lar `context.c.bg` ile aktif temayı okur (ileride taşıma için).
class ThemePalette {
  final Brightness brightness;
  final Color bg, bgWarm, surface, card, cardHi;
  final Color ink, dim, textPassive, textFaint;
  final Color red, crimson, ember;
  final Color gold, goldSoft, goldDeep;
  final Color green, blue;
  final Color navBg, border, borderSoft;
  final Color glassFill, glassStroke;
  final Color rBerbat, rEh, rIyi, rHarika;

  const ThemePalette({
    required this.brightness,
    required this.bg,
    required this.bgWarm,
    required this.surface,
    required this.card,
    required this.cardHi,
    required this.ink,
    required this.dim,
    required this.textPassive,
    required this.textFaint,
    required this.red,
    required this.crimson,
    required this.ember,
    required this.gold,
    required this.goldSoft,
    required this.goldDeep,
    required this.green,
    required this.blue,
    required this.navBg,
    required this.border,
    required this.borderSoft,
    required this.glassFill,
    required this.glassStroke,
    required this.rBerbat,
    required this.rEh,
    required this.rIyi,
    required this.rHarika,
  });

  bool get isLight => brightness == Brightness.light;

  List<BoxShadow> get cardShadow => brightness == Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x0F1A1208), // Çok hafif sıcak/koyu gölge
            blurRadius: 16,
            spreadRadius: -2,
            offset: Offset(0, 8),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            spreadRadius: -4,
            offset: Offset(0, 12),
          ),
        ];
}

const kDarkPalette = ThemePalette(
  brightness: Brightness.dark,
  bg: AppColors.bg,
  bgWarm: AppColors.bgWarm,
  surface: AppColors.surface,
  card: AppColors.card,
  cardHi: AppColors.cardHi,
  ink: Colors.white,
  dim: AppColors.dim,
  textPassive: AppColors.textPassive,
  textFaint: AppColors.textFaint,
  red: AppColors.red,
  crimson: AppColors.crimson,
  ember: AppColors.ember,
  gold: AppColors.gold,
  goldSoft: AppColors.goldSoft,
  goldDeep: AppColors.goldDeep,
  green: AppColors.green,
  blue: AppColors.blue,
  navBg: AppColors.navBg,
  border: AppColors.border,
  borderSoft: AppColors.borderSoft,
  glassFill: AppColors.glassFill,
  glassStroke: AppColors.glassStroke,
  rBerbat: AppColors.rBerbat,
  rEh: AppColors.rEh,
  rIyi: AppColors.rIyi,
  rHarika: AppColors.rHarika,
);

const kLightPalette = ThemePalette(
  brightness: Brightness.light,
  bg: AppColorsLight.bg,
  bgWarm: AppColorsLight.bgWarm,
  surface: AppColorsLight.surface,
  card: AppColorsLight.card,
  cardHi: AppColorsLight.cardHi,
  ink: AppColorsLight.ink,
  dim: AppColorsLight.dim,
  textPassive: AppColorsLight.textPassive,
  textFaint: AppColorsLight.textFaint,
  red: AppColorsLight.red,
  crimson: AppColorsLight.crimson,
  ember: AppColorsLight.ember,
  gold: AppColorsLight.gold,
  goldSoft: AppColorsLight.goldSoft,
  goldDeep: AppColorsLight.goldDeep,
  green: AppColorsLight.green,
  blue: AppColorsLight.blue,
  navBg: AppColorsLight.navBg,
  border: AppColorsLight.border,
  borderSoft: AppColorsLight.borderSoft,
  glassFill: AppColorsLight.glassFill,
  glassStroke: AppColorsLight.glassStroke,
  rBerbat: AppColorsLight.rBerbat,
  rEh: AppColorsLight.rEh,
  rIyi: AppColorsLight.rIyi,
  rHarika: AppColorsLight.rHarika,
);

/// Aktif paleti context'ten okumak için kısayol: `context.c.bg`.
/// MaterialApp.themeMode parlaklığı belirler; bu uzantı ona göre palet döndürür.
extension PaletteX on BuildContext {
  ThemePalette get c => Theme.of(this).brightness == Brightness.light
      ? kLightPalette
      : kDarkPalette;
}
