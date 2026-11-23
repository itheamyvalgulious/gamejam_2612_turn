$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$godot = Join-Path $env:LOCALAPPDATA 'TurnGameJam\Godot-4.7.2\Godot_v4.7.2-stable_win64'
$xaml = Join-Path $root 'main\ui\loading\startup_window.xaml'
$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($xaml))
$status = $window.FindName('StatusText')
$detail = $window.FindName('ErrorDetail')
$track = $window.FindName('LoadingTrack')
$window.FindName('CloseButton').Add_Click({ $window.Close() })

$settings = Join-Path $env:APPDATA 'Godot\app_userdata\TURN\turn_options.cfg'
$windowed = (Test-Path -LiteralPath $settings) -and ($null -ne (Select-String -LiteralPath $settings -Pattern '^display\.fullscreen\s*=\s*false$'))
if (-not $windowed -and '--windowed' -notin $args) {
    $window.WindowState = [Windows.WindowState]::Maximized
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('TURN-startup-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$ready = Join-Path $work 'ready'
$gameLog = Join-Path $work 'game.log'
$quotedGameLog = '"' + $gameLog + '"'
$gameArgs = @('--path', 'main', '--log-file', $quotedGameLog) + $args
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(80)
$script:child = $null
$script:stage = 'prepare'
$script:failed = $false
$script:handedOff = $false

function Start-LoadingStep([string]$file, [string]$arguments) {
    $processOptions = @{
        FilePath = $file
        ArgumentList = $arguments
        WorkingDirectory = $root
        WindowStyle = 'Hidden'
        RedirectStandardOutput = Join-Path $work ($script:stage + '.log')
        RedirectStandardError = Join-Path $work ($script:stage + '.err')
        PassThru = $true
    }
    $script:child = Start-Process @processOptions
    # Keep the process handle so Windows PowerShell can read the exit code after it exits.
    $null = $script:child.Handle
}

function Show-StartupError([string]$message) {
    $timer.Stop()
    $script:failed = $true
    $errorLog = Join-Path $work 'startup.err'
    if (-not (Test-Path -LiteralPath $errorLog)) {
        Set-Content -LiteralPath $errorLog -Value $message -Encoding UTF8
    }
    $track.Visibility = [Windows.Visibility]::Hidden
    $status.Text = $message
    $detail.Text = '启动日志位于 ' + $work
    $detail.Visibility = [Windows.Visibility]::Visible
}

$window.Add_ContentRendered({
    try {
        if (-not (Test-Path -LiteralPath ($godot + '.exe')) -or -not (Test-Path -LiteralPath ($godot + '_console.exe'))) {
            Show-StartupError '找不到 Godot 4.7.2'
            return
        }
        $python = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonArgs = '-3 -X utf8 main\tools\prepare_game.py'
        if ($null -eq $python) {
            $python = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object Source -NotMatch '\\Microsoft\\WindowsApps\\' | Select-Object -First 1
            $pythonArgs = '-X utf8 main\tools\prepare_game.py'
        }
        if ($null -eq $python) {
            Show-StartupError '找不到 Python 3'
            return
        }
        Start-LoadingStep $python.Source $pythonArgs
        $timer.Start()
    } catch {
        Set-Content -LiteralPath (Join-Path $work 'startup.err') -Value $_.ToString() -Encoding UTF8
        Show-StartupError '无法准备游戏资源'
    }
})

$timer.Add_Tick({
    try {
        if ($script:stage -eq 'game') {
            if (Test-Path -LiteralPath $ready) {
                $script:handedOff = $true
                $window.Close()
            } elseif ($script:game.HasExited -or [DateTime]::UtcNow -ge $script:gameDeadline) {
                Show-StartupError '未能进入游戏主菜单'
            }
            return
        }

        if (-not $script:child.HasExited) { return }
        if ($script:child.ExitCode -ne 0) {
            $action = if ($script:stage -eq 'prepare') { '准备' } else { '导入' }
            Show-StartupError ('游戏资源' + $action + '失败')
            return
        }
        if ($script:stage -eq 'prepare') {
            $script:stage = 'import'
            $status.Text = '正在导入游戏资源'
            Start-LoadingStep ($godot + '_console.exe') '--headless --path main --editor --import'
            return
        }

        $script:stage = 'game'
        $status.Text = '正在进入主菜单'
        $env:TURN_STARTUP_READY_FILE = $ready
        try {
            $script:game = Start-Process -FilePath ($godot + '.exe') -ArgumentList $gameArgs -WorkingDirectory $root -PassThru
        } finally {
            Remove-Item Env:TURN_STARTUP_READY_FILE -ErrorAction SilentlyContinue
        }
        $script:gameDeadline = [DateTime]::UtcNow.AddSeconds(45)
    } catch {
        Set-Content -LiteralPath (Join-Path $work 'startup.err') -Value $_.ToString() -Encoding UTF8
        Show-StartupError 'TURN 启动失败'
    }
})

try {
    [void]$window.ShowDialog()
} finally {
    $timer.Stop()
}
if ($script:failed) { exit 1 }
if ($script:handedOff) {
    foreach ($name in @('prepare.log', 'prepare.err', 'import.log', 'import.err', 'ready', 'game.log')) {
        Remove-Item -LiteralPath (Join-Path $work $name) -ErrorAction SilentlyContinue
    }
    # The game may retain the log while it is running.
    try { [IO.Directory]::Delete($work) } catch [IO.IOException] {}
}
