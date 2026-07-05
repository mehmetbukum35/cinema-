<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars($title); ?> | Ne İzlesem</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;700&display=swap" rel="stylesheet">
    <style>
        body {
            background-color: #0B0F19;
            color: white;
            font-family: 'Outfit', sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            text-align: center;
            padding: 20px;
        }
        .card {
            background-color: #151D30;
            padding: 40px;
            border-radius: 20px;
            border: 1px solid rgba(255,255,255,0.08);
            max-width: 450px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        h1 {
            color: #FFB300;
            font-size: 24px;
            margin-bottom: 16px;
        }
        p {
            color: #94A3B8;
            font-size: 15px;
            line-height: 1.5;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1><?php echo htmlspecialchars($title); ?></h1>
        <p><?php echo htmlspecialchars($desc); ?></p>
    </div>
</body>
</html>
