<?php
declare(strict_types=1);

$e = static fn(mixed $value): string => htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
$posterUrl = static fn(?string $path, string $size = 'w500'): string =>
    $path ? 'https://image.tmdb.org/t/p/' . $size . $path : '';
$initial = mb_strtoupper(mb_substr(html_entity_decode($displayName), 0, 1, 'UTF-8'), 'UTF-8');
$ogTitle = sprintf($t['og_title'], html_entity_decode($displayName));
$ogDesc = sprintf($t['og_desc'], html_entity_decode($userHandle));
if (!empty($dna)) {
    $ogTitle = sprintf($t['og_dna_title'], html_entity_decode($displayName), $dna['archetype']);
    $ogDesc = sprintf($t['og_dna_desc'], $dna['archetype'], $dna['essence']);
}
$ogCandidate = $topMovies[0] ?? $topShows[0] ?? $ratings[0] ?? $goodRatings[0] ?? $watchlist[0] ?? null;
$ogImage = $posterUrl($ogCandidate['poster_path'] ?? null);

$renderTopCards = static function (array $items) use ($e, $posterUrl, $t): void {
    foreach ($items as $item) {
        $title = trim((string) ($item['title'] ?? '')) ?: (($item['is_tv'] ?? false) ? $t['tv'] : $t['movie']);
        $poster = $posterUrl($item['poster_path'] ?? null, 'w342');
        $year = !empty($item['release_date']) ? substr((string) $item['release_date'], 0, 4) : '';
        ?>
        <article class="rank-card">
            <span class="rank-number" aria-label="#<?= $e($item['rank']) ?>">#<?= $e($item['rank']) ?></span>
            <div class="rank-poster">
                <?php if ($poster): ?>
                    <img src="<?= $e($poster) ?>" alt="<?= $e($title) ?>" loading="lazy" width="228" height="342">
                <?php else: ?>
                    <span class="poster-fallback" aria-hidden="true">C+</span>
                <?php endif; ?>
            </div>
            <h3><?= $e($title) ?></h3>
            <?php if ($year): ?><p><?= $e($year) ?></p><?php endif; ?>
        </article>
        <?php
    }
};

