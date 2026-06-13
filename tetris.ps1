# ==============================================================================
# tetris.ps1 - Game Tetris Interaktif untuk Terminal PowerShell
# ==============================================================================
# Desain oleh Antigravity (Google DeepMind Team)
# ==============================================================================

& {
    # Pastikan output menggunakan UTF-8 agar karakter blok Unicode terender dengan benar
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Cek ketersediaan sesi konsol interaktif
    try {
        $null = $Host.UI.RawUI.KeyAvailable
    }
    catch {
        Write-Host "[!] Error: Game ini memerlukan sesi konsol interaktif." -ForegroundColor Red
        Write-Host "Harap jalankan di host PowerShell standar (seperti Windows Terminal)." -ForegroundColor Yellow
        return
    }

    # Atur dimensi minimum jendela terminal jika didukung
    try {
        if ($Host.UI.RawUI.WindowSize.Width -lt 70) {
            $size = $Host.UI.RawUI.WindowSize
            $size.Width = 70
            $Host.UI.RawUI.WindowSize = $size
        }
        if ($Host.UI.RawUI.WindowSize.Height -lt 30) {
            $size = $Host.UI.RawUI.WindowSize
            $size.Height = 30
            $Host.UI.RawUI.WindowSize = $size
        }
    } catch {}

    # Konfigurasi Kode Warna ANSI (Warna 24-bit True Color)
    function Get-AnsiColor ($r, $g, $b) {
        return "$([char]27)[38;2;$r;$g;${b}m"
    }
    $Reset = "$([char]27)[0m"

    # Definisi Bentuk & Warna Tetromino Standar (7-Mino)
    $Shapes = @{
        'I' = @{
            Matrix = @(
                @(0, 0, 0, 0),
                @(1, 1, 1, 1),
                @(0, 0, 0, 0),
                @(0, 0, 0, 0)
            )
            Color = Get-AnsiColor 0 240 255     # Cyan
        }
        'O' = @{
            Matrix = @(
                @(1, 1),
                @(1, 1)
            )
            Color = Get-AnsiColor 255 230 0     # Yellow
        }
        'T' = @{
            Matrix = @(
                @(0, 1, 0),
                @(1, 1, 1),
                @(0, 0, 0)
            )
            Color = Get-AnsiColor 190 50 255    # Purple/Magenta
        }
        'S' = @{
            Matrix = @(
                @(0, 1, 1),
                @(1, 1, 0),
                @(0, 0, 0)
            )
            Color = Get-AnsiColor 0 230 70      # Green
        }
        'Z' = @{
            Matrix = @(
                @(1, 1, 0),
                @(0, 1, 1),
                @(0, 0, 0)
            )
            Color = Get-AnsiColor 255 50 50     # Red
        }
        'J' = @{
            Matrix = @(
                @(1, 0, 0),
                @(1, 1, 1),
                @(0, 0, 0)
            )
            Color = Get-AnsiColor 50 100 255    # Blue
        }
        'L' = @{
            Matrix = @(
                @(0, 0, 1),
                @(1, 1, 1),
                @(0, 0, 0)
            )
            Color = Get-AnsiColor 255 130 0     # Orange
        }
    }

    # Desain preview statis untuk sidebar (HOLD & NEXT)
    $Previews = @{
        'I' = @(
            "        ",
            "████████",
            "        ",
            "        "
        )
        'O' = @(
            "  ████  ",
            "  ████  ",
            "        ",
            "        "
        )
        'T' = @(
            "    ██  ",
            "  ██████",
            "        ",
            "        "
        )
        'J' = @(
            "  ██    ",
            "  ██████",
            "        ",
            "        "
        )
        'L' = @(
            "      ██",
            "  ██████",
            "        ",
            "        "
        )
        'S' = @(
            "    ████",
            "  ████  ",
            "        ",
            "        "
        )
        'Z' = @(
            "  ████  ",
            "    ████",
            "        ",
            "        "
        )
    }

    # Ukuran Papan Bermain (Standard Tetris)
    $BoardWidth = 10
    $BoardHeight = 20

    # Inisialisasi State Game
    $global:Board = [Object[]]::new($BoardHeight)
    for ($i = 0; $i -lt $BoardHeight; $i++) {
        $global:Board[$i] = [string[]]::new($BoardWidth)
        for ($j = 0; $j -lt $BoardWidth; $j++) {
            $global:Board[$i][$j] = ""
        }
    }

    $global:Score = 0
    $global:Level = 0
    $global:LinesCleared = 0
    $global:GameOver = $false
    $global:Paused = $false
    $global:HoldPiece = $null
    $global:CanHold = $true
    $global:NextPieceType = $null

    $global:currentPieceType = $null
    $global:currentMatrix = $null
    $global:currentColor = $null
    $global:currentX = 0
    $global:currentY = 0

    # Sistem Generator 7-Bag (Menjamin distribusi bidak yang adil)
    $global:Bag = [System.Collections.Generic.List[string]]::new()
    function Get-NextPiece {
        if ($global:Bag.Count -eq 0) {
            $shuffled = $Shapes.Keys | Get-Random -Count 7
            foreach ($k in $shuffled) {
                $global:Bag.Add($k)
            }
        }
        $type = $global:Bag[0]
        $global:Bag.RemoveAt(0)
        return $type
    }

    # Rotasi Matriks (Clockwise)
    function Rotate-Matrix ($matrix) {
        $n = $matrix.Count
        $newMatrix = [Object[]]::new($n)
        for ($i = 0; $i -lt $n; $i++) {
            $newMatrix[$i] = [int[]]::new($matrix[$i].Count)
        }
        for ($r = 0; $r -lt $n; $r++) {
            for ($c = 0; $c -lt $matrix[$r].Count; $c++) {
                $newMatrix[$c][$n - 1 - $r] = $matrix[$r][$c]
            }
        }
        return $newMatrix
    }

    # Cek Tabrakan (Collision Detection)
    function Test-Collision ($posX, $posY, $matrix) {
        $rows = $matrix.Count
        $cols = $matrix[0].Count
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                if ($matrix[$r][$c] -ne 0) {
                    $boardX = $posX + $c
                    $boardY = $posY + $r
                    
                    # Cek batas dinding kiri/kanan & lantai bawah
                    if ($boardX -lt 0 -or $boardX -ge $BoardWidth -or $boardY -ge $BoardHeight) {
                        return $true
                    }
                    # Cek tabrakan dengan balok yang sudah terkunci di papan
                    if ($boardY -ge 0) {
                        if ($global:Board[$boardY][$boardX] -ne "") {
                            return $true
                        }
                    }
                }
            }
        }
        return $false
    }

    # Memposisikan Bidak Baru di Atas Papan
    function Spawn-Piece ($type) {
        $global:currentPieceType = $type
        $global:currentMatrix = $Shapes[$type].Matrix
        $global:currentColor = $Shapes[$type].Color
        
        $matrixWidth = $global:currentMatrix[0].Count
        $global:currentX = [Math]::Floor(($BoardWidth - $matrixWidth) / 2)
        $global:currentY = 0
        
        # Game Over jika langsung menabrak balok lain saat spawn
        if (Test-Collision $global:currentX $global:currentY $global:currentMatrix) {
            $global:GameOver = $true
        }
    }

    # Spawn Siklus Utama Bidak
    function Spawn-NewPiece {
        $global:CanHold = $true
        if (-not $global:NextPieceType) {
            $global:NextPieceType = Get-NextPiece
        }
        $global:currentPieceType = $global:NextPieceType
        $global:NextPieceType = Get-NextPiece
        Spawn-Piece $global:currentPieceType
    }

    # Mengambil Baris Preview yang Sudah Diwarnai
    function Get-PreviewLine ($type, $lineIdx) {
        if (-not $type -or -not $Shapes.ContainsKey($type)) {
            return "        " # 8 spaces
        }
        $color = $Shapes[$type].Color
        $template = $Previews[$type][$lineIdx]
        return $template.Replace("██", "$color██$Reset")
    }

    # Membersihkan Baris Penuh (Line Clear)
    function Clear-Lines {
        $linesToClear = @()
        for ($y = 0; $y -lt $BoardHeight; $y++) {
            $full = $true
            for ($x = 0; $x -lt $BoardWidth; $x++) {
                if ($global:Board[$y][$x] -eq "") {
                    $full = $false
                    break
                }
            }
            if ($full) {
                $linesToClear += $y
            }
        }
        
        if ($linesToClear.Count -gt 0) {
            # Animasi Flash: Ubah warna baris yang dibersihkan menjadi putih sejenak
            $whiteColor = Get-AnsiColor 255 255 255
            for ($flash = 0; $flash -lt 2; $flash++) {
                foreach ($y in $linesToClear) {
                    for ($x = 0; $x -lt $BoardWidth; $x++) {
                        $global:Board[$y][$x] = $whiteColor
                    }
                }
                Render-Frame
                Start-Sleep -Milliseconds 60
            }
            
            # Geser baris ke bawah
            $newBoard = [Object[]]::new($BoardHeight)
            $newIdx = $BoardHeight - 1
            for ($y = $BoardHeight - 1; $y -ge 0; $y--) {
                if ($y -notin $linesToClear) {
                    $newBoard[$newIdx] = $global:Board[$y]
                    $newIdx--
                }
            }
            while ($newIdx -ge 0) {
                $newBoard[$newIdx] = [string[]]::new($BoardWidth)
                for ($x = 0; $x -lt $BoardWidth; $x++) {
                    $newBoard[$newIdx][$x] = ""
                }
                $newIdx--
            }
            $global:Board = $newBoard
            
            # Hitung Skor & Tingkat Level (Sistem Skor Klasik)
            $global:LinesCleared += $linesToClear.Count
            $scores = @(0, 100, 300, 500, 800)
            $base = $scores[$linesToClear.Count]
            if (-not $base) { $base = 800 }
            $global:Score += $base * ($global:Level + 1)
            
            $newLevel = [Math]::Floor($global:LinesCleared / 10)
            if ($newLevel -gt $global:Level) {
                $global:Level = $newLevel
                [Console]::Beep(880, 120) # Efek suara naik level
            }
            else {
                [Console]::Beep(440, 60)  # Efek suara membersihkan baris
            }
        }
    }

    # Mengunci Bidak Aktif ke Papan
    function Lock-Piece {
        $rows = $global:currentMatrix.Count
        $cols = $global:currentMatrix[0].Count
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                if ($global:currentMatrix[$r][$c] -ne 0) {
                    $boardX = $global:currentX + $c
                    $boardY = $global:currentY + $r
                    if ($boardY -ge 0 -and $boardY -lt $BoardHeight) {
                        $global:Board[$boardY][$boardX] = $global:currentColor
                    }
                }
            }
        }
        Clear-Lines
        Spawn-NewPiece
    }

    # Menghitung Interval Waktu Jatuh Berdasarkan Level (Semakin tinggi level semakin cepat)
    function Get-DropInterval {
        return [Math]::Max(100, 650 - ($global:Level * 60))
    }

    # Render Seluruh Tampilan Game (Double Buffering)
    function Render-Frame {
        $frame = [System.Collections.Generic.List[string]]::new()
        
        # ANSI Escape Code: Geser kursor ke (0,0) untuk menggambar tanpa kedip
        $frame.Add("$([char]27)[H")
        
        $uiColor = Get-AnsiColor 0 180 255 # Warna Frame Biru Neon
        
        # 1. Header ASCII Art Tetris yang Mewah
        $frame.Add("")
        $frame.Add("   $(Get-AnsiColor 0 240 255)██████╗  ██████╗  ██████╗ ██████╗  █████╗ ██████╗$Reset")
        $frame.Add("   $(Get-AnsiColor 0 200 255)╚══██╔══╝ ██╔════╝  ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝$Reset")
        $frame.Add("   $(Get-AnsiColor 100 150 255)   ██║    █████╗       ██║   ██████╔╝███████║╚█████╗ $Reset")
        $frame.Add("   $(Get-AnsiColor 180 100 255)   ██║    ██╔══╝       ██║   ██╔══██╗██╔══██║ ╚═══██╗$Reset")
        $frame.Add("   $(Get-AnsiColor 255 50 255)   ██║    ███████╗     ██║   ██║  ██║██║  ██║██████╔╝$Reset")
        $frame.Add("   $(Get-AnsiColor 255 0 255)   ╚═╝    ╚══════╝     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ $Reset")
        $frame.Add("                    $(Get-AnsiColor 128 128 128)[ P O W E R S H E L L ]$Reset")
        $frame.Add("")
        
        # 2. Desain Layout Atas
        $frame.Add("   $uiColor╔════════════╗   ╔════════════════════╗   ╔════════════╗$Reset")
        $frame.Add("   $uiColor║    HOLD    ║   ║   PAPAN BERMAIN    ║   ║    NEXT    ║$Reset")
        $frame.Add("   $uiColor╠════════════╣   ║                    ║   ╠════════════╣$Reset")
        
        # 3. Kloning Papan untuk Render + Tempel Bidak & Bayangan (Ghost Piece)
        $RenderBoard = [Object[]]::new($BoardHeight)
        for ($y = 0; $y -lt $BoardHeight; $y++) {
            $RenderBoard[$y] = [string[]]::new($BoardWidth)
            [Array]::Copy($global:Board[$y], $RenderBoard[$y], $BoardWidth)
        }
        
        $rows = $global:currentMatrix.Count
        $cols = $global:currentMatrix[0].Count
        
        # Hitung Posisi Bayangan (Ghost Piece) untuk Presisi Jatuh
        $ghostY = $global:currentY
        while (-not (Test-Collision $global:currentX ($ghostY + 1) $global:currentMatrix)) {
            $ghostY++
        }
        
        # Gambar Bayangan jika ada di bawah bidak aktif
        if ($ghostY -gt $global:currentY) {
            $ghostColor = Get-AnsiColor 65 65 65
            for ($r = 0; $r -lt $rows; $r++) {
                for ($c = 0; $c -lt $cols; $c++) {
                    if ($global:currentMatrix[$r][$c] -ne 0) {
                        $boardX = $global:currentX + $c
                        $boardY = $ghostY + $r
                        if ($boardY -ge 0 -and $boardY -lt $BoardHeight -and $boardX -ge 0 -and $boardX -lt $BoardWidth) {
                            if ($RenderBoard[$boardY][$boardX] -eq "") {
                                $RenderBoard[$boardY][$boardX] = "$ghostColor░░"
                            }
                        }
                    }
                }
            }
        }
        
        # Gambar Bidak Aktif
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                if ($global:currentMatrix[$r][$c] -ne 0) {
                    $boardX = $global:currentX + $c
                    $boardY = $global:currentY + $r
                    if ($boardY -ge 0 -and $boardY -lt $BoardHeight -and $boardX -ge 0 -and $boardX -lt $BoardWidth) {
                        $RenderBoard[$boardY][$boardX] = $global:currentColor
                    }
                }
            }
        }
        
        # 4. Rendering Papan Bermain baris demi baris berdampingan dengan Sidebar
        $emptyCell = "$(Get-AnsiColor 40 40 40)· $Reset"
        for ($y = 0; $y -lt $BoardHeight; $y++) {
            $line = "   $uiColor║$Reset"
            
            # Panel Kiri (HOLD Piece)
            if ($y -ge 0 -and $y -lt 4) {
                $pLine = Get-PreviewLine $global:HoldPiece $y
                $line += "  $pLine  $uiColor║$Reset"
            }
            else {
                $line += "            $uiColor║$Reset"
            }
            
            # Batas Tengah
            $line += "   $uiColor║$Reset"
            
            # Panel Tengah (Papan Tetris)
            if ($global:Paused -and ($y -eq 9 -or $y -eq 10)) {
                if ($y -eq 9) {
                    $line += "$(Get-AnsiColor 255 255 0)    GAME  PAUSED    $Reset"
                }
                else {
                    $line += "$(Get-AnsiColor 255 255 255) Tekan P utk lanjut  $Reset"
                }
            }
            elseif ($global:GameOver -and ($y -eq 9 -or $y -eq 10)) {
                if ($y -eq 9) {
                    $line += "$(Get-AnsiColor 255 50 50)    GAME  OVER!     $Reset"
                }
                else {
                    $scoreStr = $global:Score.ToString().PadLeft(6, '0')
                    $line += "$(Get-AnsiColor 255 255 255) SKOR: $scoreStr        $Reset"
                }
            }
            else {
                for ($x = 0; $x -lt $BoardWidth; $x++) {
                    $cell = $RenderBoard[$y][$x]
                    if ($cell -eq "") {
                        $line += $emptyCell
                    }
                    elseif ($cell.StartsWith($([char]27))) {
                        $line += "$cell$Reset"
                    }
                    else {
                        $line += "$cell██$Reset"
                    }
                }
            }
            
            # Batas Kanan
            $line += "$uiColor║$Reset   $uiColor║$Reset"
            
            # Panel Kanan (NEXT Piece & Statistik & Tombol)
            if ($y -ge 0 -and $y -lt 4) {
                $pLine = Get-PreviewLine $global:NextPieceType $y
                $line += "  $pLine  $uiColor║$Reset"
            }
            elseif ($y -eq 4) {
                $line += "            $uiColor║$Reset"
            }
            elseif ($y -eq 5) {
                $line += "════════════$uiColor║$Reset"
            }
            elseif ($y -eq 6) {
                $line += " SKOR:       $uiColor║$Reset"
            }
            elseif ($y -eq 7) {
                $scoreStr = $global:Score.ToString().PadLeft(6, '0')
                $line += "  $(Get-AnsiColor 255 255 0)$scoreStr$Reset     $uiColor║$Reset"
            }
            elseif ($y -eq 8) {
                $line += " LEVEL:      $uiColor║$Reset"
            }
            elseif ($y -eq 9) {
                $line += "  $(Get-AnsiColor 0 255 100)$($global:Level)$Reset          $uiColor║$Reset"
            }
            elseif ($y -eq 10) {
                $line += " BARIS:      $uiColor║$Reset"
            }
            elseif ($y -eq 11) {
                $line += "  $(Get-AnsiColor 255 100 255)$($global:LinesCleared)$Reset          $uiColor║$Reset"
            }
            elseif ($y -eq 12) {
                $line += "════════════$uiColor║$Reset"
            }
            elseif ($y -eq 13) {
                $line += " KONTROL:    $uiColor║$Reset"
            }
            elseif ($y -eq 14) {
                $line += " ←→ / AD:Kiri$uiColor║$Reset"
            }
            elseif ($y -eq 15) {
                $line += " ↑  / W :Putar$uiColor║$Reset"
            }
            elseif ($y -eq 16) {
                $line += " ↓  / S :Turun$uiColor║$Reset"
            }
            elseif ($y -eq 17) {
                $line += " Spasi  :Jatuh$uiColor║$Reset"
            }
            elseif ($y -eq 18) {
                $line += " C      :Hold $uiColor║$Reset"
            }
            elseif ($y -eq 19) {
                $line += " P:Pause Q:Out$uiColor║$Reset"
            }
            else {
                $line += "            $uiColor║$Reset"
            }
            
            $frame.Add($line)
        }
        
        # 5. Batas Bawah Layar
        $frame.Add("   $uiColor╚════════════╝   ╚════════════════════╝   ╚════════════╝$Reset")
        $frame.Add("")
        
        # Tulis buffer ke layar sekaligus
        [Console]::Write(($frame -join "`n"))
    }

    # Halaman Selamat Datang / Start Screen
    function Show-StartScreen {
        Clear-Host
        $titleColor = Get-AnsiColor 0 255 200
        $accentColor = Get-AnsiColor 255 0 255
        
        Write-Host ""
        Write-Host "   $titleColor██████╗  ██████╗  ██████╗ ██████╗  █████╗ ██████╗$Reset"
        Write-Host "   $titleColor╚══██╔══╝ ██╔════╝  ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝$Reset"
        Write-Host "   $titleColor   ██║    █████╗       ██║   ██████╔╝███████║╚█████╗ $Reset"
        Write-Host "   $titleColor   ██║    ██╔══╝       ██║   ██╔══██╗██╔══██║ ╚═══██╗$Reset"
        Write-Host "   $titleColor   ██║    ███████╗     ██║   ██║  ██║██║  ██║██████╔╝$Reset"
        Write-Host "   $titleColor   ╚═╝    ╚══════╝     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ $Reset"
        Write-Host "                    [ P O W E R S H E L L ]" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   +--------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "     Gunakan tombol keyboard berikut untuk bermain:" -ForegroundColor Gray
        Write-Host "     - Kiri / Kanan : Tombol panah $(Get-AnsiColor 255 255 0)← / →$Reset atau $(Get-AnsiColor 255 255 0)A / D$Reset"
        Write-Host "     - Rotasi Bidak : Tombol panah $(Get-AnsiColor 255 255 0)↑$Reset atau $(Get-AnsiColor 255 255 0)W$Reset"
        Write-Host "     - Soft Drop    : Tombol panah $(Get-AnsiColor 255 255 0)↓$Reset atau $(Get-AnsiColor 255 255 0)S$Reset"
        Write-Host "     - Hard Drop    : $(Get-AnsiColor 255 255 0)Spasi$Reset (Langsung jatuh & mengunci)"
        Write-Host "     - Simpan Bidak : $(Get-AnsiColor 255 255 0)C$Reset (Hold Piece untuk ditukar)"
        Write-Host "     - Jeda (Pause) : $(Get-AnsiColor 255 255 0)P$Reset"
        Write-Host "     - Keluar Game  : $(Get-AnsiColor 255 255 0)Q$Reset"
        Write-Host "   +--------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        
        $blink = $true
        while (-not $Host.UI.RawUI.KeyAvailable) {
            $msg = if ($blink) { "     >>> TEKAN [TOMBOL APAPUN] UNTUK MEMULAI <<<     " } else { "                                                     " }
            [Console]::Write("$([char]27)[18;0H$accentColor$msg$Reset")
            $blink = -not $blink
            Start-Sleep -Milliseconds 450
        }
        
        # Konsumsi tombol input awal agar tidak terbawa ke dalam game
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
    }

    # ==============================================================================
    # BLOK UTAMA EKSEKUSI GAME (TRY/FINALLY UNTUK KEAMANAN TERMINAL)
    # ==============================================================================
    
    # Sembunyikan kursor terminal agar terlihat rapi
    [Console]::Write("$([char]27)[?25l")
    
    try {
        Show-StartScreen
        
        # Ambil bidak awal
        Spawn-NewPiece
        Render-Frame
        
        # Pengukuran Waktu untuk Loop Utama
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastDrop = 0
        
        # Loop Utama Permainan
        while (-not $global:GameOver) {
            $currentTick = $stopwatch.ElapsedMilliseconds
            $interval = Get-DropInterval
            
            # Siklus Gravitasi (Bidak Jatuh Otomatis)
            if ($currentTick - $lastDrop -ge $interval) {
                if (-not $global:Paused) {
                    if (-not (Test-Collision $global:currentX ($global:currentY + 1) $global:currentMatrix)) {
                        $global:currentY++
                        Render-Frame
                    }
                    else {
                        Lock-Piece
                        Render-Frame
                    }
                }
                $lastDrop = $currentTick
            }
            
            # Tangani Tombol Input Non-Blocking
            $inputChanged = $false
            while ($Host.UI.RawUI.KeyAvailable) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                if ($key.KeyDown) {
                    $code = $key.VirtualKeyCode
                    $char = $key.Character
                    
                    if ($code -eq 37 -or $char -eq 'a' -or $char -eq 'A') {
                        # Gerak Kiri
                        if (-not $global:Paused -and -not (Test-Collision ($global:currentX - 1) $global:currentY $global:currentMatrix)) {
                            $global:currentX--
                            $inputChanged = $true
                        }
                    }
                    elseif ($code -eq 39 -or $char -eq 'd' -or $char -eq 'D') {
                        # Gerak Kanan
                        if (-not $global:Paused -and -not (Test-Collision ($global:currentX + 1) $global:currentY $global:currentMatrix)) {
                            $global:currentX++
                            $inputChanged = $true
                        }
                    }
                    elseif ($code -eq 38 -or $char -eq 'w' -or $char -eq 'W') {
                        # Rotasi (Dengan Wall Kick sederhana)
                        if (-not $global:Paused) {
                            $rotated = Rotate-Matrix $global:currentMatrix
                            $kicks = @(0, -1, 1, -2, 2)
                            foreach ($kick in $kicks) {
                                if (-not (Test-Collision ($global:currentX + $kick) $global:currentY $rotated)) {
                                    $global:currentX += $kick
                                    $global:currentMatrix = $rotated
                                    $inputChanged = $true
                                    break
                                }
                            }
                        }
                    }
                    elseif ($code -eq 40 -or $char -eq 's' -or $char -eq 'S') {
                        # Soft Drop (Turun lebih cepat)
                        if (-not $global:Paused -and -not (Test-Collision $global:currentX ($global:currentY + 1) $global:currentMatrix)) {
                            $global:currentY++
                            $global:Score += 1 # Tambah 1 poin per langkah soft drop
                            $inputChanged = $true
                        }
                    }
                    elseif ($code -eq 32) {
                        # Spacebar (Hard Drop - Jatuh Instan)
                        if (-not $global:Paused) {
                            $dropCount = 0
                            while (-not (Test-Collision $global:currentX ($global:currentY + 1) $global:currentMatrix)) {
                                $global:currentY++
                                $dropCount++
                            }
                            $global:Score += ($dropCount * 2) # Tambah 2 poin per langkah hard drop
                            Lock-Piece
                            $inputChanged = $true
                        }
                    }
                    elseif ($char -eq 'c' -or $char -eq 'C') {
                        # C (Hold Piece - Simpan/Tukar Bidak)
                        if (-not $global:Paused -and $global:CanHold) {
                            if ($global:HoldPiece -eq $null) {
                                $global:HoldPiece = $global:currentPieceType
                                Spawn-NewPiece
                            }
                            else {
                                $temp = $global:HoldPiece
                                $global:HoldPiece = $global:currentPieceType
                                Spawn-Piece $temp
                            }
                            $global:CanHold = $false
                            $inputChanged = $true
                        }
                    }
                    elseif ($char -eq 'p' -or $char -eq 'P') {
                        # P (Pause/Jeda)
                        $global:Paused = -not $global:Paused
                        $inputChanged = $true
                    }
                    elseif ($char -eq 'q' -or $char -eq 'Q') {
                        # Q (Quit/Keluar)
                        $global:GameOver = $true
                        $inputChanged = $true
                    }
                }
            }
            
            # Jika ada perubahan posisi/state oleh input, render ulang frame
            if ($inputChanged) {
                Render-Frame
            }
            
            # Sleep singkat untuk menghemat CPU dan menjaga FPS di ~25 FPS
            Start-Sleep -Milliseconds 40
        }
        
        # Render frame terakhir untuk menunjukkan state Game Over di papan
        Render-Frame
        Start-Sleep -Seconds 2
    }
    finally {
        # Kembalikan kursor terminal agar terlihat seperti semula
        [Console]::Write("$([char]27)[?25h")
        [Console]::Write("$Reset")
        Clear-Host
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "           TERIMA KASIH TELAH BERMAIN!    " -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host " Skor Akhir Anda : $($global:Score)" -ForegroundColor Yellow
        Write-Host " Level Terakhir   : $($global:Level)" -ForegroundColor Yellow
        Write-Host " Baris Bersih     : $($global:LinesCleared)" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
    }
}
