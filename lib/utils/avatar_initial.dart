/// Avatar için güvenli baş harf üretir.
///
/// `display_name` sunucuda boş string ("") olarak kaydedilebildiğinden
/// `displayName ?? username` fallback'i boş adı yakalamaz; ardından gelen
/// `name[0]` erişimi boş string'de `RangeError` fırlatıp ekranı çökertir.
/// Bu yardımcı önce [primary]'yi, boşsa [fallback]'i dener; ikisi de boşsa
/// '?' döner — hiçbir durumda çökmez.
String avatarInitial(String? primary, [String? fallback]) {
  final p = primary?.trim() ?? '';
  if (p.isNotEmpty) return p[0].toUpperCase();
  final f = fallback?.trim() ?? '';
  if (f.isNotEmpty) return f[0].toUpperCase();
  return '?';
}
