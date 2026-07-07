<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Uygulamayı İndir | Ne İzlesem</title>
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
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 40px 20px;
        }

        .container {
            max-width: 500px;
            width: 100%;
            text-align: center;
            padding: 40px 24px;
            background: linear-gradient(135deg, rgba(21, 29, 48, 0.6) 0%, rgba(11, 15, 25, 0.8) 100%);
            border-radius: 28px;
            border: 1px solid var(--border);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
            backdrop-filter: blur(12px);
        }

        .logo-wrap {
            font-size: 48px;
            margin-bottom: 20px;
            animation: pulse 2s infinite alternate;
        }

        h1 {
            font-size: 28px;
            font-weight: 800;
            letter-spacing: -0.5px;
            margin-bottom: 12px;
        }

        p {
            color: var(--dim);
            font-size: 15px;
            margin-bottom: 30px;
        }

        .download-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background-color: var(--red);
            color: white;
            text-decoration: none;
            font-weight: 700;
            padding: 16px 32px;
            border-radius: 14px;
            font-size: 16px;
            width: 100%;
            transition: transform 0.2s, box-shadow 0.2s;
            box-shadow: 0 10px 20px rgba(229, 9, 20, 0.3);
            margin-bottom: 16px;
            cursor: pointer;
        }

        .download-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 15px 25px rgba(229, 9, 20, 0.45);
        }

        .download-btn svg {
            margin-right: 10px;
            fill: currentColor;
            width: 20px;
            height: 20px;
        }

        .store-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background-color: transparent;
            color: var(--dim);
            text-decoration: none;
            font-weight: 600;
            padding: 14px 32px;
            border-radius: 14px;
            font-size: 14px;
            width: 100%;
            border: 1px solid var(--border);
            cursor: not-allowed;
            margin-bottom: 30px;
        }

        .store-btn svg {
            margin-right: 10px;
            fill: currentColor;
            width: 18px;
            height: 18px;
        }

        .instructions {
            text-align: left;
            background-color: rgba(255, 255, 255, 0.02);
            border-radius: 16px;
            padding: 20px;
            border: 1px solid var(--border);
        }

        .instructions-title {
            font-size: 14px;
            font-weight: 700;
            color: var(--gold);
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .instructions ol {
            padding-left: 20px;
            font-size: 13.5px;
            color: var(--dim);
        }

        .instructions li {
            margin-bottom: 8px;
        }

        .instructions li strong {
            color: var(--ink);
        }

        @keyframes pulse {
            from { transform: scale(1); }
            to { transform: scale(1.05); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo-wrap">🎬</div>
        <h1>Ne İzlesem?</h1>
        <p>Arkadaşlarınla ortak film ve dizilerini bulup karar felcinden kurtulmak için hemen uygulamayı indir!</p>

        <!-- Android APK Download -->
        <a href="https://cinema.mbkm.com.tr/app-release.apk" class="download-btn">
            <svg viewBox="0 0 24 24">
                <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/>
            </svg>
            Android (.APK) İndir
        </a>

        <!-- iOS Store Button (Disabled/Soon) -->
        <div class="store-btn">
            <svg viewBox="0 0 24 24">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 4.17c.66-.81 1.11-1.93.99-3.06-1 .04-2.22.67-2.94 1.51-.64.74-1.2 1.88-1.05 3 .1.01.21.02.32.02.89 0 2.02-.66 2.68-1.47z"/>
            </svg>
            App Store (Yakında)
        </div>

        <!-- Installation Guide -->
        <div class="instructions">
            <div class="instructions-title">Yükleme Kılavuzu</div>
            <ol>
                <li>Yukarıdaki <strong>Android (.APK) İndir</strong> butonuna basarak dosyayı indirin.</li>
                <li>İndirme tamamlandığında bildirimden veya dosya yöneticinizden dosyaya tıklayın.</li>
                <li>Eğer sistem güvenlik uyarısı verirse, <strong>Ayarlar</strong> seçeneğine tıklayıp <strong>"Bu kaynaktan izin ver"</strong> seçeneğini aktif edin.</li>
                <li>Geri dönerek <strong>Yükle</strong> butonuna basın ve uygulamanın tadını çıkarın!</li>
            </ol>
        </div>
    </div>
</body>
</html>
