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

    public function testFriendRequestNormalizesEmailSearch(): void
    {
        $this->social->sendFriendRequest(1, ['search_query' => ' BOB@EXAMPLE.COM ']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('pending', TestHelperRegistry::$lastBody['status']);
        $this->assertSame('pending', $this->friendStatus(1, 2));
    }

    public function testFriendRequestNormalizesUsernameSearchWithMixedCase(): void
    {
        $this->social->sendFriendRequest(1, ['search_query' => ' BoB ']);

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('pending', TestHelperRegistry::$lastBody['status']);
        $this->assertSame('pending', $this->friendStatus(1, 2));
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
        // signals (object) cast'lidir (boş küme JSON'da {} kalsın diye).
        $signals = (array) TestHelperRegistry::$lastBody['signals'];
        $this->assertSame(['Bob'], $signals['movie_101']);
        $this->assertArrayNotHasKey('tv_202', $signals);

        TestHelperRegistry::reset();
        $this->social->getWatchlistIntersection(1, 2);
        $this->assertCount(1, TestHelperRegistry::$lastBody['watchlist']);
        $this->assertSame(500, (int) TestHelperRegistry::$lastBody['watchlist'][0]['id']);
        $this->assertSame([28, 35], TestHelperRegistry::$lastBody['watchlist'][0]['genre_ids']);
    }

    public function testActivityFeedUsesStableCursorPagination(): void
    {
        $this->acceptFriendship(1, 2);
        $this->insertRating(2, 101, 0, 3, 'Newest', 3000);
        $this->insertRating(2, 102, 0, 3, 'Middle', 2000);
        $this->insertRating(2, 103, 0, 3, 'Oldest', 1000);

        $this->social->getActivityFeed(1, null, null, 2);
        $first = TestHelperRegistry::$lastBody;
        $this->assertCount(2, $first['activity']);
        $this->assertTrue($first['has_more']);
        $this->assertNotEmpty($first['next_cursor']);
        $this->assertSame(101, (int) $first['activity'][0]['movie_id']);
        $this->assertSame(102, (int) $first['activity'][1]['movie_id']);

        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1, null, $first['next_cursor'], 2);
        $second = TestHelperRegistry::$lastBody;
        $this->assertCount(1, $second['activity']);
        $this->assertFalse($second['has_more']);
        $this->assertNull($second['next_cursor']);
        $this->assertSame(103, (int) $second['activity'][0]['movie_id']);
    }

    public function testPrivateRatingsAreFilteredFromSocialViews(): void
    {
        $this->acceptFriendship(1, 2);
        
        // Insert public rating for friend (user 2)
        $this->insertRatingPrivate(2, 301, 0, 3, 'Public Movie', 2000, 0);
        // Insert private rating for friend (user 2)
        $this->insertRatingPrivate(2, 302, 0, 3, 'Private Movie', 2010, 1);

        // 1. Verify getActivityFeed
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertCount(1, TestHelperRegistry::$lastBody['activity']);
        $this->assertSame(301, (int) TestHelperRegistry::$lastBody['activity'][0]['movie_id']);

        // 2. Verify getFriendSignals
        TestHelperRegistry::reset();
        $this->social->getFriendSignals(1);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $signals = (array) TestHelperRegistry::$lastBody['signals'];
        $this->assertArrayHasKey('movie_301', $signals);
        $this->assertArrayNotHasKey('movie_302', $signals);

        // 3. Verify getTopProfiles
        TestHelperRegistry::reset();
        $this->db->exec('UPDATE users SET is_public = 1 WHERE id = 2');
        $this->social->getTopProfiles(1);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $profiles = TestHelperRegistry::$lastBody['profiles'];
        // Sorted profiles. Find friend 2
        $friend2Profile = null;
        foreach ($profiles as $p) {
            if ($p['id'] === 2) {
                $friend2Profile = $p;
            }
        }
        $this->assertNotNull($friend2Profile);
        $this->assertCount(1, $friend2Profile['previews']);
        $this->assertSame(301, (int) $friend2Profile['previews'][0]['movie_id']);
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

    public function testGetSentRecommendations(): void
    {
        $this->acceptFriendship(1, 2);

        $this->social->recommend(1, [
            'friend_id' => 2, 'movie_id' => 603, 'is_tv' => 0,
            'title' => 'The Matrix', 'poster_path' => '/matrix.jpg', 'note' => 'Mutlaka izle!',
        ]);

        TestHelperRegistry::reset();
        $this->social->getSentRecommendations(1);
        $body = TestHelperRegistry::$lastBody;
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertCount(1, $body['sent']);
        $sent = $body['sent'][0];
        $this->assertSame('The Matrix', $sent['title']);
        $this->assertSame('bob', $sent['to_username']);
        $this->assertSame('Mutlaka izle!', $sent['note']);
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

    public function testActivityFeedFiltersByFriendId(): void
    {
        // 1. Setup friendship between 1 & 2 and 1 & 3
        $this->acceptFriendship(1, 2);
        $this->acceptFriendship(1, 3);

        $now = now_ms();
        // Friend 2 rates movie 101 as 3
        $this->insertRating(2, 101, 0, 3, 'Movie 101', $now);
        // Friend 3 rates movie 102 as 3
        $this->insertRating(3, 102, 0, 3, 'Movie 102', $now + 100);

        // Fetch activity feed for User 1 without friendId -> should contain both
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $feed = TestHelperRegistry::$lastBody['activity'];
        $this->assertCount(2, $feed);

        // Fetch activity feed for User 1 specifying friendId = 2 -> should only contain 101
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1, 2);
        $feedBob = TestHelperRegistry::$lastBody['activity'];
        $this->assertCount(1, $feedBob);
        $this->assertSame(101, (int) $feedBob[0]['movie_id']);
        $this->assertSame('Movie 101', $feedBob[0]['title']);

        // Fetch activity feed for User 1 specifying friendId = 3 -> should only contain 102
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1, 3);
        $feedCarol = TestHelperRegistry::$lastBody['activity'];
        $this->assertCount(1, $feedCarol);
        $this->assertSame(102, (int) $feedCarol[0]['movie_id']);
        $this->assertSame('Movie 102', $feedCarol[0]['title']);
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

    // ─── Popüler Listeler (profil beğenileri) ───────────────────────────────

    public function testLikeProfileTogglesAndCounts(): void
    {
        $this->social->likeProfile(1, ['owner_id' => 2, 'liked' => true]);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame(1, TestHelperRegistry::$lastBody['like_count']);

        // İkinci beğeni idempotent: sayı artmaz.
        TestHelperRegistry::reset();
        $this->social->likeProfile(1, ['owner_id' => 2, 'liked' => true]);
        $this->assertSame(1, TestHelperRegistry::$lastBody['like_count']);

        TestHelperRegistry::reset();
        $this->social->likeProfile(3, ['owner_id' => 2, 'liked' => true]);
        $this->assertSame(2, TestHelperRegistry::$lastBody['like_count']);

        // Geri alma.
        TestHelperRegistry::reset();
        $this->social->likeProfile(1, ['owner_id' => 2, 'liked' => false]);
        $this->assertSame(1, TestHelperRegistry::$lastBody['like_count']);
        $this->assertFalse(TestHelperRegistry::$lastBody['liked']);
    }

    public function testLikeProfileRejectsSelfLike(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(422);
        try {
            $this->social->likeProfile(1, ['owner_id' => 1, 'liked' => true]);
        } finally {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testLikeProfileRejectsPrivateProfile(): void
    {
        $this->db->exec('UPDATE users SET is_public = 0 WHERE id = 2');
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(403);
        try {
            $this->social->likeProfile(1, ['owner_id' => 2, 'liked' => true]);
        } finally {
            $this->assertSame(403, TestHelperRegistry::$lastStatus);
        }
    }

    public function testLikeProfileRejectsUnknownUser(): void
    {
        $this->expectException(TestExitException::class);
        $this->expectExceptionCode(404);
        try {
            $this->social->likeProfile(1, ['owner_id' => 999, 'liked' => true]);
        } finally {
            $this->assertSame(404, TestHelperRegistry::$lastStatus);
        }
    }

    public function testTopProfilesRanksByLikesThenLikedTitles(): void
    {
        // Bob 2 beğeni, Carol 1 beğeni alır; Alice 0 beğeni ama 1 sevilen yapım.
        $this->social->likeProfile(1, ['owner_id' => 2, 'liked' => true]);
        $this->social->likeProfile(3, ['owner_id' => 2, 'liked' => true]);
        $this->social->likeProfile(2, ['owner_id' => 3, 'liked' => true]);
        $this->insertRating(1, 101, 0, 3, 'The Matrix', 2000);

        TestHelperRegistry::reset();
        $this->social->getTopProfiles(1);
        $profiles = TestHelperRegistry::$lastBody['profiles'];

        $this->assertCount(3, $profiles);
        $this->assertSame('bob', $profiles[0]['username']);
        $this->assertSame(2, $profiles[0]['like_count']);
        $this->assertTrue($profiles[0]['me_liked']); // 1 numaralı kullanıcı Bob'u beğendi
        $this->assertSame('carol', $profiles[1]['username']);
        $this->assertFalse($profiles[1]['me_liked']);
        // Alice: beğenisi yok ama sevdiği yapım var; is_me işaretli.
        $this->assertSame('alice', $profiles[2]['username']);
        $this->assertTrue($profiles[2]['is_me']);
        // Afiş önizlemesi sevilen yapımdan gelir.
        $this->assertSame('The Matrix', $profiles[2]['previews'][0]['title']);
    }

    public function testTopProfilesExcludesPrivateAndUsernamelessUsers(): void
    {
        $this->db->exec('UPDATE users SET is_public = 0 WHERE id = 2');
        $this->db->exec('UPDATE users SET username = NULL WHERE id = 3');

        $this->social->getTopProfiles(1);
        $profiles = TestHelperRegistry::$lastBody['profiles'];

        $this->assertCount(1, $profiles);
        $this->assertSame('alice', $profiles[0]['username']);
    }

    public function testReportReviewAutoHidesAfterThreshold(): void
    {
        // Bob (2) yorum yazar; 3 farklı kullanıcı şikayet edince otomatik gizlenir.
        $now = now_ms();
        $this->db->exec('INSERT INTO users (id, email, display_name, username) VALUES (4, \'dave@example.com\', \'Dave\', \'dave\')');
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment)
             VALUES (2, 500, 0, 0, \'Spam Movie\', \'[]\', ?, 0, \'reklam icerigi\')'
        );
        $st->execute([$now]);

        $this->social->reportReview(1, ['user_id' => 2, 'movie_id' => 500, 'is_tv' => 0, 'reason' => 'spam']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertFalse(TestHelperRegistry::$lastBody['auto_hidden']);

        // Aynı kullanıcının tekrar şikayeti sayacı artırmaz (idempotent).
        TestHelperRegistry::reset();
        $this->social->reportReview(1, ['user_id' => 2, 'movie_id' => 500, 'is_tv' => 0, 'reason' => 'spam']);
        $this->assertFalse(TestHelperRegistry::$lastBody['auto_hidden']);

        TestHelperRegistry::reset();
        $this->social->reportReview(3, ['user_id' => 2, 'movie_id' => 500, 'is_tv' => 0, 'reason' => 'spam']);
        $this->assertFalse(TestHelperRegistry::$lastBody['auto_hidden']);

        TestHelperRegistry::reset();
        $this->social->reportReview(4, ['user_id' => 2, 'movie_id' => 500, 'is_tv' => 0, 'reason' => 'other']);
        $this->assertTrue(TestHelperRegistry::$lastBody['auto_hidden']);

        $hidden = $this->db->query('SELECT is_hidden FROM ratings WHERE user_id = 2 AND movie_id = 500')->fetchColumn();
        $this->assertSame(1, (int) $hidden);
    }

    public function testHiddenReviewExcludedFromReviewsAndActivityComment(): void
    {
        $this->acceptFriendship(1, 2);
        $now = now_ms();
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment, is_hidden)
             VALUES (2, 600, 0, 3, \'Hidden Review Movie\', \'[]\', ?, 0, \'kufurlu yorum\', 1)'
        );
        $st->execute([$now]);

        $this->social->getTitleReviews(1, 'movie', 600);
        $this->assertCount(0, TestHelperRegistry::$lastBody['friends']);
        $this->assertCount(0, TestHelperRegistry::$lastBody['community']);

        // Aktivitede puan görünür ama yorum metni sızmaz.
        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $feed = TestHelperRegistry::$lastBody['activity'];
        $this->assertCount(1, $feed);
        $this->assertNull($feed[0]['comment']);
    }

    public function testBlockUserRemovesFriendshipAndFiltersReviews(): void
    {
        $this->acceptFriendship(1, 2);
        $now = now_ms();
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment)
             VALUES (2, 700, 0, 3, \'Block Test Movie\', \'[]\', ?, 0, \'taciz eden yorum\')'
        );
        $st->execute([$now]);

        $this->social->blockUser(1, ['user_id' => 2]);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertNull($this->friendStatus(1, 2));
        $this->assertNull($this->friendStatus(2, 1));

        // Topluluk sorgusunda da görünmemeli (arkadaşlık zaten koptu).
        TestHelperRegistry::reset();
        $this->social->getTitleReviews(1, 'movie', 700);
        $this->assertCount(0, TestHelperRegistry::$lastBody['friends']);
        $this->assertCount(0, TestHelperRegistry::$lastBody['community']);

        // Ters yön: Bob da Alice'in yorumunu görmez.
        $st2 = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment)
             VALUES (1, 700, 0, 2, \'Block Test Movie\', \'[]\', ?, 0, \'alice yorumu\')'
        );
        $st2->execute([$now]);
        TestHelperRegistry::reset();
        $this->social->getTitleReviews(2, 'movie', 700);
        $this->assertCount(0, TestHelperRegistry::$lastBody['community']);

        // Engeli kaldırınca topluluk yorumu tekrar görünür.
        TestHelperRegistry::reset();
        $this->social->unblockUser(1, ['user_id' => 2]);
        $this->assertTrue(TestHelperRegistry::$lastBody['removed']);
        TestHelperRegistry::reset();
        $this->social->getTitleReviews(1, 'movie', 700);
        $this->assertCount(1, TestHelperRegistry::$lastBody['community']);
    }

    public function testActivityFeedFiltersBlockedUsers(): void
    {
        $this->acceptFriendship(1, 2);
        $now = now_ms();
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment)
             VALUES (2, 900, 0, 3, \'Feed Movie\', \'[]\', ?, 0, \'arkadas yorumu\')'
        );
        $st->execute([$now]);

        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $this->assertCount(1, TestHelperRegistry::$lastBody['activity']);

        $this->db->prepare(
            'INSERT INTO user_blocks (user_id, blocked_user_id, created_at) VALUES (1, 2, ?)'
        )->execute([$now]);

        TestHelperRegistry::reset();
        $this->social->getActivityFeed(1);
        $this->assertCount(0, TestHelperRegistry::$lastBody['activity']);
    }

    public function testReportOwnReviewRejected(): void
    {
        $now = now_ms();
        $st = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, genre_ids, updated_at, deleted, comment)
             VALUES (1, 800, 0, 2, \'Own Movie\', \'[]\', ?, 0, \'kendi yorumum\')'
        );
        $st->execute([$now]);

        $this->expectException(TestExitException::class);
        try {
            $this->social->reportReview(1, ['user_id' => 1, 'movie_id' => 800, 'is_tv' => 0]);
        } finally {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testBlockedUserCannotSendFriendRequest(): void
    {
        // Alice (1), Bob'u (2) engeller → Bob, Alice'e istek atamaz;
        // yanıt "bulunamadı" ile aynıdır (engel bilgisi sızmaz).
        $this->social->blockUser(1, ['user_id' => 2]);

        TestHelperRegistry::reset();
        try {
            $this->social->sendFriendRequest(2, ['search_query' => 'alice']);
            $this->fail('Engellenen kullanıcının isteği reddedilmeliydi.');
        } catch (TestExitException $e) {
            $this->assertSame(404, TestHelperRegistry::$lastStatus);
            $this->assertSame('Kullanıcı bulunamadı.', TestHelperRegistry::$lastBody['error']);
        }
        $this->assertNull($this->friendStatus(2, 1));

        // Ters yön: engelleyen de engellediğine istek atamaz.
        TestHelperRegistry::reset();
        try {
            $this->social->sendFriendRequest(1, ['search_query' => 'bob']);
            $this->fail('Engelleyenin isteği de reddedilmeliydi.');
        } catch (TestExitException $e) {
            $this->assertSame(404, TestHelperRegistry::$lastStatus);
        }

        // Engel kalkınca istek normal akışına döner.
        $this->social->unblockUser(1, ['user_id' => 2]);
        TestHelperRegistry::reset();
        $this->social->sendFriendRequest(2, ['search_query' => 'alice']);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame('pending', $this->friendStatus(2, 1));
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
                created_at INTEGER,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                comment TEXT,
                is_spoiler INTEGER NOT NULL DEFAULT 0,
                is_private INTEGER NOT NULL DEFAULT 0,
                is_hidden INTEGER NOT NULL DEFAULT 0
            )'
        );
        $this->db->exec(
            'CREATE TABLE review_reports (
                reporter_id INTEGER NOT NULL,
                reported_user_id INTEGER NOT NULL,
                movie_id INTEGER NOT NULL,
                is_tv INTEGER NOT NULL,
                reason TEXT NOT NULL DEFAULT \'other\',
                status TEXT NOT NULL DEFAULT \'open\',
                created_at INTEGER NOT NULL,
                PRIMARY KEY (reporter_id, reported_user_id, movie_id, is_tv)
            )'
        );
        $this->db->exec(
            'CREATE TABLE user_blocks (
                user_id INTEGER NOT NULL,
                blocked_user_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY (user_id, blocked_user_id)
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
                PRIMARY KEY (tmdb_id, is_tv, locale)
            )'
        );
        // Legacy fixtures still carry metadata inline. Mirror it into the
        // canonical catalog so production social queries exercise `titles`.
        $this->db->exec(
            'CREATE TRIGGER ratings_title_fixture AFTER INSERT ON ratings BEGIN
                INSERT INTO titles
                    (tmdb_id, is_tv, locale, title, poster_path, genre_ids, metadata_updated_at)
                VALUES
                    (NEW.movie_id, NEW.is_tv, \'tr\', NEW.title, NEW.poster_path, NEW.genre_ids, NEW.updated_at)
                ON CONFLICT(tmdb_id, is_tv, locale) DO UPDATE SET
                    title = COALESCE(excluded.title, titles.title),
                    poster_path = COALESCE(excluded.poster_path, titles.poster_path),
                    genre_ids = COALESCE(excluded.genre_ids, titles.genre_ids),
                    metadata_updated_at = MAX(excluded.metadata_updated_at, titles.metadata_updated_at);
            END'
        );
        $this->db->exec(
            'CREATE TRIGGER watchlist_title_fixture AFTER INSERT ON watchlist BEGIN
                INSERT INTO titles
                    (tmdb_id, is_tv, locale, title, poster_path, backdrop_path, overview,
                     vote_average, release_date, genre_ids, metadata_updated_at)
                VALUES
                    (NEW.id, NEW.is_tv, \'tr\', NEW.title, NEW.poster_path, NEW.backdrop_path,
                     NEW.overview, NEW.vote_average, NEW.release_date, NEW.genre_ids, NEW.updated_at)
                ON CONFLICT(tmdb_id, is_tv, locale) DO UPDATE SET
                    title = COALESCE(excluded.title, titles.title),
                    poster_path = COALESCE(excluded.poster_path, titles.poster_path),
                    backdrop_path = COALESCE(excluded.backdrop_path, titles.backdrop_path),
                    overview = COALESCE(excluded.overview, titles.overview),
                    vote_average = COALESCE(excluded.vote_average, titles.vote_average),
                    release_date = COALESCE(excluded.release_date, titles.release_date),
                    genre_ids = COALESCE(excluded.genre_ids, titles.genre_ids),
                    metadata_updated_at = MAX(excluded.metadata_updated_at, titles.metadata_updated_at);
            END'
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
            'CREATE TABLE profile_likes (
                voter_id INTEGER NOT NULL,
                owner_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                PRIMARY KEY (voter_id, owner_id)
            )'
        );
        $this->db->exec(
            'CREATE TABLE couch_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                host_id INTEGER NOT NULL,
                guest_id INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT \'pending\',
                deck TEXT NOT NULL,
                host_votes TEXT NOT NULL,
                guest_votes TEXT NOT NULL,
                matched_key TEXT,
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

    public function testGetFriendsDoesNotExposeEmail(): void
    {
        // E-posta, kullanıcı adı bilinen herkes tarafından toplanabiliyordu
        // (istek gönder → pending_sent içinden oku). Hiçbir listede dönmemeli.
        $this->acceptFriendship(1, 2);
        $st = $this->db->prepare(
            'INSERT INTO friends (user_id, friend_id, status, created_at, updated_at)
             VALUES (?, ?, "pending", 1000, 1000)'
        );
        $st->execute([1, 3]); // gönderilen istek
        $st->execute([4, 1]); // gelen istek

        $this->db->exec('INSERT INTO users (id, email, display_name, username) VALUES (4, \'dave2@example.com\', \'Dave2\', \'dave2\')');

        $this->social->getFriends(1);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        foreach (['friends', 'pending_received', 'pending_sent'] as $listKey) {
            foreach ($body[$listKey] as $entry) {
                $this->assertArrayNotHasKey('email', $entry, "$listKey e-posta sızdırıyor");
                $this->assertArrayHasKey('username', $entry);
            }
        }
        $this->assertNotEmpty($body['friends']);
        $this->assertNotEmpty($body['pending_sent']);
        $this->assertNotEmpty($body['pending_received']);
    }

    public function testAllTasteMatchesReturnsScoresForAcceptedFriends(): void
    {
        // 1↔2 arkadaş ve ortak zevk var; 3 arkadaş değil → listede olmamalı.
        $this->acceptFriendship(1, 2);
        foreach ([201, 202, 203] as $i => $movieId) {
            $this->insertRating(1, $movieId, 0, 3, "Movie $movieId", 1000 + $i, '[28,878]');
            $this->insertRating(2, $movieId, 0, 3, "Movie $movieId", 2000 + $i, '[28,878]');
        }
        $this->insertRating(3, 301, 0, 3, 'Movie X', 1000, '[28]');

        $this->social->getAllTasteMatches(1);
        $body = TestHelperRegistry::$lastBody;

        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertCount(1, $body['scores']);
        $entry = $body['scores'][0];
        $this->assertSame(2, $entry['friend_id']);
        $this->assertSame(100, $entry['score']); // tekil uçla aynı matematik
        $this->assertTrue($entry['has_data']);
        $this->assertSame(3, $entry['common_count']);
    }

    // ─── Birlikte Seç (couch) ────────────────────────────────────────────────

    private function couchDeck(int $count = 5): array
    {
        $deck = [];
        for ($i = 1; $i <= $count; $i++) {
            $deck[] = [
                'movie_id' => 100 + $i,
                'is_tv' => 0,
                'title' => "Deck Movie $i",
                'poster_path' => "/d$i.jpg",
                'vote_average' => 7.0,
            ];
        }
        return $deck;
    }

    private function createCouch(int $hostId = 1, int $guestId = 2): int
    {
        $this->acceptFriendship($hostId, $guestId);
        $this->social->createCouchSession($hostId, [
            'friend_id' => $guestId,
            'deck' => $this->couchDeck(),
        ]);
        return (int) TestHelperRegistry::$lastBody['session']['id'];
    }

    public function testCouchCreateRequiresFriendshipAndValidDeck(): void
    {
        // Arkadaş olmayan hedef → 403.
        try {
            $this->social->createCouchSession(1, [
                'friend_id' => 3,
                'deck' => $this->couchDeck(),
            ]);
            $this->fail('Arkadaş olmayanla oturum açılabildi');
        } catch (TestExitException $e) {
            $this->assertSame(403, TestHelperRegistry::$lastStatus);
        }

        // Çok küçük deste → 422.
        $this->acceptFriendship(1, 2);
        try {
            $this->social->createCouchSession(1, [
                'friend_id' => 2,
                'deck' => $this->couchDeck(2),
            ]);
            $this->fail('2 kartlık deste kabul edildi');
        } catch (TestExitException $e) {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testCouchLifecyclePendingActiveAndProgressPrivacy(): void
    {
        $id = $this->createCouch();
        $s = TestHelperRegistry::$lastBody['session'];
        $this->assertSame('pending', $s['status']);
        $this->assertTrue($s['is_host']);
        $this->assertCount(5, $s['deck']);

        // Misafir aktif oturumunu görür; ilk teması pending → active taşır.
        $this->social->getActiveCouchSession(2);
        $g = TestHelperRegistry::$lastBody['session'];
        $this->assertSame($id, $g['id']);
        $this->assertFalse($g['is_host']);

        $this->social->getCouchSession(2, $id);
        $this->assertSame('active', TestHelperRegistry::$lastBody['session']['status']);

        // Host oy verir; misafir yalnızca İLERLEME sayısını görür, oyları değil.
        $this->social->voteCouchSession(1, $id, ['movie_id' => 101, 'is_tv' => 0, 'liked' => true]);
        $this->social->getCouchSession(2, $id);
        $g = TestHelperRegistry::$lastBody['session'];
        $this->assertSame(1, $g['their_progress']);
        // Karşı tarafın oyları sızmaz. (object) cast'i nedeniyle boş oy kümesi
        // stdClass'tır — JSON'da `{}` üretmesi tam da istenen davranış.
        $this->assertSame([], (array) $g['my_votes']);
    }

    public function testCouchMutualLikeMatches(): void
    {
        $id = $this->createCouch();

        // Host 101'i beğenir → eşleşme yok; misafir gelmediği için hâlâ pending.
        $this->social->voteCouchSession(1, $id, ['movie_id' => 101, 'is_tv' => 0, 'liked' => true]);
        $this->assertSame('pending', TestHelperRegistry::$lastBody['session']['status']);

        // Misafir 101'i beğenir → eşleşme; eşleşen yapım payload'da döner.
        $this->social->voteCouchSession(2, $id, ['movie_id' => 101, 'is_tv' => 0, 'liked' => true]);
        $s = TestHelperRegistry::$lastBody['session'];
        $this->assertSame('matched', $s['status']);
        $this->assertSame('Deck Movie 1', $s['matched']['title']);

        // Eşleşmiş oturumda 'cancel' finish anlamına gelir → ended.
        $this->social->cancelCouchSession(1, $id);
        $this->assertSame('ended', TestHelperRegistry::$lastBody['status']);
    }

    public function testCouchParticipantVotesAccumulateWithoutOverwriting(): void
    {
        $id = $this->createCouch();

        $this->social->voteCouchSession(1, $id, ['movie_id' => 101, 'is_tv' => 0, 'liked' => true]);
        $this->social->voteCouchSession(1, $id, ['movie_id' => 102, 'is_tv' => 0, 'liked' => false]);

        $st = $this->db->prepare('SELECT host_votes FROM couch_sessions WHERE id = ?');
        $st->execute([$id]);
        $votes = json_decode((string) $st->fetchColumn(), true);
        $this->assertSame(true, $votes['movie_101']);
        $this->assertSame(false, $votes['movie_102']);
    }

    public function testCouchDislikesDoNotMatchAndDeckExhaustionEnds(): void
    {
        $id = $this->createCouch();

        // Host hepsini beğenir, misafir hepsini geçer → eşleşme YOK, ended.
        for ($i = 1; $i <= 5; $i++) {
            $this->social->voteCouchSession(1, $id, ['movie_id' => 100 + $i, 'is_tv' => 0, 'liked' => true]);
            $this->social->voteCouchSession(2, $id, ['movie_id' => 100 + $i, 'is_tv' => 0, 'liked' => false]);
        }
        $s = TestHelperRegistry::$lastBody['session'];
        $this->assertSame('ended', $s['status']);
        $this->assertNull($s['matched']);
    }

    public function testCouchRejectsOutsidersAndForeignDeckItems(): void
    {
        $id = $this->createCouch();

        // Katılımcı olmayan kullanıcı → 403.
        try {
            $this->social->getCouchSession(3, $id);
            $this->fail('Katılımcı olmayan oturumu okuyabildi');
        } catch (TestExitException $e) {
            $this->assertSame(403, TestHelperRegistry::$lastStatus);
        }

        // Destede olmayan yapıma oy → 422.
        try {
            $this->social->voteCouchSession(1, $id, ['movie_id' => 999, 'is_tv' => 0, 'liked' => true]);
            $this->fail('Deste dışı yapıma oy verilebildi');
        } catch (TestExitException $e) {
            $this->assertSame(422, TestHelperRegistry::$lastStatus);
        }
    }

    public function testCouchNewSessionCancelsPreviousOpenOnes(): void
    {
        $first = $this->createCouch();
        // Aynı çift yeni oturum açar → eski pending oturum iptal edilir.
        $this->social->createCouchSession(1, [
            'friend_id' => 2,
            'deck' => $this->couchDeck(),
        ]);
        $second = (int) TestHelperRegistry::$lastBody['session']['id'];
        $this->assertNotSame($first, $second);

        $st = $this->db->prepare('SELECT status FROM couch_sessions WHERE id = ?');
        $st->execute([$first]);
        $this->assertSame('cancelled', $st->fetchColumn());
    }

    public function testUsedCouchMoviesExcludesPreviouslyPlayedDecks(): void
    {
        $id = $this->createCouch();

        // At this point, the session status is 'pending' (open). It shouldn't be returned by getUsedCouchMovies yet
        $this->social->getUsedCouchMovies(1, 2);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $this->assertSame([], TestHelperRegistry::$lastBody['used_keys']);

        // End the session to make it 'ended' (completed)
        $up = $this->db->prepare("UPDATE couch_sessions SET status = 'ended' WHERE id = ?");
        $up->execute([$id]);

        // Now it should return the deck movie keys (since it is completed)
        $this->social->getUsedCouchMovies(1, 2);
        $this->assertSame(200, TestHelperRegistry::$lastStatus);
        $expectedKeys = [
            'movie_101',
            'movie_102',
            'movie_103',
            'movie_104',
            'movie_105',
        ];
        $this->assertEquals($expectedKeys, TestHelperRegistry::$lastBody['used_keys']);
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

    private function insertRatingPrivate(int $userId, int $movieId, int $isTv, int $rating, string $title, int $updatedAt, int $isPrivate): void
    {
        $stmt = $this->db->prepare(
            'INSERT INTO ratings (user_id, movie_id, is_tv, rating, title, poster_path, genre_ids, updated_at, deleted, is_private)
             VALUES (?, ?, ?, ?, ?, "/poster.jpg", NULL, ?, 0, ?)'
        );
        $stmt->execute([$userId, $movieId, $isTv, $rating, $title, $updatedAt, $isPrivate]);
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
