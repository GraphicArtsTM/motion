#Requires -Version 5.1
<#
  Запуск реферального бота на Windows без Docker.
  Всё хранится в папке runtime\ (или C:\TaxoparkBot\runtime, если в пути к боту есть кириллица):
    uv\       — установщик Python (uv)
    python\   — портативный Python 3.12
    venv\     — виртуальное окружение с библиотеками бота
    pgsql\    — портативный PostgreSQL 16
    pgdata\   — данные базы
    logs\     — журналы
  В систему ничего не устанавливается (кроме Visual C++ Runtime, если его нет — Windows спросит разрешение).
#>
param(
    [ValidateSet('start', 'setup', 'stop', 'logs', 'backup', 'status', 'autostart')]
    [string]$Action = 'start',
    [switch]$Silent
)

# Не 'Stop': в Windows PowerShell 5.1 строка в stderr у внешней программы (psql, initdb) при 'Stop' обрывает
# скрипт. Коды возврата внешних программ проверяются явно, критичные командлеты вызываются с -ErrorAction Stop.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = 'Реферальный бот таксопарка'

# ── версии и адреса загрузки ────────────────────────────────────────────────
$UvVersion = '0.5.11'
$PyVersion = '3.12'
$PgVersion = '16.4-1'
$PgPort = 54329
$WebPort = 8000
$UvUrl = "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-x86_64-pc-windows-msvc.zip"
$PgUrl = if ($env:PG_ZIP_URL) { $env:PG_ZIP_URL } else { "https://get.enterprisedb.com/postgresql/postgresql-$PgVersion-windows-x64-binaries.zip" }
$VcUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'

# ── пути ─────────────────────────────────────────────────────────────────────
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
# PostgreSQL на Windows плохо переносит кириллицу в пути к данным — тогда держим runtime на системном диске
if ($Root -match '[^\x20-\x7E]') { $RT = Join-Path $env:SystemDrive 'TaxoparkBot\runtime' } else { $RT = Join-Path $Root 'runtime' }
$UvDir = Join-Path $RT 'uv'
$Uv = Join-Path $UvDir 'uv.exe'
$Venv = Join-Path $RT 'venv'
$Py = Join-Path $Venv 'Scripts\python.exe'
$PyW = Join-Path $Venv 'Scripts\pythonw.exe'
$Pg = Join-Path $RT 'pgsql'
$PgBin = Join-Path $Pg 'bin'
$PgData = Join-Path $RT 'pgdata'
$Logs = Join-Path $RT 'logs'
$PidFile = Join-Path $RT 'bot.pid'
$PgPassFile = Join-Path $RT 'pg.secret'
$EnvFile = Join-Path $Root '.env'
New-Item -ItemType Directory -Force $RT, $Logs -ErrorAction Stop | Out-Null

# ── вывод ────────────────────────────────────────────────────────────────────
function Say([string]$Text, [string]$Color = 'Gray') { Write-Host "  $Text" -ForegroundColor $Color }
function Step([string]$Text) { Write-Host ''; Write-Host "  » $Text" -ForegroundColor Cyan }
function Pause-IfNeeded { if (-not $Silent) { Write-Host ''; [void](Read-Host '  Нажмите Enter, чтобы закрыть окно') } }
function Fail([string]$Text) {
    Write-Host ''
    Write-Host "  [ОШИБКА] $Text" -ForegroundColor Red
    Pause-IfNeeded
    exit 1
}
function Banner {
    Write-Host ''
    Write-Host '  ============================================' -ForegroundColor Yellow
    Write-Host '      Реферальный бот таксопарка' -ForegroundColor Yellow
    Write-Host '  ============================================' -ForegroundColor Yellow
}

# ── утилиты ──────────────────────────────────────────────────────────────────
function Download([string]$Url, [string]$OutFile, [string]$Title) {
    Say "Скачиваю $Title..."
    $part = "$OutFile.part"
    for ($i = 1; $i -le 3; $i++) {
        try {
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                & curl.exe -L --fail --retry 2 --progress-bar -o $part $Url
                if ($LASTEXITCODE -ne 0) { throw "curl завершился с кодом $LASTEXITCODE" }
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing -ErrorAction Stop
            }
            Move-Item -Force $part $OutFile -ErrorAction Stop
            return
        } catch {
            Say "Попытка $i не удалась: $($_.Exception.Message)" 'Yellow'
            Start-Sleep -Seconds 3
        }
    }
    Fail "Не удалось скачать $Title. Проверьте интернет и запустите снова."
}

