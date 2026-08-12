# Keyword sinyalinin recall ve sıralamaya girmesi

**Tarih:** 2026-08-12 · **Durum:** onaylandı, uygulamaya hazır

## Problem

### 1. Re-rank, uyguladığı dilimi cezalandırıyor

`rankForYou` kaba sıralamayı `genreOnlyWeights` ile yapıyor, ilk `rerankK = 20`
adayı `fullWeights` ile yeniden puanlıyor, sonra listenin **tamamını** tek
seferde sıralıyor (`lib/services/recommendation_engine.dart:899-987`). İki
ağırlık kümesi farklı ölçekler:

- Re-rank görmeyen aday: `0.78·genre + 0.22·vote`
- Re-rank gören aday: `0.50·genre + 0.30·kw + 0.20·vote`

`genre = 0.5`, `vote = 8.0` için re-rank görmeyen **0.566**, re-rank gören
(`kw = 0`) **0.41** alıyor. 0.156'lık bu düşüş motordaki her boost'tan büyük:
arkadaş sinyali 0.18, kültür 0.125, tohum kesişimi 0.10.

Başabaş noktası `kwSim ≥ 0.52`. Ama `kwSim`, ~100 elemanlı seyrek bir kullanıcı
keyword vektörüyle filmin en fazla 15 keyword'ü arasındaki kosinüs — tipik değeri
0.1–0.3 bandında. Yani **ilk 20 aday, keyword eşleşmesi olağanüstü güçlü
olmadıkça sırf ölçek uyuşmazlığı yüzünden 21+ sıradakilerin altına düşüyor.**

Kodun kendi yorumları bunun kasıtlı olmadığını gösteriyor: iki ağırlık demeti
"keyword sinyali yokken" / "keyword sinyali varken" diye tanımlanmış — tüm liste
için alternatif modlar, tek listenin içinde karıştırılacak şeyler değil.

### 2. Tematik aday havuza hiç girmiyor

Aday havuzu tür-bazlı discover, trending, tohumların TMDB similar/recommendations
listeleri ve kültür discover'ından geliyor. Kullanıcının temasına uyan ama türü
profiline uymayan bir yapım bunların hiçbirinden gelmiyor: zihinsel bilimkurguyu
seven birine aynı temayı işleyen bir dram, Drama ağırlığı düşük olduğu için hiç
ulaşmıyor.

## Hedef

Keyword sinyali hem havuzun bileşiminde hem sıralamada gerçekten söz sahibi
olsun — kodun kendi yorumunun ona atfettiği rolü (`similarityScore` üstündeki
"tema benzerliği türden güçlüdür" notu) fiilen üstlensin.

## Hedef olmayanlar

- `toDisplayScore` / Faz 2 persentil eşlemesi (ayrı ve ertelenmiş iş)
- Couch (Birlikte Seç) destesi — ortak deste, farklı amaç, havuzu trending+popular
- Keyword sinyalinin A/B ile ölçülmesi (tek kullanıcı, ölçüm anlamsız)

## Kararlar

| Karar | Seçim |
|---|---|
| Ölçek çözümü | Herkese tek formül (`fullWeights`), eksik `kwSim` ortalamayla atanır |
| İstek bütçesi | Yükleme başına ~55 istek (bugün ~39) |
| Recall yolu | `with_keywords` discover, kullanıcının tepe 5 pozitif keyword'ü |
| Uygulandığı yüzeyler | Keşfet ("Sana Özel") ve swipe kuyruğu |
| Teslim | İki commit: önce sıralama, sonra recall (bisect edilebilsin) |

---

## Parça 1 — Sıralamayı tek ölçeğe getirmek

Bugünkü üç adım (puanla → sırala → dilimi yeniden puanla) dört adıma dönüşür,
ama **puanlama tek kalır**:

1. **Ön eleme skoru** (`genre + vote`) — yalnızca kimin keyword'ü çekileceğini
   seçmek için. Sıralama değil, seçim.
2. **Keyword çekimi** — ön elemede tepe `keywordFetchK` + keyword-discover'dan
   gelen adaylar (Parça 2), paralel.
3. **`kwSim` ataması** — çekilenlerde gerçek kosinüs; çekilmeyenlerde
   **bilinenlerin ortalaması**.
4. **Tek nihai puanlama** — herkes `fullWeights` ile; ardından mevcut
   ceza/boost/arkadaş/çeşitlilik zinciri değişmeden uygulanır.

### Neden ortalama, neden sıfır değil

Sıfır atamak "cache'te olmak"ı sıralama sinyaline çevirir: keyword'ü bilinen
aday pozitif bir değer alabilirken bilinmeyen tavanı sıfır olan bir cezaya
mahkûm olur. Üstelik cache'te olanlar geçmişte üst sıralara girmiş olanlardır —
kendini pekiştiren bir döngü.

Ortalama ataması bunu kırar: bilgi, adayı ortalamaya göre yukarı **ya da aşağı**
taşır; bilgisizlik nötr kalır.

### Parametre

`rerankK = 20` → `keywordFetchK = 30`. Hiçbir çağrı yeri bu parametreyi açıkça
geçmiyor, rename güvenli.

### Soğuk başlangıç

Keyword vektörü boşsa (hiç oy, hiç favori) hem çekim hem discover tamamen
atlanır; puanlama bugünkü `genreOnlyWeights` yoluna düşer ve hiç ek istek
yapılmaz. Yeni kullanıcı boşuna beklemesin.

### Yan kazanç

