<!DOCTYPE html>
<html lang="<?php echo htmlspecialchars($lang ?? 'tr'); ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <?php
        $ogTitle = sprintf($t['og_title'], $displayName);
        $ogDesc = sprintf($t['og_desc'], $userHandle);
        if (!empty($dna)) {
            $ogTitle = sprintf($t['og_dna_title'], $displayName, $dna['archetype']);
            $ogDesc = sprintf($t['og_dna_desc'], $dna['archetype'], $dna['essence']);
        }
        
        $ogImage = '';
        if (!empty($ratings) && !empty($ratings[0]['poster_path'])) {
            $ogImage = "https://image.tmdb.org/t/p/w500" . $ratings[0]['poster_path'];
        } elseif (!empty($goodRatings) && !empty($goodRatings[0]['poster_path'])) {
            $ogImage = "https://image.tmdb.org/t/p/w500" . $goodRatings[0]['poster_path'];
        } elseif (!empty($watchlist) && !empty($watchlist[0]['poster_path'])) {
            $ogImage = "https://image.tmdb.org/t/p/w500" . $watchlist[0]['poster_path'];
        }
    ?>
    <title><?php echo htmlspecialchars($ogTitle); ?></title>
    <meta property="og:title" content="<?php echo htmlspecialchars($ogTitle); ?>">
    <meta property="og:description" content="<?php echo htmlspecialchars($ogDesc); ?>">
    <?php if (!empty($ogImage)): ?>
        <meta property="og:image" content="<?php echo htmlspecialchars($ogImage); ?>">
    <?php endif; ?>
    <meta property="og:type" content="profile">
    <meta name="twitter:card" content="summary_large_image">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0B0F19;
            --surface: #151D30;
            --red: #E50914;
            --gold: #FFB300;
            --ink: #FFFFFF;
            --dim: #94A3B8;
            --border: rgba(255, 255, 255, 0.08);
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            background-color: var(--bg);
            color: var(--ink);
            font-family: 'Outfit', sans-serif;
            line-height: 1.6;
            padding-bottom: 80px;
        }

        .container {
            max-width: 1000px;
            margin: 0 auto;
            padding: 20px;
            position: relative;
            z-index: 1;
        }

        /* ── Sinematik arkaplan ─────────────────────────────────────────
           Yalnızca transform anime edilir (GPU dostu); içerik .container
           z-index:1 ile üstte kalır, grain katmanı pointer-events almaz. */
        .bg-cinema {
            position: fixed;
            inset: 0;
            z-index: 0;
            overflow: hidden;
            pointer-events: none;
        }

        .bg-cinema .orb {
            position: absolute;
            border-radius: 50%;
            filter: blur(80px);
            will-change: transform;
        }

        .orb-red {
            width: 55vmax;
            height: 55vmax;
            top: -22vmax;
            left: -18vmax;
            background: radial-gradient(circle, rgba(229, 9, 20, 0.32), transparent 70%);
            animation: orb-drift-a 26s ease-in-out infinite alternate;
        }

        .orb-gold {
            width: 45vmax;
            height: 45vmax;
            bottom: -18vmax;
            right: -14vmax;
            background: radial-gradient(circle, rgba(255, 179, 0, 0.22), transparent 70%);
            animation: orb-drift-b 34s ease-in-out infinite alternate;
        }

        .orb-blue {
            width: 50vmax;
            height: 50vmax;
            top: 30%;
            left: 55%;
            background: radial-gradient(circle, rgba(46, 84, 175, 0.28), transparent 70%);
            animation: orb-drift-c 30s ease-in-out infinite alternate;
        }

        /* Projeksiyon ışığı: çapraz süpüren çok soluk bant */
        .beam {
            position: absolute;
            top: -60%;
            left: -40%;
            width: 45vmax;
            height: 220%;
            background: linear-gradient(90deg, transparent, rgba(255, 236, 200, 0.05), transparent);
            transform: rotate(18deg);
            animation: beam-sweep 19s ease-in-out infinite;
        }

        @keyframes orb-drift-a {
            to { transform: translate(10vmax, 8vmax) scale(1.12); }
        }

        @keyframes orb-drift-b {
            to { transform: translate(-9vmax, -7vmax) scale(1.18); }
        }

        @keyframes orb-drift-c {
            to { transform: translate(-12vmax, 6vmax) scale(0.9); }
        }

        @keyframes beam-sweep {
            0%, 100% { transform: translateX(0) rotate(18deg); }
            50% { transform: translateX(120vmax) rotate(18deg); }
        }

        /* Film greni: tüm sayfanın üzerinde çok soluk kumlanma */
        body::after {
            content: '';
            position: fixed;
            inset: -100px;
            z-index: 2;
            pointer-events: none;
            opacity: 0.05;
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='240' height='240'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
            animation: grain-shift 1.2s steps(6) infinite;
        }

        @keyframes grain-shift {
            0% { transform: translate(0, 0); }
            100% { transform: translate(60px, -40px); }
        }

        @media (prefers-reduced-motion: reduce) {
            .bg-cinema .orb,
            .beam,
            body::after {
                animation: none;
            }
        }

        /* Header / Profile Card */
        header {
            margin-top: 40px;
            margin-bottom: 40px;
            text-align: center;
            padding: 40px 20px;
            background: linear-gradient(135deg, rgba(21, 29, 48, 0.6) 0%, rgba(11, 15, 25, 0.8) 100%);
            border-radius: 24px;
            border: 1px solid var(--border);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
            backdrop-filter: blur(10px);
        }

        .avatar {
            width: 90px;
            height: 90px;
            border-radius: 50%;
            background: linear-gradient(45deg, var(--red), var(--gold));
            margin: 0 auto 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 36px;
            font-weight: 800;
            color: white;
            box-shadow: 0 8px 24px rgba(229, 9, 20, 0.3);
        }

        h1 {
            font-size: 28px;
            font-weight: 800;
            letter-spacing: -0.5px;
            margin-bottom: 6px;
        }

        .handle {
            color: var(--gold);
            font-weight: 600;
            font-size: 16px;
            margin-bottom: 24px;
            display: inline-block;
        }

        .cta-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background-color: var(--red);
            color: white;
            text-decoration: none;
            font-weight: 700;
            padding: 14px 28px;
            border-radius: 12px;
            font-size: 15px;
            transition: transform 0.2s, box-shadow 0.2s;
            box-shadow: 0 10px 20px rgba(229, 9, 20, 0.25);
        }

        .cta-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 15px 25px rgba(229, 9, 20, 0.4);
        }

        /* Sinema DNA kartı */
        .dna {
            background: linear-gradient(135deg, rgba(255, 179, 0, 0.14) 0%, rgba(229, 9, 20, 0.12) 100%);
            border: 1px solid rgba(255, 179, 0, 0.35);
            border-radius: 24px;
            padding: 32px 24px;
            text-align: center;
            margin-bottom: 40px;
        }
        .dna-emoji { font-size: 48px; line-height: 1; }
        .dna-label {
            color: var(--gold);
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 3px;
            margin-top: 12px;
            /* lang="tr" sayesinde i→İ doğru; PHP'de uppercase entity bozar. */
            text-transform: uppercase;
        }
        .dna-name {
            font-size: 30px;
            font-weight: 800;
            margin: 6px 0 10px;
        }
        .dna-essence { color: var(--dim); font-size: 15px; }
        .dna-chips {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            justify-content: center;
            margin-top: 18px;
        }
        .dna-chip {
            padding: 7px 14px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 600;
            background: rgba(255, 179, 0, 0.12);
            color: var(--gold);
            border: 1px solid rgba(255, 179, 0, 0.4);
        }
        .dna-chip.genre {
            background: var(--surface);
            color: var(--ink);
            border-color: var(--border);
        }
        .dna-themes-evidence {
            margin-top: 24px;
            text-align: left;
            display: flex;
            flex-direction: column;
            gap: 16px;
        }
        .dna-theme-row {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .dna-theme-row .theme-name {
            align-self: flex-start;
        }
        .dna-theme-posters {
            display: flex;
            gap: 8px;
            overflow-x: auto;
            padding-bottom: 4px;
        }
        .dna-theme-poster-wrapper {
            display: block;
            text-decoration: none;
            position: relative;
            width: 50px;
            height: 75px;
            border-radius: 6px;
            overflow: hidden;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
            border: 1px solid var(--border);
            flex-shrink: 0;
            background-color: var(--surface);
        }
        .dna-theme-poster {
            width: 100%;
            height: 100%;
            object-fit: cover;
            display: block;
        }
        .dna-theme-poster.empty {
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 18px;
            color: var(--dim);
        }
        .dna-signals {
            text-align: left;
            margin-top: 22px;
            display: grid;
            gap: 10px;
        }
        .dna-signal {
            color: var(--ink);
            font-size: 14px;
            line-height: 1.4;
            padding-left: 18px;
            position: relative;
        }
        .dna-signal::before {
            content: '';
            position: absolute;
            left: 0;
            top: 8px;
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background: var(--gold);
        }
        .dna-accuracy {
            margin-top: 18px;
            padding: 12px 16px;
            border-radius: 14px;
            background: rgba(52, 199, 89, 0.12);
            border: 1px solid rgba(52, 199, 89, 0.4);
            color: #E8FFF0;
            font-size: 13.5px;
            font-weight: 600;
        }

        /* Sections */
        section {
            margin-bottom: 48px;
        }

        h2 {
            font-size: 20px;
            font-weight: 700;
            margin-bottom: 20px;
            border-left: 4px solid var(--gold);
            padding-left: 12px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        /* Bölüm içi Film / Dizi alt başlıkları */
        .type-heading {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 13px;
            font-weight: 700;
            letter-spacing: 2px;
            color: var(--dim);
            text-transform: uppercase;
            margin: 22px 0 14px;
        }

        .type-heading::after {
            content: '';
            flex: 1;
            height: 1px;
            background: var(--border);
        }

        .type-group + .type-group {
            margin-top: 28px;
        }

        /* Grid Layout */
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
            gap: 20px;
        }

        .card {
            background-color: var(--surface);
            border-radius: 16px;
            overflow: hidden;
            border: 1px solid var(--border);
            transition: transform 0.3s, box-shadow 0.3s;
            position: relative;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0, 0, 0, 0.4);
        }

        .poster-wrap {
            display: block;
            text-decoration: none;
            aspect-ratio: 2/3;
            width: 100%;
            background-color: #0d121f;
            position: relative;
            overflow: hidden;
        }

        .poster {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }

        .poster-placeholder {
            width: 100%;
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 12px;
            color: var(--dim);
            text-align: center;
            padding: 10px;
            background-color: #0e1422;
        }

        .card-info {
            padding: 12px;
        }

        .card-title {
            font-size: 13px;
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            margin-bottom: 4px;
        }

        .card-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 11px;
            color: var(--dim);
        }

        .rating-badge {
            display: inline-flex;
            align-items: center;
            background-color: rgba(255, 179, 0, 0.15);
            color: var(--gold);
            padding: 2px 6px;
            border-radius: 4px;
            font-weight: 700;
        }

        .empty-text {
            color: var(--dim);
            font-size: 14px;
            padding: 20px 0;
        }

        @media (max-width: 480px) {
            .grid {
                grid-template-columns: repeat(3, 1fr);
                gap: 10px;
            }
            .card-info {
                display: none; /* Mobilde sadece afişleri göstererek temiz görünüm */
            }
            header {
                padding: 30px 15px;
            }
            h1 {
                font-size: 24px;
            }
        }

        .dna-theme-row-collapsed {
            display: none !important;
        }

        .toggle-themes-btn {
            background: rgba(255, 179, 0, 0.1);
            color: var(--gold);
            border: 1px dashed rgba(255, 179, 0, 0.4);
            border-radius: 12px;
            padding: 10px;
            font-size: 13.5px;
            font-weight: 600;
            cursor: pointer;
            width: 100%;
            text-align: center;
            margin-top: 8px;
            transition: all 0.2s;
            font-family: inherit;
        }

        .toggle-themes-btn:hover {
            background: rgba(255, 179, 0, 0.2);
            border-color: var(--gold);
        }
    </style>
