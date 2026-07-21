<?php
declare(strict_types=1);

$e = static fn(mixed $value): string => htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
$posterUrl = static fn(?string $path, string $size = 'w500'): string =>
    $path ? 'https://image.tmdb.org/t/p/' . $size . $path : '';
/** Only emit CSS url() values that are known-safe TMDB CDN image URLs. */
$cssSafeHeroUrl = static function (string $url): string {
    if ($url === '' || !preg_match('#^https://image\.tmdb\.org/t/p/[A-Za-z0-9_]+/[A-Za-z0-9._/-]+$#', $url)) {
        return '';
    }
    return $url;
};
$tmdbHref = static function (array $item): string {
    $id = (int) ($item['movie_id'] ?? 0);
    if ($id <= 0) {
        return '';
    }
    $kind = ((int) ($item['is_tv'] ?? 0) === 1) ? 'tv' : 'movie';
    return 'https://www.themoviedb.org/' . $kind . '/' . $id;
};

$ogTitle = sprintf($t['og_title'], html_entity_decode($displayName));
$ogDesc = sprintf($t['og_desc'], html_entity_decode($userHandle));
if (!empty($dna)) {
    $ogTitle = sprintf($t['og_dna_title'], html_entity_decode($displayName), $dna['archetype']);
    $ogDesc = sprintf($t['og_dna_desc'], $dna['archetype'], $dna['essence']);
}

// Hero rotasyonu: her ziyarette Top 20'den rastgele bir görsel — profil canlı
// kalır. Top 20'de görselli aday yoksa diğer havuzlara düşülür.
$hasArt = static fn(array $item): bool =>
    !empty($item['backdrop_path']) || !empty($item['poster_path']);
$heroPool = array_values(array_filter(array_merge($topMovies, $topShows), $hasArt));
if ($heroPool === []) {
    $heroPool = array_values(array_filter(
        array_merge($ratings, $goodRatings, $watchlist),
        $hasArt
    ));
}
$heroCandidate = $heroPool !== [] ? $heroPool[array_rand($heroPool)] : null;
// Desktop: wide cinematic backdrop. Mobile: portrait poster so the art fits phone width.
$heroDesktop = $posterUrl($heroCandidate['backdrop_path'] ?? null, 'w1280');
$heroMobile = $posterUrl($heroCandidate['poster_path'] ?? null, 'w780');
if ($heroDesktop === '') {
    $heroDesktop = $heroMobile;
}
if ($heroMobile === '') {
    $heroMobile = $heroDesktop;
}
$ogImage = $posterUrl($heroCandidate['poster_path'] ?? null)
    ?: $posterUrl($heroCandidate['backdrop_path'] ?? null, 'w780');
// Hero kredisi: ziyaretçinin "bu hangi film?" merakını giderir, TMDB'ye köprü.
$heroCreditTitle = trim((string) ($heroCandidate['title'] ?? ''));
$heroCreditYear = !empty($heroCandidate['release_date'])
    ? substr((string) $heroCandidate['release_date'], 0, 4)
    : '';
$heroCreditHref = $heroCandidate !== null ? $tmdbHref($heroCandidate) : '';

$renderTopCards = static function (array $items) use ($e, $posterUrl, $tmdbHref, $t): void {
    $i = 0;
    foreach ($items as $item) {
        $title = trim((string) ($item['title'] ?? '')) ?: (((int) ($item['is_tv'] ?? 0) === 1) ? $t['tv'] : $t['movie']);
        $poster = $posterUrl($item['poster_path'] ?? null, 'w342');
        $year = !empty($item['release_date']) ? substr((string) $item['release_date'], 0, 4) : '';
        $href = $tmdbHref($item);
        $delay = min($i, 12) * 40;
        $i++;
        ?>
        <article class="rank-card reveal" style="--d:<?= $delay ?>ms">
            <span class="rank-number" aria-label="#<?= $e($item['rank']) ?>">#<?= $e($item['rank']) ?></span>
            <?php if ($href): ?><a class="poster-link" href="<?= $e($href) ?>" target="_blank" rel="noopener" title="<?= $e($title) ?>"><?php endif; ?>
            <div class="rank-poster">
                <?php if ($poster): ?>
                    <img src="<?= $e($poster) ?>" alt="<?= $e($title) ?>" loading="lazy" width="228" height="342">
                <?php else: ?>
                    <span class="poster-fallback" aria-hidden="true">C+</span>
                <?php endif; ?>
            </div>
            <?php if ($href): ?></a><?php endif; ?>
            <h3><?= $e($title) ?></h3>
            <?php if ($year): ?><p><?= $e($year) ?></p><?php endif; ?>
        </article>
        <?php
    }
};

