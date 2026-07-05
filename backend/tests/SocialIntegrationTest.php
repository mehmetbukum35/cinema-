<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

class SocialIntegrationTest extends TestCase
{
    private PDO $db;
    private Social $social;

    protected function setUp(): void
    {
        TestHelperRegistry::reset();
        $this->db = new PDO('sqlite::memory:');
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->createSchema();
        $this->seedUsers();
        $this->social = new Social($this->db);
    }

    public function testFriendRequestLifecycleUsesRealDatabaseState(): void
    {
        $this->social->sendFriendRequest(1, ['search_query' => 'bob']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('pending', TestHelperRegistry::$lastBody['status']);
        $this->assertSame('pending', $this->friendStatus(1, 2));

        TestHelperRegistry::reset();
        $this->social->getFriends(2);

        $this->assertCount(1, TestHelperRegistry::$lastBody['pending_received']);
        $this->assertSame('alice', TestHelperRegistry::$lastBody['pending_received'][0]['username']);

        TestHelperRegistry::reset();
        $this->social->sendFriendRequest(2, ['search_query' => 'alice']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('accepted', TestHelperRegistry::$lastBody['status']);
        $this->assertSame('accepted', $this->friendStatus(1, 2));
        $this->assertSame('accepted', $this->friendStatus(2, 1));
    }

    public function testActivitySignalsAndWatchlistIntersectionRespectAcceptedFriendship(): void
    {
        $this->acceptFriendship(1, 2);
        $this->insertRating(2, 101, 0, 3, 'The Matrix', 2000);
        $this->insertRating(3, 202, 1, 3, 'Hidden Show', 2100);
        $this->insertWatchlist(1, 500, 0, 'Shared Movie', '[28,35]', 1000);
        $this->insertWatchlist(2, 500, 0, 'Shared Movie', '[28,35]', 1100);
        $this->insertWatchlist(2, 501, 0, 'Only Bob', '[18]', 1200);

        $this->social->getActivityFeed(1);
        $this->assertCount(1, TestHelperRegistry::$lastBody['activity']);
        $this->assertSame(101, (int) TestHelperRegistry::$lastBody['activity'][0]['movie_id']);

        TestHelperRegistry::reset();
        $this->social->getFriendSignals(1);
        $this->assertSame(['Bob'], TestHelperRegistry::$lastBody['signals']['movie_101']);
        $this->assertArrayNotHasKey('tv_202', TestHelperRegistry::$lastBody['signals']);

        TestHelperRegistry::reset();
        $this->social->getWatchlistIntersection(1, 2);
        $this->assertCount(1, TestHelperRegistry::$lastBody['watchlist']);
        $this->assertSame(500, (int) TestHelperRegistry::$lastBody['watchlist'][0]['id']);
        $this->assertSame([28, 35], TestHelperRegistry::$lastBody['watchlist'][0]['genre_ids']);
    }

    public function testPublishTasteDnaStoresSnapshot(): void
    {
        $snapshot = ['archetype' => 'dark_chronicler', 'themes' => ['revenge']];
        $this->social->publishTasteDna(1, ['dna' => $snapshot]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertTrue(TestHelperRegistry::$lastBody['ok']);

        $st = $this->db->prepare('SELECT taste_dna, taste_dna_at FROM users WHERE id = 1');
        $st->execute();
        $row = $st->fetch(PDO::FETCH_ASSOC);
        $this->assertSame($snapshot, json_decode($row['taste_dna'], true));
        $this->assertGreaterThan(0, (int) $row['taste_dna_at']);
    }

    public function testPublishTasteDnaRejectsNonArray(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);
        try {
            $this->social->publishTasteDna(1, ['dna' => 'not-an-object']);
        } finally {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testPublishTasteDnaRejectsOversizedSnapshot(): void
    {
        $huge = ['themes' => array_fill(0, 5000, 'padding-keyword')];
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);
        try {
            $this->social->publishTasteDna(1, ['dna' => $huge]);
        } finally {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testWatchlistIntersectionRejectsNonFriends(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);

        try {
            $this->social->getWatchlistIntersection(1, 3);
        } finally {
            $this->assertSame(403, TestHelperRegistry::$lastStatus);
        }
    }

    public function testExplicitAcceptFriendRequestLifecycle(): void
    {
        // Alice sends a friend request to Bob
        $this->social->sendFriendRequest(1, ['search_query' => 'bob']);
        $this->assertSame('pending', $this->friendStatus(1, 2));
        $this->assertNull($this->friendStatus(2, 1));

        // Bob explicitly accepts Alice's request
        TestHelperRegistry::reset();
        $this->social->acceptFriendRequest(2, ['friend_id' => 1]);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('accepted', $this->friendStatus(1, 2));
        $this->assertSame('accepted', $this->friendStatus(2, 1));
    }

    public function testDeviceRegistrationAndUnregistration(): void
    {
        // 1. Register a new device token
        $this->social->registerDevice(1, ['token' => 'fcm_token_123', 'platform' => 'android']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);

        // Verify it was stored in database
        $st = $this->db->prepare('SELECT user_id, platform FROM device_tokens WHERE token = ?');
        $st->execute(['fcm_token_123']);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        $this->assertNotFalse($row);
        $this->assertSame(1, (int) $row['user_id']);
        $this->assertSame('android', $row['platform']);

        // 2. Register again with same token but different user and platform (updates key details)
        TestHelperRegistry::reset();
        $this->social->registerDevice(2, ['token' => 'fcm_token_123', 'platform' => 'ios']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);

        $st->execute(['fcm_token_123']);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        $this->assertNotFalse($row);
        $this->assertSame(2, (int) $row['user_id']);
        $this->assertSame('ios', $row['platform']);

        // 3. Unregister device token
        TestHelperRegistry::reset();
        $this->social->unregisterDevice(2, ['token' => 'fcm_token_123']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);

        $st->execute(['fcm_token_123']);
        $row = $st->fetch();
        $this->assertFalse($row); // token deleted
    }


    // ─── Zevk Uyumu (taste match) ────────────────────────────────────────────

    public function testTasteMatchBlendsAgreementAndGenreSimilarity(): void
    {
        $this->acceptFriendship(1, 2);

        // 3 ortak yapım: iki tanesinde tam anlaşma (3-3), birinde tam zıtlık (3-0).
        $this->insertRating(1, 101, 0, 3, 'Movie A', 1000, '[28,12]');
        $this->insertRating(2, 101, 0, 3, 'Movie A', 1001, '[28,12]');
        $this->insertRating(1, 102, 0, 3, 'Movie B', 1002, '[28]');
        $this->insertRating(2, 102, 0, 3, 'Movie B', 1003, '[28]');
        $this->insertRating(1, 103, 0, 3, 'Movie C', 1004, '[35]');
        $this->insertRating(2, 103, 0, 0, 'Movie C', 1005, '[35]');

        $this->social->getTasteMatch(1, 2);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame(3, $body['common_count']);
        $this->assertSame(2, $body['both_loved']);
        // Anlaşma: (1 + 1 + 0) / 3 = 0.6667
        $this->assertEqualsWithDelta(0.6667, $body['agreement'], 0.001);
        $this->assertTrue($body['has_data']);
        $this->assertGreaterThan(0, $body['score']);
        $this->assertLessThanOrEqual(100, $body['score']);
    }

    public function testTasteMatchPerfectAgreementYieldsFullScore(): void
    {
        $this->acceptFriendship(1, 2);
        // 3+ ortak yapımda birebir aynı puanlar ve aynı türler → 100.
        foreach ([201, 202, 203] as $i => $movieId) {
            $this->insertRating(1, $movieId, 0, 3, "Movie $movieId", 1000 + $i, '[28,878]');
            $this->insertRating(2, $movieId, 0, 3, "Movie $movieId", 2000 + $i, '[28,878]');
        }

        $this->social->getTasteMatch(1, 2);
        $this->assertSame(100, TestHelperRegistry::$lastBody['score']);
    }

    public function testTasteMatchWithoutCommonTitlesFallsBackToGenres(): void
    {
        $this->acceptFriendship(1, 2);
        // Ortak yapım yok ama tür zevki aynı (Aksiyon sevenler).
        $this->insertRating(1, 301, 0, 3, 'Movie X', 1000, '[28]');
        $this->insertRating(2, 302, 0, 3, 'Movie Y', 1001, '[28]');

        $this->social->getTasteMatch(1, 2);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(0, $body['common_count']);
        $this->assertSame(100, $body['score']); // kosinüs = 1.0
        $this->assertTrue($body['has_data']);
    }

    public function testTasteMatchNoDataReturnsZeroWithFlag(): void
    {
        $this->acceptFriendship(1, 2);
        $this->social->getTasteMatch(1, 2);

        $this->assertSame(0, TestHelperRegistry::$lastBody['score']);
        $this->assertFalse(TestHelperRegistry::$lastBody['has_data']);
    }

    public function testTasteMatchRejectsNonFriends(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);
        $this->social->getTasteMatch(1, 3);
    }

    // ─── Arkadaşa Öneri (recommendations) ───────────────────────────────────

    public function testRecommendLifecycle(): void
    {
        $this->acceptFriendship(1, 2);

        // Alice, Bob'a film önerir.
        $this->social->recommend(1, [
            'friend_id' => 2, 'movie_id' => 603, 'is_tv' => 0,
            'title' => 'The Matrix', 'poster_path' => '/matrix.jpg', 'note' => 'Mutlaka izle!',
        ]);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);

        // Bob gelen kutusunda görür (unseen = 1).
        TestHelperRegistry::reset();
        $this->social->getRecommendations(2);
        $body = TestHelperRegistry::$lastBody;
        $this->assertCount(1, $body['recommendations']);
        $this->assertSame(1, $body['unseen']);
        $rec = $body['recommendations'][0];
        $this->assertSame('The Matrix', $rec['title']);
        $this->assertSame('Mutlaka izle!', $rec['note']);
        $this->assertSame('alice', $rec['from_username']);
        $this->assertFalse($rec['seen']);

        // Görüldü olarak işaretle.
        TestHelperRegistry::reset();
        $this->social->markRecommendationsSeen(2);
        $this->assertSame(1, TestHelperRegistry::$lastBody['marked']);

        TestHelperRegistry::reset();
        $this->social->getRecommendations(2);
        $this->assertSame(0, TestHelperRegistry::$lastBody['unseen']);
        $this->assertTrue(TestHelperRegistry::$lastBody['recommendations'][0]['seen']);
    }

    public function testRecommendSameMovieTwiceUpdatesInsteadOfDuplicating(): void
    {
        $this->acceptFriendship(1, 2);

        $payload = ['friend_id' => 2, 'movie_id' => 603, 'is_tv' => 0, 'title' => 'The Matrix'];
        $this->social->recommend(1, $payload);
        TestHelperRegistry::reset();
        $this->social->recommend(1, $payload + ['note' => 'Yeni not']);

        $st = $this->db->query('SELECT COUNT(*) FROM recommendations');
        $this->assertSame(1, (int) $st->fetchColumn());

        TestHelperRegistry::reset();
        $this->social->getRecommendations(2);
        $this->assertSame('Yeni not', TestHelperRegistry::$lastBody['recommendations'][0]['note']);
        $this->assertSame(1, TestHelperRegistry::$lastBody['unseen']); // tekrar unseen oldu
    }

    public function testRecommendRejectsNonFriends(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);
        $this->social->recommend(1, [
            'friend_id' => 3, 'movie_id' => 603, 'is_tv' => 0, 'title' => 'The Matrix',
        ]);
    }

    public function testRecommendValidatesRequiredFields(): void
    {
        $this->acceptFriendship(1, 2);
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);
        $this->social->recommend(1, ['friend_id' => 2, 'movie_id' => 0, 'title' => '']);
    }