$renderLibrary = static function (array $items, string $empty) use ($e, $posterUrl, $t): void {
    if (!$items) {
        echo '<p class="empty">' . $e($empty) . '</p>';
        return;
    }
    echo '<div class="library-grid">';
    foreach ($items as $item) {
        $title = trim((string) ($item['title'] ?? '')) ?: (($item['is_tv'] ?? false) ? $t['tv'] : $t['movie']);
        $poster = $posterUrl($item['poster_path'] ?? null, 'w342');
        $year = !empty($item['release_date']) ? substr((string) $item['release_date'], 0, 4) : '';
        echo '<article class="library-card"><div class="library-poster">';
        if ($poster) {
            echo '<img src="' . $e($poster) . '" alt="' . $e($title) . '" loading="lazy" width="228" height="342">';
        } else {
            echo '<span class="poster-fallback" aria-hidden="true">C+</span>';
        }
        echo '</div><div><h3>' . $e($title) . '</h3><p>' . $e($year) . '</p></div></article>';
    }
    echo '</div>';
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
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root{--bg:#08090c;--panel:#111319;--panel2:#171a21;--ink:#f7f5ef;--muted:#9b9da6;--gold:#ffc24b;--red:#ef3d45;--line:rgba(255,255,255,.1);--radius:24px}
        *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--ink);font-family:Outfit,system-ui,sans-serif;line-height:1.5;overflow-x:hidden}button,a{font:inherit}img{display:block;width:100%;height:100%;object-fit:cover}.shell{width:min(1180px,calc(100% - 40px));margin:auto;padding:28px 0 80px}.topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:22px}.brand{font-size:1.35rem;font-weight:800;letter-spacing:-.04em}.brand b{color:var(--red)}.lang{color:var(--muted);font-size:.85rem;text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:10px 14px}.lang:hover{color:var(--ink);border-color:#ffffff55}
        .hero{position:relative;overflow:hidden;display:grid;grid-template-columns:auto 1fr minmax(260px,350px);gap:22px;align-items:center;padding:30px;border:1px solid var(--line);border-radius:var(--radius);background:radial-gradient(circle at 90% 0,rgba(239,61,69,.22),transparent 36%),linear-gradient(135deg,#17191f,#0e1015)}.avatar{display:grid;place-items:center;width:88px;height:88px;border-radius:28px;background:linear-gradient(145deg,var(--red),#8e1520);font-size:2.2rem;font-weight:800;box-shadow:0 12px 30px #0008}.eyebrow{margin:0 0 6px;color:var(--gold);font-size:.72rem;font-weight:700;letter-spacing:.16em}.hero h1{margin:0;font-size:clamp(2rem,5vw,3.5rem);line-height:1;letter-spacing:-.055em}.handle{margin:6px 0 0;color:var(--muted)}.hero-copy{max-width:350px;color:#d0d0d4;margin:0}.hero .cta{grid-column:3;justify-self:start}.cta{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:0 18px;border-radius:14px;background:var(--ink);color:#08090c;text-decoration:none;font-weight:700}.cta:hover{background:var(--gold)}
        section{margin-top:56px}.section-head{display:flex;align-items:end;justify-content:space-between;gap:20px;margin-bottom:20px}.section-head h2{margin:3px 0 0;font-size:clamp(1.7rem,4vw,2.6rem);line-height:1.05;letter-spacing:-.045em}.section-head p{margin:0;color:var(--muted)}.tabs{display:flex;padding:4px;border:1px solid var(--line);border-radius:14px;background:var(--panel)}.tab{min-height:42px;padding:0 16px;border:0;border-radius:10px;background:transparent;color:var(--muted);cursor:pointer;font-weight:600}.tab[aria-selected=true]{background:var(--ink);color:#090a0d}.tab:focus-visible,.cta:focus-visible,.lang:focus-visible,summary:focus-visible{outline:3px solid var(--gold);outline-offset:3px}
        .rank-track{display:grid;grid-auto-flow:column;grid-auto-columns:158px;gap:16px;overflow-x:auto;padding:4px 4px 18px;scroll-snap-type:x proximity;scrollbar-color:#444 transparent}.rank-panel[hidden]{display:none}.rank-card{position:relative;scroll-snap-align:start;min-width:0}.rank-poster{aspect-ratio:2/3;overflow:hidden;border-radius:16px;background:var(--panel2);border:1px solid var(--line)}.rank-card:first-child .rank-poster{box-shadow:0 0 0 2px var(--gold),0 20px 50px #000}.rank-number{position:absolute;z-index:2;top:-8px;left:-7px;display:grid;place-items:center;min-width:38px;height:38px;padding:0 7px;border-radius:12px;background:var(--gold);color:#15100a;font-size:.9rem;font-weight:800;box-shadow:0 7px 20px #0009}.rank-card h3{margin:11px 0 0;font-size:.96rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.rank-card p,.library-card p{margin:2px 0 0;color:var(--muted);font-size:.82rem}.poster-fallback{display:grid;place-items:center;width:100%;height:100%;color:#5a5c65;font-weight:800;font-size:1.5rem;background:linear-gradient(145deg,#20232b,#111319)}.empty{padding:40px;border:1px dashed var(--line);border-radius:18px;text-align:center;color:var(--muted)}
        .dna-card{display:grid;grid-template-columns:minmax(260px,.85fr) 1.15fr;gap:32px;padding:32px;border:1px solid var(--line);border-radius:var(--radius);background:linear-gradient(145deg,#171a20,#0f1116)}.identity{display:grid;grid-template-columns:64px 1fr;gap:16px;align-items:start}.dna-emoji{display:grid;place-items:center;width:64px;height:64px;border-radius:20px;background:#ffffff0b;font-size:2rem}.identity h2{margin:0;font-size:clamp(1.6rem,4vw,2.35rem);line-height:1.05;letter-spacing:-.04em}.identity .essence{grid-column:1/-1;margin:4px 0 0;color:#cbccd1;font-size:1.03rem}.dna-detail{display:grid;gap:22px}.dna-detail h3{margin:0 0 10px;color:var(--muted);font-size:.75rem;letter-spacing:.13em;text-transform:uppercase}.chips{display:flex;flex-wrap:wrap;gap:8px}.chip{padding:8px 12px;border:1px solid #ffc24b44;border-radius:999px;background:#ffc24b0d;color:#ffe0a0;font-size:.88rem}.signals{display:grid;gap:8px;margin:0;padding:0;list-style:none}.signals li{padding-left:16px;border-left:2px solid var(--red);color:#d5d5d8;font-size:.91rem}.accuracy{margin:0;padding:12px 14px;border-radius:12px;background:#ffffff08;color:#ddd;font-size:.88rem}
        .more>h2{font-size:clamp(1.7rem,4vw,2.5rem);letter-spacing:-.04em}.collection{border-top:1px solid var(--line)}.collection:last-child{border-bottom:1px solid var(--line)}summary{display:flex;align-items:center;justify-content:space-between;min-height:66px;cursor:pointer;font-size:1.08rem;font-weight:700;list-style:none}summary::-webkit-details-marker{display:none}summary:after{content:'+';color:var(--gold);font-size:1.5rem;font-weight:400}details[open] summary:after{content:'−'}.collection-body{padding:2px 0 26px}.library-grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:14px}.library-poster{aspect-ratio:2/3;border-radius:12px;overflow:hidden;background:var(--panel2)}.library-card h3{margin:9px 0 0;font-size:.88rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        footer{margin-top:60px;padding-top:24px;border-top:1px solid var(--line);display:flex;justify-content:space-between;color:var(--muted);font-size:.85rem}
        @media(max-width:760px){.shell{width:min(100% - 24px,1180px);padding-top:16px}.topbar{margin-bottom:12px}.hero{grid-template-columns:64px 1fr;padding:20px;gap:14px}.avatar{width:64px;height:64px;border-radius:20px;font-size:1.7rem}.hero-copy{grid-column:1/-1}.hero .cta{grid-column:1/-1}.section-head{align-items:start;flex-direction:column}.tabs{width:100%}.tab{flex:1}.rank-track{grid-auto-columns:136px;margin-right:-12px}.dna-card{grid-template-columns:1fr;padding:22px;gap:28px}.library-grid{grid-template-columns:repeat(3,minmax(0,1fr))}section{margin-top:42px}footer{flex-direction:column;gap:6px}}
        @media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{animation:none!important;transition:none!important}}
    </style>
</head>
<body>
<main class="shell">
    <nav class="topbar" aria-label="Cinema+">
        <span class="brand">cinema<b>+</b></span>
        <a class="lang" href="?lang=<?= ($lang ?? 'tr') === 'tr' ? 'en' : 'tr' ?>" hreflang="<?= ($lang ?? 'tr') === 'tr' ? 'en' : 'tr' ?>"><?= ($lang ?? 'tr') === 'tr' ? 'EN' : 'TR' ?></a>
    </nav>

    <header class="hero">
        <div class="avatar" aria-hidden="true"><?= $e($initial) ?></div>
        <div><p class="eyebrow"><?= $e($t['brand_kicker']) ?></p><h1><?= $displayName ?></h1><p class="handle">@<?= $userHandle ?></p></div>
        <p class="hero-copy"><?= $e($t['hero_desc']) ?></p>
        <a class="cta" href="https://cinema.mbkm.com.tr" rel="noopener"><?= $e(sprintf($t['cta'], html_entity_decode($displayName))) ?></a>
    </header>

    <section aria-labelledby="top-heading">
        <div class="section-head">
            <div><p class="eyebrow">TOP 20</p><h2 id="top-heading"><?= $e($t['top_title']) ?></h2><p><?= $e($t['top_desc']) ?></p></div>
            <div class="tabs" role="tablist" aria-label="<?= $e($t['top_title']) ?>">
                <button class="tab" id="movies-tab" role="tab" aria-selected="true" aria-controls="movies-panel"><?= $e($t['top_movies']) ?></button>
                <button class="tab" id="shows-tab" role="tab" aria-selected="false" aria-controls="shows-panel" tabindex="-1"><?= $e($t['top_shows']) ?></button>
            </div>
        </div>
        <div class="rank-panel" id="movies-panel" role="tabpanel" aria-labelledby="movies-tab">
            <?php if ($topMovies): ?><div class="rank-track"><?php $renderTopCards($topMovies); ?></div><?php else: ?><p class="empty"><?= $e($t['top_empty_movies']) ?></p><?php endif; ?>
        </div>
        <div class="rank-panel" id="shows-panel" role="tabpanel" aria-labelledby="shows-tab" hidden>
            <?php if ($topShows): ?><div class="rank-track"><?php $renderTopCards($topShows); ?></div><?php else: ?><p class="empty"><?= $e($t['top_empty_shows']) ?></p><?php endif; ?>
        </div>
    </section>

    <?php if ($dna): ?>
    <section aria-labelledby="dna-heading">
        <div class="dna-card">
            <div class="identity"><div class="dna-emoji" aria-hidden="true"><?= $e($dna['emoji']) ?></div><div><p class="eyebrow"><?= $e($t['dna_kicker']) ?></p><h2 id="dna-heading"><?= $e($dna['archetype']) ?></h2></div><p class="essence"><?= $e($dna['essence']) ?></p></div>
            <div class="dna-detail">
                <?php if (!empty($dna['themes'])): ?><div><h3><?= $e($t['dna_themes']) ?></h3><div class="chips"><?php foreach ($dna['themes'] as $theme): ?><span class="chip"><?= $e($theme) ?></span><?php endforeach; ?></div></div><?php endif; ?>
                <?php if (!empty($dna['genres'])): ?><div><h3><?= ($lang ?? 'tr') === 'tr' ? 'Baskın türler' : 'Dominant genres' ?></h3><div class="chips"><?php foreach ($dna['genres'] as $genre): ?><span class="chip"><?= $e($genre) ?></span><?php endforeach; ?></div></div><?php endif; ?>
                <?php if (!empty($dna['signals'])): ?><ul class="signals"><?php foreach (array_slice($dna['signals'], 0, 3) as $signal): ?><li><?= $e($signal) ?></li><?php endforeach; ?></ul><?php endif; ?>
                <?php if (!empty($dna['accuracy'])): ?><p class="accuracy"><?= $e($dna['accuracy']) ?></p><?php endif; ?>
            </div>
        </div>
    </section>
    <?php endif; ?>

    <section class="more" aria-labelledby="more-heading"><h2 id="more-heading"><?= $e($t['more_title']) ?></h2>
        <details class="collection" open><summary><?= $e(preg_replace('/^[^\p{L}\p{N}]+/u', '', $t['sec_great'])) ?></summary><div class="collection-body"><?php $renderLibrary($ratings, $t['empty_great']); ?></div></details>
        <details class="collection"><summary><?= $e(preg_replace('/^[^\p{L}\p{N}]+/u', '', $t['sec_good'])) ?></summary><div class="collection-body"><?php $renderLibrary($goodRatings, $t['empty_good']); ?></div></details>
        <details class="collection"><summary><?= $e(preg_replace('/^[^\p{L}\p{N}]+/u', '', $t['sec_watchlist'])) ?></summary><div class="collection-body"><?php $renderLibrary($watchlist, $t['empty_watchlist']); ?></div></details>
    </section>
    <footer><span>cinema+</span><span>@<?= $userHandle ?> · <?= date('Y') ?></span></footer>
</main>
<script>
(() => { const tabs=[...document.querySelectorAll('[role=tab]')]; tabs.forEach((tab,i)=>{ tab.addEventListener('click',()=>activate(tab)); tab.addEventListener('keydown',e=>{if(!['ArrowLeft','ArrowRight'].includes(e.key))return;e.preventDefault();const next=tabs[(i+(e.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length];activate(next);next.focus()}) }); function activate(active){tabs.forEach(tab=>{const on=tab===active;tab.setAttribute('aria-selected',String(on));tab.tabIndex=on?0:-1;document.getElementById(tab.getAttribute('aria-controls')).hidden=!on})} })();
</script>
</body>
</html>
