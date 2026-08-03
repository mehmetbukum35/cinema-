[CmdletBinding()]
param(
    [switch]$BuildAndroid,
    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$startedAt = Get-Date
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-PreflightStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Host "`n==> $Name" -ForegroundColor Cyan
    $stepStartedAt = Get-Date
    try {
        $global:LASTEXITCODE = 0
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw "Komut $LASTEXITCODE çıkış koduyla başarısız oldu."
        }
        $duration = [math]::Round(((Get-Date) - $stepStartedAt).TotalSeconds, 1)
        $results.Add([pscustomobject]@{
            Step = $Name
            Status = 'PASS'
            Seconds = $duration
        })
        Write-Host "PASS ($duration sn)" -ForegroundColor Green
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $stepStartedAt).TotalSeconds, 1)
        $results.Add([pscustomobject]@{
            Step = $Name
            Status = 'FAIL'
            Seconds = $duration
        })
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Assert-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' PATH üzerinde bulunamadı."
    }
}

function Assert-ReleaseSigning {
    $propertiesPath = Join-Path $repoRoot 'android\key.properties'
    if (-not (Test-Path -LiteralPath $propertiesPath -PathType Leaf)) {
        throw 'android/key.properties bulunamadı. İmzalı build için önce release anahtarını yapılandır.'
    }

    $properties = @{}
    foreach ($line in Get-Content -LiteralPath $propertiesPath) {
        if ($line -match '^\s*([^#!][^=]*)=(.*)$') {
            $properties[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    foreach ($required in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
        if (-not $properties.ContainsKey($required) -or
            [string]::IsNullOrWhiteSpace($properties[$required])) {
            throw "android/key.properties içinde '$required' eksik."
        }
    }

    $storePath = Join-Path (Join-Path $repoRoot 'android\app') $properties['storeFile']
    if (-not (Test-Path -LiteralPath $storePath -PathType Leaf)) {
        throw "Release keystore bulunamadı: $storePath"
    }
}

Push-Location $repoRoot
try {
    Invoke-PreflightStep 'Araçlar ve kritik dosyalar' {
        foreach ($command in @('git', 'dart', 'flutter', 'php', 'composer')) {
            Assert-CommandExists $command
        }
        foreach ($path in @(
            'pubspec.yaml',
            'backend\composer.json',
            'backend\migrations\027_cultural_preferences.sql',
            'backend\migrations\028_recommendation_events.sql'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path) -PathType Leaf)) {
                throw "Kritik dosya eksik: $path"
            }
        }
        $schema = Get-Content -Raw -LiteralPath (
            Join-Path $repoRoot 'backend\migrations\database.sql'
        )
        foreach ($fragment in @('cultural_preferences', 'recommendation_events')) {
            if (-not $schema.Contains($fragment)) {
                throw "Üretim şemasında '$fragment' bulunamadı."
            }
        }
    }

    Invoke-PreflightStep 'Git whitespace kontrolü' {
        & git diff --check
    }

    Invoke-PreflightStep 'Flutter bağımlılıkları' {
        & flutter pub get
    }

    Invoke-PreflightStep 'Dart biçim kontrolü' {
        & dart format --output=none --set-exit-if-changed .
    }

    Invoke-PreflightStep 'Flutter statik analiz' {
        & flutter analyze
    }

    Invoke-PreflightStep 'Flutter testleri' {
        & flutter test
    }

    Invoke-PreflightStep 'Composer doğrulama' {
        & composer validate --working-dir=backend --no-check-publish
    }

    Invoke-PreflightStep 'Backend testleri' {
        Push-Location (Join-Path $repoRoot 'backend')
        try {
            & composer test
        }
        finally {
            Pop-Location
        }
    }

    if ($BuildAndroid) {
        if ($BuildNumber -le 0) {
            throw '-BuildAndroid kullanıldığında pozitif bir -BuildNumber verilmelidir.'
        }
        Invoke-PreflightStep 'Android release imzalama önkoşulları' {
            Assert-ReleaseSigning
        }
        Invoke-PreflightStep 'İmzalı Android APK' {
            $previousSigningRequirement = $env:ANDROID_REQUIRE_RELEASE_SIGNING
            try {
                $env:ANDROID_REQUIRE_RELEASE_SIGNING = '1'
                & flutter build apk --release --build-number=$BuildNumber
            }
            finally {
                $env:ANDROID_REQUIRE_RELEASE_SIGNING = $previousSigningRequirement
            }
        }
        Invoke-PreflightStep 'İmzalı Android App Bundle' {
            $previousSigningRequirement = $env:ANDROID_REQUIRE_RELEASE_SIGNING
            try {
                $env:ANDROID_REQUIRE_RELEASE_SIGNING = '1'
                & flutter build appbundle --release --build-number=$BuildNumber
            }
            finally {
                $env:ANDROID_REQUIRE_RELEASE_SIGNING = $previousSigningRequirement
            }
        }
    }

    Write-Host "`n=== Yayın öncesi sonuç ===" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    $totalSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
    Write-Host "Tüm otomatik kontroller geçti ($totalSeconds sn)." -ForegroundColor Green
    Write-Warning 'Veritabanına bağlanılmadı. 027 ve 028 migration durumunu sunucuda manuel doğrula.'
}
finally {
    Pop-Location
}