$renderLibrary = static function (array $items, string $empty) use ($e, $posterUrl, $tmdbHref, $t): void {
    if (!$items) {
        echo '<p class="empty">' . $e($empty) . '</p>';
        return;
    }
    echo '<div class="library-grid">';
    foreach ($items as $item) {
        $title = trim((string) ($item['title'] ?? '')) ?: (((int) ($item['is_tv'] ?? 0) === 1) ? $t['tv'] : $t['movie']);
        $poster = $posterUrl($item['poster_path'] ?? null, 'w342');
        $year = !empty($item['release_date']) ? substr((string) $item['release_date'], 0, 4) : '';
        $href = $tmdbHref($item);
        echo '<article class="library-card reveal">';
        if ($href) {
            echo '<a class="poster-link" href="' . $e($href) . '" target="_blank" rel="noopener" title="' . $e($title) . '">';
        }
        echo '<div class="library-poster">';
        if ($poster) {
            echo '<img src="' . $e($poster) . '" alt="' . $e($title) . '" loading="lazy" width="228" height="342">';
        } else {
            echo '<span class="poster-fallback" aria-hidden="true">C+</span>';
        }
        echo '</div>';
        if ($href) {
            echo '</a>';
        }
        echo '<div><h3>' . $e($title) . '</h3><p>' . $e($year) . '</p></div></article>';
    }
    echo '</div>';
};