`penalty + overlap + cultureBoost + contextBoost` bloğu şu an
`recommendation_engine.dart:846` ve `:922`'de birebir iki kez yazılı — final
incelemenin bakım riski olarak işaretlediği tekrar. Tek puanlama adımı bu
tekrarı ortadan kaldırıyor.

### Bilinçli ödünleşim

Ortalama ataması bir adayın skorunu havuzun bileşimine bağımlı kılar; aynı film
farklı bir havuzda farklı puan alabilir. Sıralama zaten havuz içi olduğundan
sıraya etkisi yok. Etkilenen `personalizedMatchScore`, o da Faz 2'ye kadar
hâlihazırda dar bir banda sıkışmış durumda.

---

## Parça 2 — Keyword discover (recall)

### TMDB katmanı

`discover()`'a `String? keywordStr` parametresi eklenir, sorguya
`with_keywords` olarak geçer. TMDB'de `|` OR, `,` AND anlamına gelir; OR
kullanılır — kullanıcının temalarından **herhangi biri** yeter.

Ayrıca `getKeywordEntries(int id, {bool isTV})` eklenir: aynı önbellek
girdisinden `({int id, String name})` çiftleri döndürür, **sıfır ek ağ isteği**
(`getKeywords` ve `getKeywordIds` zaten aynı `/keywords` yanıtını paylaşıyor).
Mevcut iki metot farklı `take()` sınırları ve farklı filtreler kullandığı için
indeks hizası güvenli değil — bu yüzden ayrı metot, mevcutlara dokunulmaz.

### Motor katmanı

`fetchKeywordCandidates()`:

1. `buildUserKeywordVector()`'dan ağırlığı pozitif tepe 5 keyword id'si alınır.
2. Vektör boşsa boş liste döner (soğuk başlangıç).
3. `discover(keywordStr: ids.join('|'), ...)` ile en fazla 2 istek
   (`DiscoveryContext.media`'ya saygı duyarak film/dizi).
4. Gelen adaylara `recoSource = 'keyword'`, `recoReasonType = 'keyword'`,
   `recoReason = <keyword adı>` yazılır.

Keyword adları `getKeywordEntries` ile tohumların önbellekli yanıtlarından
toplanır; ad bulunamazsa `recoReason` null bırakılır (rozet gerekçesiz gösterilir,
sıralama etkilenmez).

### Recall'ın ranking tarafından yutulmaması

Keyword-discover'dan gelen aday tür bakımından zayıf olduğu için ön elemede
150. sıraya düşebilir; keyword'ü çekilmezse ortalamaya sabitlenir ve hiç
yükselemez — yani recall düzeltmesi ranking aşamasında kaybolur.

Bu yüzden çekim kümesi şudur: **ön elemede tepe `keywordFetchK`** ∪ **keyword
kaynaklı adaylardan en fazla 10 tanesi**.

### Çağrı yerleri

- `lib/screens/browse_screen.dart` — aday havuzuna `fetchSeedCandidates`'ın yanına
- `lib/providers/swipe_provider.dart` — aynı şekilde
- Couch değişmez.

### Bütçe muhasebesi

| | bugün | sonra |
|---|---|---|
| discover / trending | 4 | 4 |
| tohum (similar+recommendations) | ≤12 | ≤12 |
| kültür discover | ≤3 | ≤3 |
| keyword discover | 0 | ≤2 |
| keyword çekimi | ≤20 | ≤30 |
| **toplam** | **~39** | **~51** |

Keyword uçları diskte önbelleklendiğinden tekrar yüklemelerde fark kapanır.

---

## Test stratejisi

**Ölçek (Parça 1)**
- Aynı `genre`/`vote` değerlerine sahip iki adaydan biri keyword'ü bilinen ve
  `kwSim` tam olarak ortalamaya eşit olan, diğeri bilinmeyen olsun: skorları
  eşit çıkmalı. Bu, ölçek tutarlılığının doğrudan testi.
- `kwSim` ortalamanın üstündeki aday, bilinmeyene göre yükselmeli; altındaki
  düşmeli.
- Hiçbir adayın keyword'ü bilinmiyorsa (boş vektör) `genreOnlyWeights` yoluna
  düşülmeli ve hiç keyword isteği yapılmamalı.
- Ceza/boost bloğunun tek kopya olduğu: aynı adayın nihai skoru, elle hesaplanan
  `blend + penalty + overlap + culture + context` toplamına eşit olmalı.

**Recall (Parça 2)**
- `discover(keywordStr: '1|2')` sorguya `with_keywords=1|2` koymalı.
- `getKeywordEntries` id ve adı doğru eşleştirmeli, ek istek yapmamalı
  (mock client çağrı sayısıyla doğrulanır).
- Keyword vektörü boşken `fetchKeywordCandidates` boş dönmeli ve hiç istek
  yapmamalı.
- Keyword kaynaklı aday, ön elemede son sırada olsa bile çekim kümesine girmeli.
- Gelen adaylarda `recoSource`/`recoReasonType`/`recoReason` doğru olmalı.

## Teslim sırası

1. **Commit 1 — Parça 1:** ölçek düzeltmesi, ortalama ataması, `keywordFetchK`,
   tekrar eden bloğun kaldırılması, testleri.
2. **Commit 2 — Parça 2:** `with_keywords`, `getKeywordEntries`,
   `fetchKeywordCandidates`, garanti slot, çağrı yerleri, testleri.

Ayrı commit'ler bilinçli: kuyruk kötüleşirse hangi parçanın sebep olduğu
bisect ile ayrılabilsin.