function Extract-Zip([string]$Zip, [string]$Dest, [string[]]$Only = @()) {
    New-Item -ItemType Directory -Force $Dest -ErrorAction Stop | Out-Null
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        & tar.exe -xf $Zip -C $Dest @Only   # встроенный в Windows 10/11 tar распаковывает zip в разы быстрее
        if ($LASTEXITCODE -eq 0) { return }
    }
    Expand-Archive -Force -Path $Zip -DestinationPath $Dest -ErrorAction Stop
}

function Read-EnvFile {
    $values = @{}
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content $EnvFile -Encoding UTF8) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $v = $Matches[2].Trim()
                if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
                $values[$Matches[1]] = $v
            }
        }
    }
    return $values
}

function Is-Configured { $e = Read-EnvFile; return [bool]$e['BOT_TOKEN'] }

function Test-Url([string]$Url) {
    try { return ((Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop).StatusCode -eq 200) } catch { return $false }
}

# ── Python ───────────────────────────────────────────────────────────────────
function Ensure-Uv {
    if (Test-Path $Uv) { return }
    Step 'Скачиваю установщик Python (uv, ≈15 МБ)...'
    $zip = Join-Path $RT 'uv.zip'
    $tmp = Join-Path $RT 'uv-tmp'
    Download $UvUrl $zip 'uv'
    Extract-Zip $zip $tmp
    $exe = Get-ChildItem $tmp -Recurse -Filter 'uv.exe' | Select-Object -First 1
    if (-not $exe) { Fail 'В архиве uv не найден uv.exe' }
    New-Item -ItemType Directory -Force $UvDir | Out-Null
    Copy-Item $exe.FullName $Uv -ErrorAction Stop
    Remove-Item -Recurse -Force $tmp, $zip
}

function Ensure-Venv {
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $RT 'python'
    $env:UV_CACHE_DIR = Join-Path $RT 'uv-cache'
    if (-not (Test-Path $Py)) {
        Step "Готовлю Python $PyVersion и виртуальное окружение (первый раз 1–3 минуты)..."
        & $Uv venv --python $PyVersion --python-preference only-managed $Venv
        if ($LASTEXITCODE -ne 0) { Fail 'Не удалось создать виртуальное окружение Python.' }
    }
    $req = Join-Path $Root 'requirements.txt'
    $stamp = Join-Path $Venv '.requirements.sha256'
    $hash = (Get-FileHash $req -Algorithm SHA256).Hash
    if (-not (Test-Path $stamp) -or (Get-Content $stamp) -ne $hash) {
        Step 'Устанавливаю библиотеки бота (первый раз 1–3 минуты)...'
        & $Uv pip install --python $Py -r $req
        if ($LASTEXITCODE -ne 0) { Fail 'Не удалось установить библиотеки. Проверьте интернет и запустите снова.' }
        Set-Content $stamp $hash
    }
}