    public function testTitleReviewsAndActivityFeedWithNegativeComments(): void
    {
        // 1. Setup friendship between 1 and 2
        $this->acceptFriendship(1, 2);

        // 2. Friend 2 rates movie 999 as 1 (Meh) with comment & spoiler
        $now = now_ms();
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (2, 999, 0, 1, \'Horrible Movie\', \'/path.jpg\', \'[]\', ?, 0, \'Very bad movie!\', 1)'
        );
        $st->execute([$now]);

        // 3. Stranger 3 (not a friend) rates movie 999 as 3 (Harika) with comment
        $st3 = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (3, 999, 0, 3, \'Horrible Movie\', \'/path.jpg\', \'[]\', ?, 0, \'Nice movie!\', 0)'
        );
        $st3->execute([$now]);

        // 4. User 1 itself rates movie 999 (should be excluded from both lists)
        $st1 = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (1, 999, 0, 2, \'Horrible Movie\', \'/path.jpg\', \'[]\', ?, 0, \'My own comment\', 0)'
        );
        $st1->execute([$now]);

        // 5. Fetch activity feed for User 1 -> should contain Friend 2's negative review because it has a comment
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $feed = TestHelperRegistry::$lastBody['activity'];
        $this->assertCount(1, $feed);
        $this->assertSame(999, (int) $feed[0]['movie_id']);
        $this->assertSame('Very bad movie!', $feed[0]['comment']);
        $this->assertSame(1, (int) $feed[0]['is_spoiler']);

        // 6. Fetch title reviews for User 1 -> should return Friend 2's review in reviews and friends, and Stranger 3's review in community
        TestHelperRegistry::reset();
        $this->social->getTitleReviews(1, 'movie', 999);
        
        $reviews = TestHelperRegistry::$lastBody['reviews'];
        $friends = TestHelperRegistry::$lastBody['friends'];
        $community = TestHelperRegistry::$lastBody['community'];

        // Backward compatibility check
        $this->assertCount(1, $reviews);
        $this->assertSame('Very bad movie!', $reviews[0]['comment']);

        // Friends list check
        $this->assertCount(1, $friends);
        $this->assertSame('Very bad movie!', $friends[0]['comment']);
        $this->assertSame(1, (int) $friends[0]['rating']);
        $this->assertSame(1, (int) $friends[0]['is_spoiler']);

        // Community list check (should contain Stranger 3 but NOT Friend 2 or User 1)
        $this->assertCount(1, $community);
        $this->assertSame('Nice movie!', $community[0]['comment']);
        $this->assertSame(3, (int) $community[0]['rating']);
        $this->assertSame(0, (int) $community[0]['is_spoiler']);
    }