</head>
<body>
    <div class="bg-cinema" aria-hidden="true">
        <div class="orb orb-red"></div>
        <div class="orb orb-gold"></div>
        <div class="orb orb-blue"></div>
        <div class="beam"></div>
    </div>
    <div class="container">
        <header>
            <div class="avatar"><?php echo mb_substr($displayName, 0, 1, 'UTF-8'); ?></div>
            <h1><?php echo $displayName; ?></h1>
            <span class="handle">@<?php echo $userHandle; ?></span>
            <div>
                <a href="https://cinema.mbkm.com.tr/download" class="cta-btn">
                    <?php echo sprintf($t['cta'], $displayName); ?>
                </a>
            </div>
        </header>

        <!-- Sinema DNA -->
        <?php if (!empty($dna)): ?>
            <div class="dna">
                <div class="dna-emoji"><?php echo $dna['emoji']; ?></div>
                <div class="dna-label"><?php echo $displayName; ?></div>
                <div class="dna-name"><?php echo htmlspecialchars($dna['archetype']); ?></div>
                <div class="dna-essence"><?php echo htmlspecialchars($dna['essence']); ?></div>

                <?php if (!empty($dna['themes_with_evidence'])): ?>
                    <div class="dna-themes-evidence" id="dna-themes-container">
                        <?php foreach ($dna['themes_with_evidence'] as $idx => $item): ?>
                            <div class="dna-theme-row<?php echo $idx >= 3 ? ' dna-theme-row-collapsed' : ''; ?>">
                                <span class="dna-chip theme-name"><?php echo htmlspecialchars($item['name']); ?></span>
                                <div class="dna-theme-posters">
                                    <?php foreach ($item['movies'] as $m): ?>
                                        <?php 
                                            $tmdbUrl = 'https://www.themoviedb.org/' . ($m['is_tv'] ? 'tv' : 'movie') . '/' . (int)$m['id'];
                                        ?>
                                        <a href="<?php echo htmlspecialchars($tmdbUrl); ?>" target="_blank" rel="noopener" class="dna-theme-poster-wrapper" title="<?php echo htmlspecialchars($m['title']); ?>">
                                            <?php if (!empty($m['poster_path'])): ?>
                                                <img class="dna-theme-poster" src="https://image.tmdb.org/t/p/w92<?php echo htmlspecialchars($m['poster_path']); ?>" alt="<?php echo htmlspecialchars($m['title']); ?>">
                                            <?php else: ?>
                                                <div class="dna-theme-poster empty">🎬</div>
                                            <?php endif; ?>
                                        </a>
                                    <?php endforeach; ?>
                                </div>
                            </div>
                        <?php endforeach; ?>
                        <?php if (count($dna['themes_with_evidence']) > 3): ?>
                            <button id="toggle-themes-btn" class="toggle-themes-btn"><?php echo htmlspecialchars($t['show_all_themes']); ?></button>
                        <?php endif; ?>
                    </div>
                <?php elseif (!empty($dna['themes'])): ?>
                    <div class="dna-chips">
                        <?php /* $t çeviri dizisi; döngü değişkeni onu ezmemeli */ ?>
                        <?php foreach ($dna['themes'] as $themeName): ?>
                            <span class="dna-chip"><?php echo htmlspecialchars($themeName); ?></span>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['genres'])): ?>
                    <div class="dna-chips">
                        <?php foreach ($dna['genres'] as $g): ?>
                            <span class="dna-chip genre"><?php echo htmlspecialchars($g); ?></span>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['signals'])): ?>
                    <div class="dna-signals">
                        <?php foreach ($dna['signals'] as $s): ?>
                            <div class="dna-signal"><?php echo htmlspecialchars($s); ?></div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['accuracy'])): ?>
                    <div class="dna-accuracy">✓ <?php echo htmlspecialchars($dna['accuracy']); ?></div>
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <?php
            // Kart gridini basar. Alt başlık (Filmler/Diziler) gruplandığı için
            // kart metasında tür yerine yıl gösterilir; yıl yoksa tür etiketi.
            $renderGrid = function (array $items) use ($t): void {
                ?>
                <div class="grid">
                    <?php foreach ($items as $r): ?>
                        <div class="card">
                            <?php
                                $tmdbUrl = 'https://www.themoviedb.org/' . ($r['is_tv'] ? 'tv' : 'movie') . '/' . (int)$r['movie_id'];
                                $year = substr((string)($r['release_date'] ?? ''), 0, 4);
                                $metaLabel = ctype_digit($year) && strlen($year) === 4
                                    ? $year
                                    : ($r['is_tv'] ? $t['tv'] : $t['movie']);
                            ?>
                            <a href="<?php echo htmlspecialchars($tmdbUrl); ?>" target="_blank" rel="noopener" class="poster-wrap">
                                <?php if (!empty($r['poster_path'])): ?>
                                    <img src="https://image.tmdb.org/t/p/w300<?php echo htmlspecialchars($r['poster_path']); ?>" alt="<?php echo htmlspecialchars($r['title']); ?>" class="poster" loading="lazy">
                                <?php else: ?>
                                    <div class="poster-placeholder"><?php echo htmlspecialchars($r['title']); ?></div>
                                <?php endif; ?>
                            </a>
                            <div class="card-info">
                                <div class="card-title"><?php echo htmlspecialchars($r['title']); ?></div>
                                <div class="card-meta">
                                    <span><?php echo htmlspecialchars($metaLabel); ?></span>
                                    <?php if (!empty($r['vote_average'])): ?>
                                        <span class="rating-badge">★ <?php echo round((float) $r['vote_average'], 1); ?></span>
                                    <?php endif; ?>
                                </div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
                <?php
            };

            // Bölüm içeriği: filmler ve diziler ayrı alt başlıklar altında.
            $renderSection = function (array $items, string $emptyText) use ($t, $renderGrid): void {
                if (empty($items)) {
                    echo '<p class="empty-text">' . htmlspecialchars($emptyText) . '</p>';
                    return;
                }
                $movies = array_values(array_filter($items, fn ($x) => empty($x['is_tv'])));
                $shows  = array_values(array_filter($items, fn ($x) => !empty($x['is_tv'])));
                if (!empty($movies)) {
                    echo '<div class="type-group"><h3 class="type-heading">' . htmlspecialchars($t['sub_movies']) . '</h3>';
                    $renderGrid($movies);
                    echo '</div>';
                }
                if (!empty($shows)) {
                    echo '<div class="type-group"><h3 class="type-heading">' . htmlspecialchars($t['sub_tv']) . '</h3>';
                    $renderGrid($shows);
                    echo '</div>';
                }
            };
        ?>

        <!-- Harika Buldukları (Favorites / Top Rated) -->
        <section>
            <h2><?php echo htmlspecialchars($t['sec_great']); ?></h2>
            <?php $renderSection($ratings, $t['empty_great']); ?>
        </section>

        <!-- İyi Buldukları (Liked / Good) -->
        <section>
            <h2><?php echo htmlspecialchars($t['sec_good']); ?></h2>
            <?php $renderSection($goodRatings, $t['empty_good']); ?>
        </section>

        <!-- İzleme Listesi (Watchlist) -->
        <section>
            <h2><?php echo htmlspecialchars($t['sec_watchlist']); ?></h2>
            <?php $renderSection($watchlist, $t['empty_watchlist']); ?>
        </section>
    </div>

    <script>
        document.addEventListener('DOMContentLoaded', function() {
            var toggleBtn = document.getElementById('toggle-themes-btn');
            if (toggleBtn) {
                toggleBtn.addEventListener('click', function() {
                    var collapsedRows = document.querySelectorAll('.dna-theme-row-collapsed');
                    collapsedRows.forEach(function(row) {
                        row.classList.remove('dna-theme-row-collapsed');
                    });
                    toggleBtn.style.display = 'none';
                });
            }
        });
    </script>
</body>
</html>
