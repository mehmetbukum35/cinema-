<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

/**
 * Sync (delta-sync) için GERÇEK veritabanı entegrasyon testleri.
 * PDO mock'u yerine bellek-içi SQLite kullanır; böylece upsert SQL'i
 * sahici bir motorda çalıştırılır ve last-write-wins davranışı doğrulanır.
 * Aynı kod prod'da MySQL/MariaDB üzerinde çalışır (motor-bağımsız upsert).
 */
class SyncIntegrationTest extends TestCase
{
    private PDO $db;
    private Sync $sync;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->createSchema();
        $this->sync = new Sync($this->db);
    }

    // ─── INSERT yolu ────────────────────────────────────────────────────────
    public function testPushInsertsNewRecords(): void
    {
        $this->sync->push(1, [
            'ratings' => [
                ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'genre_ids' => [28, 878],
                 'title' => 'The Matrix', 'updated_at' => 1000],
            ],
            'watchlist' => [
                ['id' => 1399, 'is_tv' => 1, 'title' => 'Game of Thrones',
                 'genre_ids' => [18, 10765], 'updated_at' => 1100],
            ],
        ]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame(2, TestHelperRegistry::$lastBody['applied']);

        $rating = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $rating['rating']);
        $title = $this->titleRow(603, 0);
        $this->assertSame('The Matrix', $title['title']);
        // JSON kolonu string olarak saklanmalı
        $this->assertSame([28, 878], json_decode($title['genre_ids'], true));
        // created_at gönderilmediği için updated_at ile doldurulmalı
        $this->assertSame(1000, (int) $rating['created_at']);

        $this->row('watchlist', 'id', 1399);
        $this->assertSame('Game of Thrones', $this->titleRow(1399, 1)['title']);
    }

    public function testLocalizedMetadataIsIsolatedByLocale(): void
    {
        $this->sync->push(1, [
            'metadata_locale' => 'tr',
            'watchlist' => [[
                'id' => 278, 'is_tv' => 0, 'title' => 'Esaretin Bedeli',
                'updated_at' => 1000,
            ]],
        ]);
        $this->sync->push(1, [
            'metadata_locale' => 'en',
            'watchlist' => [[
                'id' => 278, 'is_tv' => 0, 'title' => 'The Shawshank Redemption',
                'updated_at' => 1100,
            ]],
        ]);

        $this->assertSame('Esaretin Bedeli', $this->titleRow(278, 0, 'tr')['title']);
        $this->assertSame('The Shawshank Redemption', $this->titleRow(278, 0, 'en')['title']);

        TestHelperRegistry::reset();
        $this->sync->pull(1, 0, 'tr');
        $this->assertSame('Esaretin Bedeli', TestHelperRegistry::$lastBody['watchlist'][0]['title']);
        TestHelperRegistry::reset();
        $this->sync->pull(1, 0, 'en');
        $this->assertSame('The Shawshank Redemption', TestHelperRegistry::$lastBody['watchlist'][0]['title']);
    }

    // ─── last-write-wins: YENİ kazanır ────────────────────────────────────────
    public function testNewerWriteWins(): void
    {
        $this->seedRating(1, 603, 0, 1, 'Old Title', 1000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'title' => 'New Title', 'updated_at' => 2000],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $row['rating']);
        // Shared titles: dolu title istemciyle overwrite edilmez (fill-empty).
        $this->assertSame('Old Title', $this->titleRow(603, 0)['title']);
        $this->assertSame(2000, (int) $row['updated_at']);
    }

    public function testTitleFillEmptyAndSanitize(): void
    {
        // Boş overview olan satır: sonraki push overview doldurabilir.
        $this->db->exec(
            "INSERT INTO titles (tmdb_id, is_tv, locale, title, overview, metadata_updated_at)
             VALUES (777, 0, 'und', 'Keep Me', NULL, 1000)"
        );

        $this->push(1, 'ratings', [
            [
                'movie_id' => 777, 'is_tv' => 0, 'rating' => 2,
                'title' => 'http://spam.example Poison',
                'overview' => "Nice film\x00 www.evil.com more text",
                'updated_at' => 2000,
            ],
        ]);

        $title = $this->titleRow(777, 0);
        $this->assertSame('Keep Me', $title['title']); // dolu title korunur
        $this->assertSame('Nice film more text', $title['overview']); // boş overview doldurulur, URL/kontrol strip

        // İlk insert'te title sanitize edilir.
        $this->push(1, 'ratings', [
            [
                'movie_id' => 778, 'is_tv' => 0, 'rating' => 1,
                'title' => "  Cool\x01Movie https://x.test  ",
                'updated_at' => 1000,
            ],
        ]);
        $this->assertSame('CoolMovie', $this->titleRow(778, 0)['title']);
        $this->assertSame('client', $this->titleRow(778, 0)['source']);
    }

    public function testClientCannotOverwriteTmdbSource(): void
    {
        $this->db->exec(
            "INSERT INTO titles (tmdb_id, is_tv, locale, title, overview, metadata_updated_at, source, refreshed_at)
             VALUES (9001, 0, 'und', 'Canonical', 'Official overview', 1000, 'tmdb', 1000)"
        );

        $this->push(1, 'ratings', [
            [
                'movie_id' => 9001, 'is_tv' => 0, 'rating' => 2,
                'title' => 'Client Poison',
                'overview' => 'Client overview',
                'updated_at' => 5000,
            ],
        ]);

        $title = $this->titleRow(9001, 0);
        $this->assertSame('Canonical', $title['title']);
        $this->assertSame('Official overview', $title['overview']);
        $this->assertSame('tmdb', $title['source']);
    }

    public function testLazyRefreshPromotesClientTitleToTmdb(): void
    {
        $fake = new class('test-key') extends Tmdb {
            public function fetchDetails(int $tmdbId, bool $isTv, string $locale): ?array
            {
                return [
                    'title' => 'Official Title',
                    'overview' => 'From TMDB',
                    'poster_path' => '/poster.jpg',
                    'backdrop_path' => null,
                    'vote_average' => 8.5,
                    'release_date' => '1999-03-31',
                    'popularity' => 12.0,
                    'genre_ids' => '[28,12]',
                ];
            }
        };
        $this->sync = new Sync($this->db, new TitleCatalog($this->db, $fake));

        $this->push(1, 'ratings', [
            [
                'movie_id' => 9002, 'is_tv' => 0, 'rating' => 3,
                'title' => 'Client Draft',
                'updated_at' => 1000,
            ],
        ]);

        $title = $this->titleRow(9002, 0);
        $this->assertSame('Official Title', $title['title']);
        $this->assertSame('From TMDB', $title['overview']);
        $this->assertSame('/poster.jpg', $title['poster_path']);
        $this->assertSame('tmdb', $title['source']);
        $this->assertGreaterThan(0, (int) $title['refreshed_at']);
    }

    // ─── last-write-wins: ESKİ veri yok sayılır ──────────────────────────────
    public function testStaleWriteIsIgnored(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Current', 2000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 0, 'title' => 'Stale', 'updated_at' => 1000],
        ]);

        // Eski veri uygulanmadı → applied 0
        $this->assertSame(0, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(3, (int) $row['rating']);
        $this->assertSame('Current', $this->titleRow(603, 0)['title']);
        $this->assertSame(2000, (int) $row['updated_at']);
    }

    // ─── rating range validation: GEÇERSİZ puan yoksayılır ────────────────────
    public function testInvalidRatingIsIgnored(): void
    {
        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 888, 'is_tv' => 0, 'rating' => 4, 'title' => 'Too High', 'updated_at' => 1000],
            ['movie_id' => 889, 'is_tv' => 0, 'rating' => -1, 'title' => 'Too Low', 'updated_at' => 1000],
            ['movie_id' => 890, 'is_tv' => 0, 'rating' => 2, 'title' => 'Valid', 'updated_at' => 1000],
        ]);

        // Sadece geçerli olan (890) uygulanmalı
        $this->assertSame(1, $applied);
        
        $stmt = $this->db->prepare("SELECT * FROM ratings WHERE user_id = 1 AND movie_id = ?");
        
        $stmt->execute([888]);
        $this->assertFalse($stmt->fetch());
        
        $stmt->execute([889]);
        $this->assertFalse($stmt->fetch());
        
        $stmt->execute([890]);
        $validRow = $stmt->fetch(PDO::FETCH_ASSOC);
        $this->assertIsArray($validRow);
        $this->assertSame(2, (int)$validRow['rating']);
    }

    // ─── Eşit timestamp da kazanır (>= kuralı) ───────────────────────────────
    public function testEqualTimestampOverwrites(): void
    {
        $this->seedRating(1, 603, 0, 1, 'Before', 1500);
        $this->db->exec('UPDATE ratings SET server_updated_at = 5 WHERE movie_id = 603');

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 2, 'title' => 'After', 'updated_at' => 1500],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(2, (int) $row['rating']);
        $this->assertSame('Before', $this->titleRow(603, 0)['title']);
        // Eşit stamp + içerik değişimi diğer cihazlara yansısın.
        $this->assertGreaterThan(5, (int) $row['server_updated_at']);
    }

    // ─── Soft delete senkronu ────────────────────────────────────────────────
    public function testSoftDeletePropagates(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Watched', 1000);

        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'updated_at' => 2000, 'deleted' => true],
        ]);

        $this->assertSame(1, $applied);
        $row = $this->row('ratings', 'movie_id', 603);
        $this->assertSame(1, (int) $row['deleted']);
    }

    // ─── Kullanıcı kapsamı: başka kullanıcının aynı anahtarı etkilenmez ───────
    public function testPushIsScopedToUser(): void
    {
        $this->seedRating(2, 603, 0, 1, 'Bob rating', 1000);

        $this->push(1, 'ratings', [
            ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'title' => 'Alice rating', 'updated_at' => 5000],
        ]);

        // Bob'un kaydı dokunulmadan kalmalı
        $bob = $this->rowForUser('ratings', 2, 'movie_id', 603);
        $this->assertSame(1, (int) $bob['rating']);
        $this->assertSame(1000, (int) $bob['updated_at']);
        // Alice için yeni kayıt eklenmeli
        $alice = $this->rowForUser('ratings', 1, 'movie_id', 603);
        $this->assertSame(3, (int) $alice['rating']);
        // İlk yazılan shared title korunur; Alice spam'i üzerine yazamaz.
        $this->assertSame('Bob rating', $this->titleRow(603, 0)['title']);
    }

    // ─── Veri kolonu olmayan tablo (watched_seasons) + string anahtar (search) ─
    public function testKeyOnlyAndStringKeyTables(): void
    {
        $applied = 0;
        $this->sync->push(1, [
            'watched_seasons' => [
                ['tv_id' => 1399, 'season_number' => 1, 'updated_at' => 1000],
            ],
            'search_history' => [
                ['query' => 'matrix', 'updated_at' => 1100],
            ],
        ]);
        $applied = TestHelperRegistry::$lastBody['applied'];

        $this->assertSame(2, $applied);
        $this->assertNotNull($this->row('watched_seasons', 'tv_id', 1399));
        $sh = $this->row('search_history', 'query', 'matrix');
        $this->assertSame('matrix', $sh['query']);
        // search_history.created_at otomatik dolmalı
        $this->assertSame(1100, (int) $sh['created_at']);
    }

    // ─── push → pull tam tur (round-trip) ────────────────────────────────────
    public function testPushThenPullRoundTrip(): void
    {
        $this->sync->push(1, [
            'ratings' => [
                ['movie_id' => 603, 'is_tv' => 0, 'rating' => 3, 'genre_ids' => [28, 878],
                 'title' => 'The Matrix', 'updated_at' => 1000],
                ['movie_id' => 604, 'is_tv' => 0, 'rating' => 0, 'title' => 'Deleted One',
                 'updated_at' => 1200, 'deleted' => true],
            ],
        ]);

        TestHelperRegistry::reset();
        $this->sync->pull(1, 0);

        $out = TestHelperRegistry::$lastBody;
        $this->assertArrayHasKey('server_time', $out);
        $this->assertCount(2, $out['ratings']);

        // updated_at artan sırada gelmeli
        $this->assertSame(603, (int) $out['ratings'][0]['movie_id']);
        $this->assertSame(604, (int) $out['ratings'][1]['movie_id']);

        // genre_ids dizi olarak parse edilmeli
        $this->assertSame([28, 878], $out['ratings'][0]['genre_ids']);
        // deleted bool olmalı
        $this->assertIsBool($out['ratings'][1]['deleted']);
        $this->assertTrue($out['ratings'][1]['deleted']);
        // user_id sızdırılmamalı
        $this->assertArrayNotHasKey('user_id', $out['ratings'][0]);
    }

    // ─── pull yalnızca `since`'ten sonrasını döner ───────────────────────────
    public function testPullRespectsSinceCursor(): void
    {
        $this->seedRating(1, 603, 0, 3, 'Old', 1000);
        $this->seedRating(1, 700, 0, 2, 'New', 3000);

        $this->sync->pull(1, 2000);
        $out = TestHelperRegistry::$lastBody;

        $this->assertCount(1, $out['ratings']);
        $this->assertSame(700, (int) $out['ratings'][0]['movie_id']);
    }

    // ─── Regresyon: pull server saatine göre filtreler, cihaz saatine değil ───
    // Cihaz saati geride bir istemci düşük updated_at ile push edebilir. Pull
    // `since`'i cihaz-saatli updated_at'e bakarsa, bu satır başka cihazların
    // (sunucu-saatli) cursor'unun altında kalıp KALICI olarak atlanır. Fix:
    // pull, her yazımda sunucu saatiyle damgalanan server_updated_at'e bakar.
    public function testPullFiltersByServerTimeNotDeviceClock(): void
    {
        // Cihaz saati çok geride: updated_at = 500. Sunucu bunu ŞİMDİ aldı
        // (upsert server_updated_at = now_ms() yazar → ~10^12).
        $this->sync->push(1, [
            'ratings' => [
                ['movie_id' => 42, 'is_tv' => 0, 'rating' => 3,
                 'title' => 'Behind Clock', 'updated_at' => 500],
            ],
        ]);

        // Başka bir cihazın cursor'u 500'ün ÜSTÜNDE ama sunucunun şu anki
        // saatinin altında. Fix'siz (updated_at > 1000): 500 > 1000 değil →
        // satır kaybolurdu. Fix'li (server_updated_at > 1000): satır gelir.
        TestHelperRegistry::reset();
        $this->sync->pull(1, 1000);
        $out = TestHelperRegistry::$lastBody;

        $this->assertCount(1, $out['ratings']);
        $this->assertSame(42, (int) $out['ratings'][0]['movie_id']);
    }

    // ─── Regresyon: idempotent re-push server_updated_at'i ilerletmemeli ──────
    // Aynı updated_at'li satırlar 1ms örtüşme (_overlappingCursor) yüzünden her
    // sync'te yeniden push edilir. Her re-push server_updated_at'i "now"a çekseydi,
    // satır gönderen cihaza geri pull'lanıp SONSUZ sync döngüsü kurardı.
    public function testIdempotentRepushDoesNotBumpServerCursor(): void
    {
        $this->sync->push(1, [
            'ratings' => [['movie_id' => 77, 'is_tv' => 0, 'rating' => 3,
                'title' => 'Same Stamp', 'updated_at' => 1000]],
        ]);
        // server_updated_at'i bilinen düşük bir değere sabitle (zaten senkron,
        // eski satır senaryosu). Fix'li re-push bunu KORUMALI.
        $this->db->exec('UPDATE ratings SET server_updated_at = 5 WHERE movie_id = 77');

        // Aynı updated_at ile idempotent re-push.
        $this->sync->push(1, [
            'ratings' => [['movie_id' => 77, 'is_tv' => 0, 'rating' => 3,
                'title' => 'Same Stamp', 'updated_at' => 1000]],
        ]);
        $after = (int) $this->db->query(
            'SELECT server_updated_at FROM ratings WHERE movie_id = 77'
        )->fetchColumn();
        // Fix'li: 5 kalır. Fix'siz: now_ms() (~10^12) ile ezilir → döngü.
        $this->assertSame(5, $after,
            'Idempotent re-push server_updated_at ilerletmemeli (yoksa sonsuz döngü)');

        // Kontrol: kesinlikle daha yeni updated_at bump ETMELİ.
        $this->sync->push(1, [
            'ratings' => [['movie_id' => 77, 'is_tv' => 0, 'rating' => 2,
                'title' => 'Same Stamp', 'updated_at' => 2000]],
        ]);
        $bumped = (int) $this->db->query(
            'SELECT server_updated_at FROM ratings WHERE movie_id = 77'
        )->fetchColumn();
        $this->assertGreaterThan(5, $bumped,
            'Daha yeni updated_at server_updated_at bumplamalı');
    }

    // ───────────────────────── yardımcılar ──────────────────────────────────

    /** Tek tabloyu push edip applied sayısını döndürür. */
    // ─── Yorum doğrulaması: 280 kırpma + URL sökme ───────────────────────────
    public function testCommentIsSanitizedOnPush(): void
    {
        $longComment = str_repeat('a', 400);
        $applied = $this->push(1, 'ratings', [
            ['movie_id' => 1, 'is_tv' => 0, 'rating' => 2, 'title' => 'Long',
             'comment' => $longComment, 'updated_at' => 1000],
            ['movie_id' => 2, 'is_tv' => 0, 'rating' => 2, 'title' => 'Spammy',
             'comment' => 'Harika film! https://spam.example.com/kumar hemen tikla', 'updated_at' => 1000],
            ['movie_id' => 3, 'is_tv' => 0, 'rating' => 2, 'title' => 'OnlyUrl',
             'comment' => 'www.spam-site.io/x', 'updated_at' => 1000],
        ]);
        $this->assertSame(3, $applied);

        $this->assertSame(280, mb_strlen($this->row('ratings', 'movie_id', 1)['comment']));

        $spammy = $this->row('ratings', 'movie_id', 2);
        $this->assertStringNotContainsString('http', $spammy['comment']);
        $this->assertStringContainsString('Harika film!', $spammy['comment']);

        // Yalnızca URL'den oluşan yorum boşa iner → NULL saklanır.
        $this->assertNull($this->row('ratings', 'movie_id', 3)['comment']);
    }

    // ─── Küfür tespiti: is_hidden sunucu tarafında set edilir ────────────────
    public function testFlaggedCommentIsAutoHiddenAndUnhiddenWhenEdited(): void
    {
        $this->push(1, 'ratings', [
            ['movie_id' => 10, 'is_tv' => 0, 'rating' => 0, 'title' => 'Bad',
             'comment' => 'bu film amk berbat', 'updated_at' => 1000],
        ]);
        $this->assertSame(1, (int) $this->row('ratings', 'movie_id', 10)['is_hidden']);

        // Kullanıcı küfrü temizleyip yorumu güncellerse görünürlük geri gelir.
        $this->push(1, 'ratings', [
            ['movie_id' => 10, 'is_tv' => 0, 'rating' => 0, 'title' => 'Bad',
             'comment' => 'bu film berbat', 'updated_at' => 2000],
        ]);
        $row = $this->row('ratings', 'movie_id', 10);
        $this->assertSame(0, (int) $row['is_hidden']);
        $this->assertSame('bu film berbat', $row['comment']);
    }

    // ─── Yorum yasağı: susturulan kullanıcının yeni yorumu otomatik gizlenir ─
    public function testReviewBannedUserCommentsAreAutoHidden(): void
    {
        $this->db->exec('UPDATE users SET review_banned = 1 WHERE id = 1');

        $this->push(1, 'ratings', [
            ['movie_id' => 12, 'is_tv' => 0, 'rating' => 2, 'title' => 'Banned',
             'comment' => 'gayet masum bir yorum', 'updated_at' => 1000],
        ]);
        $row = $this->row('ratings', 'movie_id', 12);
        $this->assertSame(1, (int) $row['is_hidden']);
        // Yorum verisi korunur; yalnızca başkalarına gösterilmez.
        $this->assertSame('gayet masum bir yorum', $row['comment']);

        // Yasaksız kullanıcı etkilenmez.
        $this->push(2, 'ratings', [
            ['movie_id' => 12, 'is_tv' => 0, 'rating' => 2, 'title' => 'Free',
             'comment' => 'gayet masum bir yorum', 'updated_at' => 1000],
        ]);
        $rowFree = $this->rowForUser('ratings', 2, 'movie_id', 12);
        $this->assertSame(0, (int) $rowFree['is_hidden']);
    }

    // ─── Moderatör gizlemesi, yorum değişmedikçe korunur ─────────────────────
    public function testModeratorHideSurvivesUnrelatedUpdate(): void
    {
        $this->push(1, 'ratings', [
            ['movie_id' => 11, 'is_tv' => 0, 'rating' => 2, 'title' => 'Reported',
             'comment' => 'sinsi spam yorumu', 'updated_at' => 1000],
        ]);
        // Moderatör/otomatik eşik gizledi:
        $this->db->exec('UPDATE ratings SET is_hidden = 1 WHERE movie_id = 11');

        // Yorum AYNI kalarak puan güncellenirse gizleme kalkmaz.
        $this->push(1, 'ratings', [
            ['movie_id' => 11, 'is_tv' => 0, 'rating' => 3, 'title' => 'Reported',
             'comment' => 'sinsi spam yorumu', 'updated_at' => 2000],
        ]);
        $row = $this->row('ratings', 'movie_id', 11);
        $this->assertSame(1, (int) $row['is_hidden']);
        $this->assertSame(3, (int) $row['rating']);
    }

    public function testPullRegistersAndAdvancesDeviceAcknowledgement(): void
    {
        $deviceId = 'device-sync-test-0001';
        $this->sync->pull(1, 0, 'tr', $deviceId, 1234, true);

        $row = $this->db->query(
            "SELECT * FROM sync_devices WHERE user_id = 1 AND device_id = '$deviceId'"
        )->fetch(PDO::FETCH_ASSOC);
        $this->assertSame(1234, (int) $row['last_ack_cursor']);

        TestHelperRegistry::reset();
        $this->sync->pull(1, 1234, 'tr', $deviceId, 2345, true);
        $ack = $this->db->query(
            "SELECT last_ack_cursor FROM sync_devices WHERE user_id = 1 AND device_id = '$deviceId'"
        )->fetchColumn();
        $this->assertSame(2345, (int) $ack);
    }

    public function testInvalidatedDeviceMustResetBeforePush(): void
    {
        $this->db->exec(
            "INSERT INTO sync_devices VALUES
             (1, 'device-expired-0001', 5000, 1000, 1000, 2000)"
        );

        try {
            $this->sync->push(1, [
                'device_id' => 'device-expired-0001',
                'ack_cursor' => 5000,
                'ratings' => [[
                    'movie_id' => 999, 'is_tv' => 0, 'rating' => 3,
                    'updated_at' => 4000,
                ]],
            ], true);
            $this->fail('Expired device push should require a reset.');
        } catch (TestExitException $e) {
            $this->assertSame(409, $e->getCode());
            $this->assertSame('sync_reset_required', TestHelperRegistry::$lastBody['code']);
        }
        $this->assertSame(0, (int) $this->db->query('SELECT COUNT(*) FROM ratings')->fetchColumn());

        // ack_cursor=0 without local_reset still requires an explicit wipe.
        TestHelperRegistry::reset();
        try {
            $this->sync->push(1, [
                'device_id' => 'device-expired-0001',
                'ack_cursor' => 0,
            ], true);
            $this->fail('Expired device push without local_reset should require a reset.');
        } catch (TestExitException $e) {
            $this->assertSame(409, $e->getCode());
            $this->assertSame('sync_reset_required', TestHelperRegistry::$lastBody['code']);
        }

        TestHelperRegistry::reset();
        $this->sync->push(1, [
            'device_id' => 'device-expired-0001',
            'ack_cursor' => 0,
            'local_reset' => true,
        ], true);
        $row = $this->db->query(
            "SELECT last_ack_cursor, invalidated_at FROM sync_devices
             WHERE device_id = 'device-expired-0001'"
        )->fetch(PDO::FETCH_ASSOC);
        $this->assertSame(0, (int) $row['last_ack_cursor']);
        $this->assertNull($row['invalidated_at']);
    }

    public function testUnknownOldDeviceResetsAfterGarbageCollectionStarted(): void
    {
        $this->db->exec('INSERT INTO sync_gc_state VALUES (1, 3000, 4000)');
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(409);
        $this->sync->pull(1, 2000, 'tr', 'device-unknown-0001', 2000, true);
    }

    private function push(int $uid, string $table, array $items): int
    {
        TestHelperRegistry::reset();
        $this->sync->push($uid, [$table => $items]);
        return (int) TestHelperRegistry::$lastBody['applied'];
    }

    private function seedRating(int $uid, int $movieId, int $isTv, int $rating, string $title, int $updatedAt): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, created_at, updated_at, server_updated_at, deleted)
             VALUES (?, ?, ?, ?, ?, ?, ?, 0)'
        );
        // server_updated_at = updated_at: doğrudan seed edilen satır, sunucunun o
        // damgayla aldığını simüle eder (server-zamanlı cursor testleri için).
        $stmt->execute([$uid, $movieId, $isTv, $rating, $updatedAt, $updatedAt, $updatedAt]);
        $stmt = $this->db->prepare(
            'INSERT INTO titles (tmdb_id, is_tv, locale, title, metadata_updated_at) VALUES (?, ?, \'und\', ?, ?)
             ON CONFLICT(tmdb_id, is_tv, locale) DO UPDATE SET
               title = excluded.title, metadata_updated_at = excluded.metadata_updated_at
             WHERE excluded.metadata_updated_at >= titles.metadata_updated_at'
        );
        $stmt->execute([$movieId, $isTv, $title, $updatedAt]);
    }

    private function titleRow(int $tmdbId, int $isTv, string $locale = 'und'): array
    {
        $stmt = $this->db->prepare('SELECT * FROM titles WHERE tmdb_id = ? AND is_tv = ? AND locale = ?');
        $stmt->execute([$tmdbId, $isTv, $locale]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $this->assertIsArray($row, "Beklenen katalog kaydı bulunamadı: $tmdbId/$isTv");
        return $row;
    }

    /** user_id = 1 varsayımıyla tek satır okur. */
    private function row(string $table, string $keyCol, $keyVal): array
    {
        return $this->rowForUser($table, 1, $keyCol, $keyVal);
    }

    private function rowForUser(string $table, int $uid, string $keyCol, $keyVal): array
    {
        $stmt = $this->db->prepare("SELECT * FROM `$table` WHERE user_id = ? AND `$keyCol` = ?");
        $stmt->execute([$uid, $keyVal]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $this->assertIsArray($row, "Beklenen satır bulunamadı: $table.$keyCol=$keyVal");
        return $row;
    }

    private function createSchema(): void
    {
        // Sync::isReviewBanned kullanıcı tablosuna bakar (yorum yasağı).
        $this->db->exec(
            'CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                review_banned INTEGER NOT NULL DEFAULT 0
            )'
        );
        $this->db->exec('INSERT INTO users (id, review_banned) VALUES (1, 0), (2, 0)');
        $this->db->exec(
            'CREATE TABLE titles (
                tmdb_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                locale TEXT NOT NULL,
                title TEXT,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                popularity REAL,
                genre_ids TEXT,
                metadata_updated_at INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT \'client\',
                refreshed_at INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (tmdb_id, is_tv, locale)
            )'
        );
        $this->db->exec(
            'CREATE TABLE ratings (
                user_id INTEGER NOT NULL,
                movie_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                rating INTEGER,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                server_updated_at INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                comment TEXT,
                is_spoiler INTEGER NOT NULL DEFAULT 0,
                is_private INTEGER NOT NULL DEFAULT 0,
                is_hidden INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, movie_id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE watchlist (
                user_id INTEGER NOT NULL,
                id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                server_updated_at INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE favorites (
                user_id INTEGER NOT NULL,
                id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                server_updated_at INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE watched_seasons (
                user_id INTEGER NOT NULL,
                tv_id INTEGER NOT NULL,
                season_number INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                server_updated_at INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, tv_id, season_number)
            )'
        );
        $this->db->exec(
            'CREATE TABLE search_history (
                user_id INTEGER NOT NULL,
                query TEXT NOT NULL,
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                server_updated_at INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, query)
            )'
        );
        $this->db->exec(
            'CREATE TABLE sync_devices (
                user_id INTEGER NOT NULL,
                device_id TEXT NOT NULL,
                last_ack_cursor INTEGER NOT NULL DEFAULT 0,
                last_seen_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                invalidated_at INTEGER,
                PRIMARY KEY (user_id, device_id)
            )'
        );
        $this->db->exec(
            'CREATE TABLE sync_gc_state (
                user_id INTEGER PRIMARY KEY,
                gc_cursor INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL
            )'
        );
    }
}