    public function testTitleScoreAggregatesLikedPercentAcrossAllMembers(): void
    {
        // Aynı filme (555) farklı üyeler farklı puanlar verir; arkadaşlık gerekmez.
        // rating: 3=Harika, 2=İyi (beğeni), 1=Eh, 0=Berbat (beğeni değil), -1=izlenmedi (sayılmaz)
        $now = now_ms();
        $ins = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (?, 555, 0, ?, \'Film\', \'/p.jpg\', \'[]\', ?, ?, NULL, 0)'
        );
        // 3 beğeni (3,3,2), 2 beğenmeme (1,0) → 3/5 = %60
        $ins->execute([1, 3, $now, 0]);
        $ins->execute([2, 3, $now, 0]);
        $ins->execute([3, 2, $now, 0]);
        $ins->execute([4, 1, $now, 0]);
        $ins->execute([5, 0, $now, 0]);
        // Gürültü: silinmiş kayıt ve "izlenmedi" sayılmamalı
        $ins->execute([6, 3, $now, 1]);   // deleted
        $insWatched = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (7, 555, 0, -1, \'Film\', \'/p.jpg\', \'[]\', ?, 0, NULL, 0)'
        );
        $insWatched->execute([$now]);

        TestHelperRegistry::reset();
        $this->social->getTitleScore(1, 'movie', 555);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(5, $body['total']);
        $this->assertSame(60, $body['liked_percent']);
        $this->assertTrue($body['enough']);
        $this->assertSame(2, $body['distribution']['harika']);
        $this->assertSame(1, $body['distribution']['iyi']);
        $this->assertSame(1, $body['distribution']['eh']);
        $this->assertSame(1, $body['distribution']['berbat']);
    }