# ── PostgreSQL ───────────────────────────────────────────────────────────────
function Ensure-PgBinaries {
    if (Test-Path (Join-Path $PgBin 'pg_ctl.exe')) { return }
    Step "Скачиваю PostgreSQL $PgVersion (≈300 МБ, только в первый раз)..."
    $zip = Join-Path $RT 'pgsql.zip'
    Download $PgUrl $zip 'PostgreSQL'
    Say 'Распаковываю (1–3 минуты)...'
    $vcDlls = @('pgsql/pgAdmin 4/python/vcruntime140.dll', 'pgsql/pgAdmin 4/python/vcruntime140_1.dll')
    Extract-Zip $zip $RT (@('pgsql/bin', 'pgsql/lib', 'pgsql/share') + $vcDlls)
    Remove-Item -Force $zip
    # библиотеки Visual C++ из комплекта pgAdmin — чтобы не ставить VC++ Runtime с правами администратора
    foreach ($dll in $vcDlls) {
        $src = Join-Path $RT ($dll -replace '/', '\')
        $dst = Join-Path $PgBin (Split-Path $src -Leaf)
        if ((Test-Path $src) -and -not (Test-Path $dst)) { Copy-Item $src $dst }
    }
    foreach ($extra in 'pgAdmin 4', 'StackBuilder', 'symbols', 'doc', 'include') {
        $p = Join-Path $Pg $extra
        if (Test-Path $p) { Remove-Item -Recurse -Force $p }
    }
    if (-not (Test-Path (Join-Path $PgBin 'pg_ctl.exe'))) { Fail 'Архив PostgreSQL распакован неправильно.' }
}

function Ensure-VcRuntime {
    & (Join-Path $PgBin 'postgres.exe') -V *> $null
    if ($LASTEXITCODE -eq 0) { return }
    Step 'Нужен компонент Microsoft Visual C++ Runtime — устанавливаю (Windows попросит разрешение)...'
    $exe = Join-Path $RT 'vc_redist.x64.exe'
    Download $VcUrl $exe 'Visual C++ Runtime'
    Start-Process $exe -ArgumentList '/install', '/quiet', '/norestart' -Verb RunAs -Wait | Out-Null
    & (Join-Path $PgBin 'postgres.exe') -V *> $null
    if ($LASTEXITCODE -ne 0) { Fail "PostgreSQL не запускается. Установите вручную: $VcUrl и запустите снова." }
}

function Init-PgCluster([string]$Password) {
    if (Test-Path (Join-Path $PgData 'PG_VERSION')) { return }
    Step 'Создаю базу данных...'
    $pw = Join-Path $RT 'pwfile.tmp'
    [IO.File]::WriteAllText($pw, $Password)
    & (Join-Path $PgBin 'initdb.exe') -D $PgData -U referral "--pwfile=$pw" -E UTF8 --no-locale -A scram-sha-256 *> (Join-Path $Logs 'initdb.log')
    $code = $LASTEXITCODE
    Remove-Item -Force $pw
    if ($code -ne 0) { Fail "Не удалось создать базу данных. Журнал: $Logs\initdb.log" }
    Add-Content (Join-Path $PgData 'postgresql.conf') "`r`nlisten_addresses = '127.0.0.1'`r`nport = $PgPort`r`n"
    Set-Content $PgPassFile $Password
}

function Test-PgRunning {
    if (-not (Test-Path (Join-Path $PgData 'PG_VERSION'))) { return $false }
    & (Join-Path $PgBin 'pg_ctl.exe') status -D $PgData *> $null
    return ($LASTEXITCODE -eq 0)
}

function Start-Pg {
    if (Test-PgRunning) { return }
    Say 'Запускаю базу данных...'
    $pgArgs = @('start', '-D', "`"$PgData`"", '-l', "`"$Logs\postgres.log`"", '-w', '-t', '90')
    $p = Start-Process -FilePath (Join-Path $PgBin 'pg_ctl.exe') -ArgumentList $pgArgs -WindowStyle Hidden -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "База данных не запустилась. Журнал: $Logs\postgres.log" }
}

function Stop-Pg {
    if (-not (Test-PgRunning)) { return }
    $pgArgs = @('stop', '-D', "`"$PgData`"", '-m', 'fast', '-w')
    Start-Process -FilePath (Join-Path $PgBin 'pg_ctl.exe') -ArgumentList $pgArgs -WindowStyle Hidden -Wait | Out-Null
}

function Ensure-Database([string]$Password) {
    $env:PGPASSWORD = $Password
    try {
        $exists = & (Join-Path $PgBin 'psql.exe') -h 127.0.0.1 -p $PgPort -U referral -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='referral'" 2> $null
        if ("$exists".Trim() -ne '1') {
            & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $PgPort -U referral referral
            if ($LASTEXITCODE -ne 0) { Fail 'Не удалось создать базу referral. Если меняли пароль в .env — верните прежний (runtime\pg.secret).' }
        }
    } finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

# ── процесс бота ─────────────────────────────────────────────────────────────
function Get-BotProcess {
    if (-not (Test-Path $PidFile)) { return $null }
    $raw = "$(Get-Content $PidFile)".Trim()
    if ($raw -notmatch '^\d+$') { return $null }
    $id = [int]$raw
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -like 'python*') { return $p }
    return $null
}

function Stop-BotProcess {
    $p = Get-BotProcess
    if ($p) { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 1 }
    Remove-Item -Force $PidFile -ErrorAction SilentlyContinue
}

function Set-PythonEnv {
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PATH = "$PgBin;$env:PATH"   # pg_dump для ежедневной резервной копии
}

# ── действия ─────────────────────────────────────────────────────────────────
function Run-Setup {
    Ensure-Uv
    Ensure-Venv
    if (-not (Test-Path $EnvFile) -and (Test-Path $PgPassFile)) {
        # база уже создана с паролем — сохраняем его, чтобы мастер не сгенерировал новый
        [IO.File]::WriteAllText($EnvFile, "POSTGRES_PASSWORD=$((Get-Content $PgPassFile).Trim())`n")
    }
    Step 'Открываю мастер настройки в браузере: http://localhost:8765'
    Say 'Заполните шаги и нажмите «Сохранить и запустить». Передумали — просто закройте это окно.'
    Set-PythonEnv
    $env:LOCAL_MODE = '1'
    $env:WORKSPACE = $Root
    $env:SETUP_HOST = '127.0.0.1'
    $env:LOCAL_PG_PORT = "$PgPort"
    $p = Start-Process -FilePath $Py -ArgumentList '-m', 'src.setup_wizard' -WorkingDirectory $Root -NoNewWindow -PassThru
    for ($i = 0; $i -lt 30 -and -not (Test-Url 'http://127.0.0.1:8765/'); $i++) { Start-Sleep -Seconds 1 }
    Start-Process 'http://localhost:8765'
    $p.WaitForExit()
    if (-not (Is-Configured)) { Fail 'Настройка не была сохранена. Запустите start.bat ещё раз.' }
    Say 'Настройки сохранены.' 'Green'
}

function Start-Bot {
    Banner
    if (-not (Is-Configured)) {
        Say 'Первый запуск — сначала настройка.'
        Run-Setup
    }
    Ensure-Uv
    Ensure-Venv
    Ensure-PgBinaries
    Ensure-VcRuntime
    $envValues = Read-EnvFile
    $password = $envValues['POSTGRES_PASSWORD']
    if (-not $password) { Fail 'В .env нет POSTGRES_PASSWORD — запустите setup.bat.' }
    Init-PgCluster $password
    Start-Pg
    Ensure-Database $password

    if (Get-BotProcess) { Say 'Бот уже работал — перезапускаю с актуальными настройками...'; Stop-BotProcess }
    Step 'Запускаю бота...'
    foreach ($f in 'bot.log', 'bot-errors.log') {
        $path = Join-Path $Logs $f
        if (Test-Path $path) { Move-Item -Force $path "$path.prev" }
    }
    Set-PythonEnv
    Remove-Item Env:LOCAL_MODE -ErrorAction SilentlyContinue
    $runner = if (Test-Path $PyW) { $PyW } else { $Py }   # pythonw — без окна консоли
    $p = Start-Process -FilePath $runner -ArgumentList '-m', 'src.local' -WorkingDirectory $Root -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $Logs 'bot.log') -RedirectStandardError (Join-Path $Logs 'bot-errors.log') `
        -PassThru -ErrorAction Stop
    Set-Content $PidFile $p.Id

    Say 'Жду готовности (первый запуск — до минуты)...'
    $ready = $false
    for ($i = 0; $i -lt 90; $i++) {
        if (Test-Url "http://127.0.0.1:$WebPort/health") { $ready = $true; break }
        if ($p.HasExited) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        Write-Host ''
        Say 'Последние строки журнала ошибок:' 'Yellow'
        if (Test-Path (Join-Path $Logs 'bot-errors.log')) { Get-Content (Join-Path $Logs 'bot-errors.log') -Tail 15 -Encoding UTF8 | ForEach-Object { Say $_ 'Yellow' } }
        Fail 'Бот не запустился. Полный журнал: logs.bat'
    }
    $envValues = Read-EnvFile
    Write-Host ''
    Say 'ГОТОВО! Бот работает.' 'Green'
    if ($envValues['BOT_USERNAME']) { Say "Бот в Telegram:  https://t.me/$($envValues['BOT_USERNAME'])" 'Green' }
    Say "Состояние:       http://localhost:$WebPort/" 'Green'
    Write-Host ''
    Say 'Окно можно закрыть — бот продолжит работать в фоне, пока включён компьютер.'
    Say 'Остановить: stop.bat   Журнал: logs.bat   Настройки: setup.bat   Автозапуск: autostart.bat'
    if (-not $Silent) { Start-Process "http://localhost:$WebPort/" }
    Pause-IfNeeded
}

function Stop-All {
    Banner
    Say 'Останавливаю бота...'
    Stop-BotProcess
    if (Test-Path (Join-Path $PgBin 'pg_ctl.exe')) { Say 'Останавливаю базу данных...'; Stop-Pg }
    Say 'Бот остановлен. Данные сохранены — следующий start.bat продолжит работу.' 'Green'
    Pause-IfNeeded
}

function Show-Logs {
    $log = Join-Path $Logs 'bot.log'
    $err = Join-Path $Logs 'bot-errors.log'
    if (Test-Path $err) {
        $tail = Get-Content $err -Tail 20 -Encoding UTF8
        if ($tail) { Say '── Последние ошибки ──' 'Yellow'; $tail | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }
    }
    if (-not (Test-Path $log)) { Fail 'Журнала пока нет — бот ещё не запускался.' }
    Say "── Журнал бота ($log), новые строки появляются сами. Закрыть — Ctrl+C ──" 'Cyan'
    Get-Content $log -Tail 100 -Wait -Encoding UTF8
}

function Backup-Db {
    Banner
    $envValues = Read-EnvFile
    if (-not $envValues['POSTGRES_PASSWORD']) { Fail 'Бот ещё не настроен.' }
    Start-Pg
    $dir = Join-Path $Root 'backups'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $file = Join-Path $dir ("referral-{0}.dump" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
    Say "Создаю резервную копию: $file"
    $env:PGPASSWORD = $envValues['POSTGRES_PASSWORD']
    & (Join-Path $PgBin 'pg_dump.exe') -h 127.0.0.1 -p $PgPort -U referral -Fc -f $file referral
    $code = $LASTEXITCODE
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    if ($code -ne 0) { Fail 'Резервная копия не создана.' }
    Say 'Готово. Храните копию вне этого компьютера (флешка, облако).' 'Green'
    Pause-IfNeeded
}

function Show-Status {
    Banner
    $bot = Get-BotProcess
    Say ("Бот:            " + $(if ($bot) { "работает (PID $($bot.Id))" } else { 'остановлен' }))
    Say ("База данных:    " + $(if (Test-PgRunning) { 'работает' } else { 'остановлена' }))
    Say ("Веб-панель:     " + $(if (Test-Url "http://127.0.0.1:$WebPort/health") { "http://localhost:$WebPort/" } else { 'не отвечает' }))
    Say "Папка данных:   $RT"
    Pause-IfNeeded
}

function Toggle-Autostart {
    Banner
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Реферальный бот таксопарка.lnk'
    if (Test-Path $lnk) {
        Remove-Item -Force $lnk
        Say 'Автозапуск ВЫКЛЮЧЕН.' 'Yellow'
    } else {
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $Root 'start.bat'
        $s.Arguments = 'silent'
        $s.WorkingDirectory = $Root
        $s.WindowStyle = 7
        $s.Save()
        Say 'Автозапуск ВКЛЮЧЁН: бот будет запускаться сам при входе в Windows.' 'Green'
        Say 'Повторный запуск autostart.bat выключит автозапуск.'
    }
    Pause-IfNeeded
}

try {
    switch ($Action) {
        'start' { Start-Bot }
        'setup' { Banner; Run-Setup; Start-Bot }
        'stop' { Stop-All }
        'logs' { Show-Logs }
        'backup' { Backup-Db }
        'status' { Show-Status }
        'autostart' { Toggle-Autostart }
    }
} catch {
    Fail $_.Exception.Message
}
