/// TMDB keyword'lerinin zevk hakkında hiçbir şey söylemeyen kısmı.
///
/// Bunlar neredeyse her yapımda bulunduğu için, ağırlığı FREKANSLA biriken her
/// sıralamada yapısal olarak tepeye çıkar: "duringcreditsstinger" 15 tohumun
/// 12'sinde geçerken "time travel" birinde geçer. Filtrelenmezlerse hem zevk
/// vektörünü hem de ondan türeyen her şeyi (tema recall'ı, gerekçe etiketi,
/// DNA temaları) gürültü sürer.
const kKeywordStoplist = {
  'aftercreditsstinger',
  'duringcreditsstinger',
  'based on novel or book',
  'based on novel',
  'woman director',
  'live action',
  'sequel',
  'remake',
  // Kişi/rol belirten genel anahtarlar zevki açıklayan bir tema değildir.
  'man',
  'woman',
  'boy',
  'girl',
  'father',
  'mother',
  'son',
  'daughter',
  'king',
  'queen',
  'male protagonist',
  'female protagonist',
};

/// [name] zevki açıklamayan jenerik bir keyword mü? Boş ad da elenir.
bool isStoplistedKeyword(String name) {
  final normalized = name.toLowerCase().trim();
  return normalized.isEmpty || kKeywordStoplist.contains(normalized);
}