    public function testTitleScoreBelowThresholdFlagsNotEnough(): void
    {
        $now = now_ms();
        $ins = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, comment, is_spoiler)
             VALUES (?, 777, 1, ?, \'Dizi\', \'/p.jpg\', \'[]\', ?, 0, NULL, 0)'
        );
        $ins->execute([1, 3, $now]);
        $ins->execute([2, 2, $now]);

        TestHelperRegistry::reset();
        $this->social->getTitleScore(1, 'tv', 777);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(2, $body['total']);
        $this->assertSame(100, $body['liked_percent']);
        $this->assertFalse($body['enough']); // eşiğin (5) altında
    }

    public function testTitleScoreNoVotesReturnsZero(): void
    {
        TestHelperRegistry::reset();
        $this->social->getTitleScore(1, 'movie', 12345);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(0, $body['total']);
        $this->assertSame(0, $body['liked_percent']);
        $this->assertFalse($body['enough']);
    }

    private function createSchema(): void
    {
        $this->db->exec(
            'CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                display_name TEXT,
                username TEXT UNIQUE,
                is_public INTEGER NOT NULL DEFAULT 1,
                updated_at INTEGER NOT NULL DEFAULT 0,
                taste_dna TEXT NULL,
                taste_dna_at INTEGER NOT NULL DEFAULT 0
            )'
        );
        $this->db->exec(
            'CREATE TABLE friends (
                user_id INTEGER NOT NULL,
                friend_id INTEGER NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (user_id, friend_id)
            )'
        );
        $this->db->exec(
            'CREATE TABLE ratings (
                user_id INTEGER NOT NULL,
                movie_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                rating INTEGER NOT NULL,
                title TEXT,
                poster_path TEXT,
                genre_ids TEXT,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                comment TEXT,
                is_spoiler INTEGER NOT NULL DEFAULT 0
            )'
        );
        $this->db->exec(
            'CREATE TABLE watchlist (
                user_id INTEGER NOT NULL,
                id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                title TEXT NOT NULL,
                poster_path TEXT,
                backdrop_path TEXT,
                overview TEXT,
                vote_average REAL,
                release_date TEXT,
                genre_ids TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
            )'
        );
        $this->db->exec(
            'CREATE TABLE device_tokens (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                platform TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )'
        );
        $this->db->exec(
            'CREATE TABLE recommendations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_user_id INTEGER NOT NULL,
                to_user_id INTEGER NOT NULL,
                movie_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                title TEXT NOT NULL,
                poster_path TEXT,
                note TEXT,
                seen INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                UNIQUE (from_user_id, to_user_id, movie_id, is_tv)
            )'
        );
    }

    private function seedUsers(): void
    {
        $users = [
            [1, 'alice@example.com', 'Alice', 'alice'],
            [2, 'bob@example.com', 'Bob', 'bob'],
            [3, 'carol@example.com', 'Carol', 'carol'],
        ];
        $stmt = $this->db->prepare('INSERT INTO users (id, email, display_name, username) VALUES (?, ?, ?, ?)');
        foreach ($users as $user) {
            $stmt->execute($user);
        }
    }

    private function acceptFriendship(int $userId, int $friendId): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO friends (user_id, friend_id, status, created_at, updated_at)
             VALUES (?, ?, "accepted", 1000, 1000)'
        );
        $stmt->execute([$userId, $friendId]);
        $stmt->execute([$friendId, $userId]);
    }

    private function friendStatus(int $userId, int $friendId): ?string
    {
        $stmt = $this->db->prepare('SELECT status FROM friends WHERE user_id = ? AND friend_id = ?');
        $stmt->execute([$userId, $friendId]);
        $status = $stmt->fetchColumn();
        return $status === false ? null : (string) $status;
    }

    private function insertRating(int $userId, int $movieId, int $isTv, int $rating, string $title, int $updatedAt, ?string $genreIds = null): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted)
             VALUES (?, ?, ?, ?, ?, "/poster.jpg", ?, ?, 0)'
        );
        $stmt->execute([$userId, $movieId, $isTv, $rating, $title, $genreIds, $updatedAt]);
    }

    private function insertWatchlist(int $userId, int $id, int $isTv, string $title, string $genreIds, int $createdAt): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO watchlist
             (user_id, id, is_tv, title, poster_path, backdrop_path, overview, vote_average, release_date, genre_ids, created_at, updated_at, deleted)
             VALUES (?, ?, ?, ?, "/poster.jpg", "/back.jpg", "Overview", 8.5, "1999-03-31", ?, ?, ?, 0)'
        );
        $stmt->execute([$userId, $id, $isTv, $title, $genreIds, $createdAt, $createdAt]);
    }
}