$renderSplitShelf = static function (
    string $headingId,
    string $title,
    array $movies,
    array $shows,
    string $emptyMovies,
    string $emptyShows,
) use ($e, $t, $renderLibrary): void {
    if (!$movies && !$shows) {
        return;
    }
    ?>
    <section class="shelf" aria-labelledby="<?= $e($headingId) ?>">
        <div class="section-head">
            <h2 id="<?= $e($headingId) ?>"><?= $e($title) ?></h2>
        </div>
        <?php if ($movies): ?>
        <div class="media-block">
            <h3 class="media-label"><?= $e($t['sub_movies']) ?></h3>
            <?php $renderLibrary($movies, $emptyMovies); ?>
        </div>
        <?php endif; ?>
        <?php if ($shows): ?>
        <div class="media-block">
            <h3 class="media-label"><?= $e($t['sub_tv']) ?></h3>
            <?php $renderLibrary($shows, $emptyShows); ?>
        </div>
        <?php endif; ?>
    </section>
    <?php
};
?>
<!doctype html>
<html lang="<?= $e($lang ?? 'tr') ?>">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="#08090c">
    <title><?= $e($ogTitle) ?></title>
    <meta name="description" content="<?= $e($ogDesc) ?>">
    <meta property="og:title" content="<?= $e($ogTitle) ?>">
    <meta property="og:description" content="<?= $e($ogDesc) ?>">
    <meta property="og:type" content="profile">
    <?php if ($ogImage): ?><meta property="og:image" content="<?= $e($ogImage) ?>"><?php endif; ?>
    <meta name="twitter:card" content="summary_large_image">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="preconnect" href="https://image.tmdb.org">
    <?php // Hero LCP: background-image tarayıcı taramasında geç keşfedilir; preload öne çeker. ?>
    <?php if ($heroDesktop): ?><link rel="preload" as="image" href="<?= $e($heroDesktop) ?>" media="(min-width: 761px)"><?php endif; ?>
    <?php if ($heroMobile): ?><link rel="preload" as="image" href="<?= $e($heroMobile) ?>" media="(max-width: 760px)"><?php endif; ?>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #08090c;
            --panel: #111319;
            --panel2: #171a21;
            --ink: #f7f5ef;
            --muted: #9b9da6;
            --gold: #ffc24b;
            --red: #ef3d45;
            --line: rgba(255, 255, 255, .1);
            --radius: 24px;
        }
        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body {
            margin: 0;
            background: var(--bg);
            color: var(--ink);
            font-family: Outfit, system-ui, sans-serif;
            line-height: 1.5;
            overflow-x: hidden;
        }
        a { font: inherit; color: inherit; }
        img { display: block; width: 100%; height: 100%; object-fit: cover; }

        .hero-stage {
            position: relative;
            min-height: min(92vh, 860px);
            display: flex;
            flex-direction: column;
            overflow: hidden;
            isolation: isolate;
        }
        /* Subtle cinematic aurora — soft gold & crimson orbs drifting slowly. */
        .hero-ambience {
            position: absolute;
            inset: 0;
            z-index: 1;
            pointer-events: none;
            overflow: hidden;
        }
        .ambience-orb {
            position: absolute;
            border-radius: 50%;
            filter: blur(56px);
            will-change: transform, opacity;
        }
        .ambience-orb--gold {
            width: min(70vw, 720px);
            height: min(70vw, 720px);
            top: -20%;
            left: -14%;
            background: radial-gradient(
                circle,
                rgba(255, 214, 120, .34) 0%,
                rgba(255, 194, 75, .18) 34%,
                rgba(255, 194, 75, .05) 58%,
                transparent 72%
            );
            animation: orbGold 20s ease-in-out infinite alternate;
        }
        .ambience-orb--crimson {
            width: min(65vw, 680px);
            height: min(65vw, 680px);
            top: 4%;
            right: -18%;
            background: radial-gradient(
                circle,
                rgba(255, 80, 90, .3) 0%,
                rgba(239, 61, 69, .16) 34%,
                rgba(160, 20, 30, .05) 58%,
                transparent 72%
            );
            animation: orbCrimson 24s ease-in-out infinite alternate;
        }
        .ambience-orb--warm {
            width: min(55vw, 560px);
            height: min(55vw, 560px);
            bottom: -20%;
            left: 26%;
            background: radial-gradient(
                circle,
                rgba(255, 180, 90, .22) 0%,
                rgba(220, 70, 50, .1) 44%,
                transparent 68%
            );
            animation: orbWarm 28s ease-in-out infinite alternate;
        }
        .ambience-ribbon {
            position: absolute;
            inset: -40%;
            background: linear-gradient(
                118deg,
                transparent 30%,
                rgba(255, 230, 160, .14) 44%,
                rgba(255, 90, 90, .1) 52%,
                transparent 68%
            );
            mix-blend-mode: screen;
            animation: ribbonSweep 18s ease-in-out infinite;
        }
        .hero-bg {
            position: absolute;
            inset: 0;
            z-index: 0;
            background-color: #101218;
            background-image: var(--hero-desktop);
            background-position: center center;
            background-size: cover;
            background-repeat: no-repeat;
            transform: scale(1.08);
            animation: heroDrift 16s ease-in-out infinite alternate;
        }
        .hero-bg::after {
            content: '';
            position: absolute;
            inset: 0;
            background:
                linear-gradient(180deg, rgba(8, 9, 12, .45) 0%, rgba(8, 9, 12, .25) 38%, rgba(8, 9, 12, .88) 78%, var(--bg) 100%),
                linear-gradient(90deg, rgba(8, 9, 12, .55) 0%, rgba(8, 9, 12, .15) 55%, rgba(8, 9, 12, .4) 100%);
        }
        .hero-topbar {
            position: relative;
            z-index: 2;
            display: flex;
            align-items: center;
            justify-content: space-between;
            width: min(1180px, calc(100% - 40px));
            margin: 0 auto;
            padding: 28px 0 0;
        }
        .brand { font-size: 1.35rem; font-weight: 800; letter-spacing: -.04em; text-decoration: none; }
        .brand b { color: var(--red); }
        .lang {
            color: var(--muted);
            font-size: .85rem;
            text-decoration: none;
            border: 1px solid var(--line);
            border-radius: 999px;
            padding: 10px 14px;
            backdrop-filter: blur(8px);
            background: rgba(8, 9, 12, .35);
            transition: color .25s ease, border-color .25s ease, background .25s ease;
        }
        .lang:hover { color: var(--ink); border-color: #ffffff55; background: rgba(8, 9, 12, .5); }

        /* Hero görsel kredisi: "bu hangi film?" — köşede küçük, TMDB'ye köprü. */
        .hero-credit {
            position: absolute;
            right: max(20px, calc((100% - 1180px) / 2));
            bottom: 20px;
            z-index: 3;
            padding: 8px 13px;
            border: 1px solid var(--line);
            border-radius: 999px;
            background: rgba(8, 9, 12, .45);
            backdrop-filter: blur(8px);
            color: var(--muted);
            font-size: .8rem;
            font-weight: 600;
            text-decoration: none;
            transition: color .25s ease, border-color .25s ease, background .25s ease;
        }
        a.hero-credit:hover {
            color: var(--ink);
            border-color: #ffc24b66;
            background: rgba(8, 9, 12, .65);
        }

        .hero-content {
            position: relative;
            z-index: 2;
            width: min(1180px, calc(100% - 40px));
            margin: auto auto 0;
            padding: 48px 0 72px;
            animation: heroIn .9s ease both;
        }
        .eyebrow {
            margin: 0 0 10px;
            color: var(--gold);
            font-size: .72rem;
            font-weight: 700;
            letter-spacing: .18em;
            text-transform: uppercase;
            background: linear-gradient(100deg, #c9a04a 0%, #ffc24b 35%, #fff1c8 50%, #ffc24b 65%, #c9a04a 100%);
            background-size: 220% 100%;
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            animation: goldSheen 7s ease-in-out infinite;
        }
        .hero-archetype {
            margin: 0;
            max-width: 16ch;
            font-size: clamp(2.4rem, 7vw, 5.2rem);
            line-height: .98;
            letter-spacing: -.055em;
            font-weight: 800;
            text-wrap: balance;
            text-shadow: 0 12px 40px rgba(0, 0, 0, .45);
        }
        .hero-essence {
            margin: 18px 0 0;
            max-width: 38rem;
            color: #d8d8dc;
            font-size: clamp(1.05rem, 2.2vw, 1.25rem);
        }
        .hero-meta {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 14px 22px;
            margin-top: 28px;
        }
        .hero-identity {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }
        .hero-name { margin: 0; font-size: 1.05rem; font-weight: 700; }
        .hero-handle { margin: 0; color: var(--muted); font-size: .92rem; }
        .cta {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            min-height: 48px;
            padding: 0 20px;
            border-radius: 14px;
            background: linear-gradient(135deg, #f7f5ef 0%, #e8e2d4 100%);
            color: #08090c;
            text-decoration: none;
            font-weight: 700;
            box-shadow: 0 8px 28px rgba(0, 0, 0, .35);
            transition: background .3s ease, transform .25s ease, box-shadow .3s ease;
        }
        .cta:hover {
            background: linear-gradient(135deg, #ffc24b 0%, #f0a820 100%);
            transform: translateY(-2px);
            box-shadow: 0 12px 32px rgba(255, 194, 75, .28);
        }
        .cta:focus-visible, .lang:focus-visible, .poster-link:focus-visible {
            outline: 3px solid var(--gold);
            outline-offset: 3px;
        }

        .shell { width: min(1180px, calc(100% - 40px)); margin: auto; padding: 8px 0 80px; }
        section.shelf, section.rank-shelf, section.dna-panel { margin-top: 56px; }
        .section-head { margin-bottom: 18px; }
        .section-head h2 {
            margin: 4px 0 0;
            font-size: clamp(1.7rem, 4vw, 2.6rem);
            line-height: 1.05;
            letter-spacing: -.045em;
        }
        .section-head p { margin: 8px 0 0; color: var(--muted); max-width: 40rem; }

        .rank-track {
            display: grid;
            grid-auto-flow: column;
            grid-auto-columns: 158px;
            gap: 16px;
            overflow-x: auto;
            padding: 8px 4px 18px;
            scroll-snap-type: x proximity;
            scrollbar-color: #444 transparent;
        }
        .rank-card { position: relative; scroll-snap-align: start; min-width: 0; }
        .rank-poster, .library-poster {
            aspect-ratio: 2 / 3;
            overflow: hidden;
            border-radius: 16px;
            background: var(--panel2);
            border: 1px solid var(--line);
            transition: transform .25s ease, box-shadow .25s ease;
        }
        .rank-card:first-child .rank-poster {
            box-shadow: 0 0 0 2px var(--gold), 0 20px 50px #000;
        }
        .poster-link { display: block; text-decoration: none; }
        .poster-link:hover .rank-poster,
        .poster-link:hover .library-poster {
            transform: translateY(-4px) scale(1.02);
            box-shadow: 0 16px 36px #000a;
        }
        .rank-number {
            position: absolute;
            z-index: 2;
            top: -8px;
            left: -7px;
            display: grid;
            place-items: center;
            min-width: 38px;
            height: 38px;
            padding: 0 7px;
            border-radius: 12px;
            background: var(--gold);
            color: #15100a;
            font-size: .9rem;
            font-weight: 800;
            box-shadow: 0 7px 20px #0009;
            animation: rankPop .55s ease both;
            animation-delay: var(--d, 0ms);
        }
        .rank-card h3, .library-card h3 {
            margin: 11px 0 0;
            font-size: .96rem;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .rank-card p, .library-card p {
            margin: 2px 0 0;
            color: var(--muted);
            font-size: .82rem;
        }
        .poster-fallback {
            display: grid;
            place-items: center;
            width: 100%;
            height: 100%;
            color: #5a5c65;
            font-weight: 800;
            font-size: 1.5rem;
            background: linear-gradient(145deg, #20232b, #111319);
        }
        .empty {
            padding: 28px;
            border: 1px dashed var(--line);
            border-radius: 18px;
            text-align: center;
            color: var(--muted);
        }

        .dna-card {
            position: relative;
            display: grid;
            grid-template-columns: 1fr;
            gap: 22px;
            padding: 28px 32px;
            border: 1px solid transparent;
            border-radius: var(--radius);
            background:
                linear-gradient(145deg, #171a20, #0f1116) padding-box,
                linear-gradient(135deg, rgba(255, 194, 75, .35), rgba(255, 255, 255, .06) 40%, rgba(239, 61, 69, .28) 70%, rgba(255, 194, 75, .2)) border-box;
            background-size: 100% 100%, 220% 220%;
            animation: borderLuxe 16s ease-in-out infinite alternate;
            box-shadow: 0 20px 50px rgba(0, 0, 0, .28);
        }
        .chip {
            padding: 8px 12px;
            border: 1px solid #ffc24b44;
            border-radius: 999px;
            background: #ffc24b0d;
            color: #ffe0a0;
            font-size: .88rem;
            transition: border-color .25s ease, background .25s ease, transform .2s ease;
        }
        .chip:hover {
            border-color: #ffc24b88;
            background: #ffc24b18;
            transform: translateY(-1px);
        }
        .dna-detail { display: grid; gap: 22px; }
        .dna-detail h3 {
            margin: 0 0 10px;
            color: var(--muted);
            font-size: .75rem;
            letter-spacing: .13em;
            text-transform: uppercase;
        }
        .chips { display: flex; flex-wrap: wrap; gap: 8px; }
        .signals { display: grid; gap: 8px; margin: 0; padding: 0; list-style: none; }
        .signals li {
            padding-left: 16px;
            border-left: 2px solid var(--red);
            color: #d5d5d8;
            font-size: .91rem;
        }
        .accuracy {
            margin: 0;
            padding: 12px 14px;
            border-radius: 12px;
            background: #ffffff08;
            color: #ddd;
            font-size: .88rem;
        }

        .media-block { margin-top: 22px; }
        .media-label {
            margin: 0 0 12px;
            color: var(--muted);
            font-size: .78rem;
            font-weight: 700;
            letter-spacing: .14em;
            text-transform: uppercase;
        }
        .library-grid {
            display: grid;
            grid-template-columns: repeat(6, minmax(0, 1fr));
            gap: 14px;
        }
        .library-poster { border-radius: 12px; }
        .library-card h3 { font-size: .88rem; margin-top: 9px; }

        .reveal {
            opacity: 0;
            transform: translateY(14px);
            animation: rise .55s ease forwards;
            animation-delay: var(--d, 0ms);
        }

        footer {
            margin-top: 60px;
            padding-top: 24px;
            border-top: 1px solid var(--line);
            display: flex;
            justify-content: space-between;
            color: var(--muted);
            font-size: .85rem;
        }

        @keyframes heroIn {
            from { opacity: 0; transform: translateY(18px); }
            to { opacity: 1; transform: none; }
        }
        @keyframes heroDrift {
            0% { transform: scale(1.08) translate3d(0, 0, 0); }
            50% { transform: scale(1.16) translate3d(-2.5%, -1.5%, 0); }
            100% { transform: scale(1.12) translate3d(2%, 1%, 0); }
        }
        @keyframes orbGold {
            from { transform: translate3d(0, 0, 0) scale(1); opacity: .7; }
            to { transform: translate3d(16%, 10%, 0) scale(1.15); opacity: 1; }
        }
        @keyframes orbCrimson {
            from { transform: translate3d(0, 6%, 0) scale(1.02); opacity: .65; }
            to { transform: translate3d(-18%, -8%, 0) scale(1.18); opacity: 1; }
        }
        @keyframes orbWarm {
            from { transform: translate3d(-6%, 0, 0) scale(1); opacity: .6; }
            to { transform: translate3d(12%, -10%, 0) scale(1.12); opacity: .9; }
        }
        @keyframes ribbonSweep {
            0% { transform: translate3d(-10%, 3%, 0) rotate(0deg); opacity: .3; }
            50% { transform: translate3d(6%, -4%, 0) rotate(1.5deg); opacity: .6; }
            100% { transform: translate3d(12%, 2%, 0) rotate(-1deg); opacity: .35; }
        }
        @keyframes goldSheen {
            0%, 100% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
        }
        @keyframes borderLuxe {
            from { background-position: 0% 0%, 0% 40%; }
            to { background-position: 0% 0%, 100% 60%; }
        }
        @keyframes rise {
            to { opacity: 1; transform: none; }
        }
        @keyframes rankPop {
            from { opacity: 0; transform: scale(.7); }
            to { opacity: 1; transform: none; }
        }

        @media (max-width: 760px) {
            .hero-stage {
                /* Height tracks viewport width so the portrait poster fills the phone edge-to-edge. */
                min-height: min(85vh, calc(100vw * 1.4));
            }
            .hero-bg {
                background-image: var(--hero-mobile, var(--hero-desktop));
                background-position: center top;
                background-size: cover;
                transform: none;
                animation: none;
            }
            .hero-ambience .ambience-orb {
                filter: blur(44px);
            }
            .hero-bg::after {
                background:
                    linear-gradient(180deg, rgba(8, 9, 12, .38) 0%, rgba(8, 9, 12, .2) 40%, rgba(8, 9, 12, .86) 72%, var(--bg) 100%),
                    linear-gradient(90deg, rgba(8, 9, 12, .28) 0%, transparent 42%, rgba(8, 9, 12, .28) 100%);
            }
            .hero-topbar, .hero-content, .shell { width: min(100% - 24px, 1180px); }
            .hero-topbar { padding-top: 16px; }
            /* Mobilde CTA hero'nun altında — kredi üst köşeye alınır, çakışmaz. */
            .hero-credit {
                right: 12px;
                bottom: auto;
                top: 68px;
                font-size: .74rem;
                padding: 7px 11px;
            }
            .hero-content { padding: 28px 0 48px; margin-top: auto; }
            .hero-archetype { max-width: none; }
            .rank-track { grid-auto-columns: 136px; margin-right: -12px; }
            .library-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
            section.shelf, section.rank-shelf, section.dna-panel { margin-top: 42px; }
            footer { flex-direction: column; gap: 6px; }
        }

        @media (prefers-reduced-motion: reduce) {
            html { scroll-behavior: auto; }
            *, *::before, *::after {
                animation: none !important;
                transition: none !important;
            }
            .reveal { opacity: 1; transform: none; }
            .hero-bg { transform: none; }
            .hero-ambience { opacity: .45; }
            .ambience-orb, .ambience-ribbon { filter: none; }
            .eyebrow {
                color: var(--gold);
                background: none;
                -webkit-background-clip: unset;
                background-clip: unset;
            }
        }
    </style>
</head>
<body>
<header class="hero-stage">
    <div class="hero-bg"<?php
        if ($heroDesktop || $heroMobile) {
            $vars = [];
            if ($heroDesktop) {
                $safeDesktop = $cssSafeHeroUrl($heroDesktop);
                if ($safeDesktop !== '') {
                    // Single-quoted CSS url() so it survives inside style="..."
                    $vars[] = "--hero-desktop:url('" . $safeDesktop . "')";
                }
            }
            if ($heroMobile) {
                $safeMobile = $cssSafeHeroUrl($heroMobile);
                if ($safeMobile !== '') {
                    $vars[] = "--hero-mobile:url('" . $safeMobile . "')";
                }
            }
            if ($vars !== []) {
                echo ' style="' . implode(';', $vars) . '"';
            }
        }
    ?> aria-hidden="true"></div>
    <div class="hero-ambience" aria-hidden="true" data-ambience="v3">
        <span class="ambience-orb ambience-orb--gold"></span>
        <span class="ambience-orb ambience-orb--crimson"></span>
        <span class="ambience-orb ambience-orb--warm"></span>
        <span class="ambience-ribbon"></span>
    </div>
    <nav class="hero-topbar" aria-label="Cinema+">
        <a class="brand" href="https://cinema.mbkm.com.tr">cinema<b>+</b></a>
        <a class="lang" href="?lang=<?= ($lang ?? 'tr') === 'tr' ? 'en' : 'tr' ?>" hreflang="<?= ($lang ?? 'tr') === 'tr' ? 'en' : 'tr' ?>"><?= ($lang ?? 'tr') === 'tr' ? 'EN' : 'TR' ?></a>
    </nav>
    <div class="hero-content">
        <?php if (!empty($dna)): ?>
            <p class="eyebrow"><?= $e($t['dna_kicker']) ?></p>
            <h1 class="hero-archetype"><?= $e($dna['archetype']) ?></h1>
            <p class="hero-essence"><?= $e($dna['essence']) ?></p>
        <?php else: ?>
            <p class="eyebrow"><?= $e($t['brand_kicker']) ?></p>
            <h1 class="hero-archetype"><?= $displayName ?></h1>
            <p class="hero-essence"><?= $e($t['hero_desc']) ?></p>
        <?php endif; ?>
        <div class="hero-meta">
            <div class="hero-identity">
                <?php if (!empty($dna)): ?>
                    <p class="hero-name"><?= $displayName ?></p>
                <?php endif; ?>
                <p class="hero-handle">@<?= $userHandle ?></p>
            </div>
            <a class="cta" href="https://cinema.mbkm.com.tr" rel="noopener"><?= $e(sprintf($t['cta'], html_entity_decode($displayName))) ?></a>
        </div>
    </div>
    <?php if ($heroCreditTitle !== ''): ?>
        <?php $heroCreditLabel = '🎬 ' . $heroCreditTitle . ($heroCreditYear !== '' ? ' (' . $heroCreditYear . ')' : ''); ?>
        <?php if ($heroCreditHref !== ''): ?>
            <a class="hero-credit" href="<?= $e($heroCreditHref) ?>" target="_blank" rel="noopener"><?= $e($heroCreditLabel) ?></a>
        <?php else: ?>
            <span class="hero-credit"><?= $e($heroCreditLabel) ?></span>
        <?php endif; ?>
    <?php endif; ?>
</header>

<main class="shell">
    <?php if (!empty($dna) && (!empty($dna['themes']) || !empty($dna['genres']) || !empty($dna['signals']) || !empty($dna['accuracy']))): ?>
    <section class="dna-panel" aria-label="<?= $e($t['dna_kicker']) ?>">
        <div class="dna-card">
            <div class="dna-detail">
                <?php if (!empty($dna['themes'])): ?>
                    <div>
                        <h3><?= $e($t['dna_themes']) ?></h3>
                        <div class="chips"><?php foreach ($dna['themes'] as $theme): ?><span class="chip"><?= $e($theme) ?></span><?php endforeach; ?></div>
                    </div>
                <?php endif; ?>
                <?php if (!empty($dna['genres'])): ?>
                    <div>
                        <h3><?= $e($t['dna_genres']) ?></h3>
                        <div class="chips"><?php foreach ($dna['genres'] as $genre): ?><span class="chip"><?= $e($genre) ?></span><?php endforeach; ?></div>
                    </div>
                <?php endif; ?>
                <?php if (!empty($dna['signals'])): ?>
                    <ul class="signals"><?php foreach (array_slice($dna['signals'], 0, 3) as $signal): ?><li><?= $e($signal) ?></li><?php endforeach; ?></ul>
                <?php endif; ?>
                <?php if (!empty($dna['accuracy'])): ?>
                    <p class="accuracy"><?= $e($dna['accuracy']) ?></p>
                <?php endif; ?>
            </div>
        </div>
    </section>
    <?php endif; ?>

    <?php if ($topMovies): ?>
    <section class="rank-shelf" aria-labelledby="top-movies-heading">
        <div class="section-head">
            <p class="eyebrow">TOP 20</p>
            <h2 id="top-movies-heading"><?= $e($t['top_movies']) ?></h2>
            <p><?= $e($t['top_desc']) ?></p>
        </div>
        <div class="rank-track"><?php $renderTopCards($topMovies); ?></div>
    </section>
    <?php endif; ?>

    <?php if ($topShows): ?>
    <section class="rank-shelf" aria-labelledby="top-shows-heading">
        <div class="section-head">
            <p class="eyebrow">TOP 20</p>
            <h2 id="top-shows-heading"><?= $e($t['top_shows']) ?></h2>
            <?php if (!$topMovies): ?><p><?= $e($t['top_desc']) ?></p><?php endif; ?>
        </div>
        <div class="rank-track"><?php $renderTopCards($topShows); ?></div>
    </section>
    <?php endif; ?>

    <?php
    $renderSplitShelf('great-heading', $t['sec_great'], $greatMovies, $greatShows, $t['empty_great_movies'], $t['empty_great_shows']);
    $renderSplitShelf('good-heading', $t['sec_good'], $goodMovies, $goodShows, $t['empty_good_movies'], $t['empty_good_shows']);
    $renderSplitShelf('watch-heading', $t['sec_watchlist'], $watchMovies, $watchShows, $t['empty_watch_movies'], $t['empty_watch_shows']);
    ?>

    <footer>
        <span>cinema+</span>
        <span>@<?= $userHandle ?> · <?= date('Y') ?></span>
    </footer>
</main>
</body>
</html>
