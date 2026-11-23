#requires -Version 5.1
<#
    AutoTelas - IniciarTelas.ps1
    Executado no login (via IniciarTelas.bat / atalho na pasta Inicializar).

    1. Espera ESPERA_SEGUNDOS (padrão 20) para rede e Windows carregarem.
    2. Abre o SAIPOS (SAIPOS_ATALHO do config.txt) e garante a janela
       maximizada na TELA PRINCIPAL (monitor VGA).
    3. Se SEGUNDA_TELA estiver preenchido e o arquivo existir, abre-o na
       SEGUNDA TELA (monitor DisplayPort):
         - PDF / imagem / página web / endereço https://  -> Chrome em tela cheia (--kiosk)
         - outros tipos -> programa padrão + janela movida via SetWindowPos
    4. Grava tudo em log.txt (mesma pasta).

    Parâmetros:
      -SemEspera   pula a espera inicial (usado nos testes)
      -Config      caminho alternativo do config.txt
#>
param(
    [switch]$SemEspera,
    [string]$Config
)

$ErrorActionPreference = 'Continue'
$Pasta   = $PSScriptRoot
if (-not $Config) { $Config = Join-Path $Pasta 'config.txt' }
$LogPath = Join-Path $Pasta 'log.txt'

# ----------------------------------------------------------------- log
function Escrever-Log([string]$Mensagem) {
    $linha = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mensagem
    try { Add-Content -LiteralPath $LogPath -Value $linha -Encoding UTF8 } catch { }
    Write-Host $linha
}

try {
    if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 1MB)) {
        Move-Item -LiteralPath $LogPath -Destination (Join-Path $Pasta 'log_anterior.txt') -Force
    }
} catch { }

# ------------------------------------------------- uma execução por vez
$mutex = New-Object System.Threading.Mutex($false, 'Local\AutoTelas_IniciarTelas')
if (-not $mutex.WaitOne(0)) {
    Escrever-Log 'Outra execução do AutoTelas já está em andamento. Saindo.'
    exit
}

# ------------------------------------------------------- API do Windows
if (-not ('AutoTelas.Win32' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace AutoTelas
{
    public class Janela
    {
        public IntPtr Handle;
        public string Titulo;
        public string Classe;
        public uint Pid;
    }

    public static class Win32
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int cx, int cy, bool repaint);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);

        public static void TornarDpiAware()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        public static string Titulo(IntPtr h)
        {
            int n = GetWindowTextLength(h);
            if (n <= 0) return "";
            StringBuilder sb = new StringBuilder(n + 1);
            GetWindowText(h, sb, sb.Capacity);
            return sb.ToString();
        }

        // Janelas "de aplicativo": visíveis, sem dono, com título e não ocultas pelo DWM.
        public static List<Janela> Listar()
        {
            List<Janela> lista = new List<Janela>();
            EnumWindows(delegate (IntPtr h, IntPtr p)
            {
                if (!IsWindowVisible(h)) return true;
                if (GetWindow(h, 4) != IntPtr.Zero) return true; // GW_OWNER
                string t = Titulo(h);
                if (t.Length == 0) return true;
                int cloaked = 0;
                try { DwmGetWindowAttribute(h, 14, out cloaked, 4); } catch { }
                if (cloaked != 0) return true;
                StringBuilder c = new StringBuilder(256);
                GetClassName(h, c, c.Capacity);
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                Janela j = new Janela();
                j.Handle = h; j.Titulo = t; j.Classe = c.ToString(); j.Pid = pid;
                lista.Add(j);
                return true;
            }, IntPtr.Zero);
            return lista;
        }
    }
}
'@
}

[AutoTelas.Win32]::TornarDpiAware()
Add-Type -AssemblyName System.Windows.Forms

# ------------------------------------------------------------- config
function Ler-Config([string]$Caminho) {
    $cfg = @{}
    if (Test-Path -LiteralPath $Caminho) {
        foreach ($l in (Get-Content -LiteralPath $Caminho -Encoding UTF8)) {
            $t = $l.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $i = $t.IndexOf('=')
            if ($i -lt 1) { continue }
            $chave = $t.Substring(0, $i).Trim().ToUpperInvariant()
            $valor = $t.Substring($i + 1).Trim().Trim('"').Trim()
            $cfg[$chave] = $valor
        }
    }
    return $cfg
}

function Valor-Config($Cfg, [string]$Chave, [string]$Padrao) {
    if ($Cfg.ContainsKey($Chave) -and $Cfg[$Chave] -ne '') { return $Cfg[$Chave] }
    return $Padrao
}

Escrever-Log '================ AutoTelas iniciado ================'
if (-not (Test-Path -LiteralPath $Config)) {
    Escrever-Log "AVISO: config.txt não encontrado em $Config"
}
$cfg = Ler-Config $Config

$espera = 20
[void][int]::TryParse((Valor-Config $cfg 'ESPERA_SEGUNDOS' '20'), [ref]$espera)
if ($SemEspera) {
    Escrever-Log 'Modo teste: sem espera inicial.'
} else {
    Escrever-Log "Aguardando $espera segundos para o Windows e a rede carregarem..."
    Start-Sleep -Seconds $espera
}

# Lê o config de novo (pode ter sido editado durante a espera)
$cfg = Ler-Config $Config

# ------------------------------------------------------------ monitores
$telas     = [System.Windows.Forms.Screen]::AllScreens
$principal = $telas | Where-Object { $_.Primary } | Select-Object -First 1
$segunda   = $telas | Where-Object { -not $_.Primary } | Sort-Object { $_.Bounds.X } | Select-Object -First 1

foreach ($t in $telas) {
    $b = $t.Bounds
    $tipo = 'secundária'
    if ($t.Primary) { $tipo = 'PRINCIPAL' }
    Escrever-Log ("Monitor {0}: {1}x{2} na posição ({3},{4}) - {5}" -f $t.DeviceName, $b.Width, $b.Height, $b.X, $b.Y, $tipo)
}
if (-not $segunda) {
    Escrever-Log 'AVISO: só 1 monitor detectado. A segunda tela será ignorada nesta execução.'
}

# ----------------------------------------------------------- utilidades
$cacheProc = @{}
function Nome-Processo([uint32]$ProcId) {
    if ($cacheProc.ContainsKey($ProcId)) { return $cacheProc[$ProcId] }
    $nome = ''
    try { $nome = (Get-Process -Id $ProcId -ErrorAction Stop).ProcessName.ToLowerInvariant() } catch { }
    $cacheProc[$ProcId] = $nome
    return $nome
}

function Achar-Navegador {
    $candidatos = @()
    foreach ($exe in @('chrome.exe', 'msedge.exe')) {
        foreach ($raiz in @('HKLM:', 'HKCU:')) {
            try {
                $p = (Get-ItemProperty -LiteralPath "$raiz\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction Stop).'(default)'
                if ($p) { $candidatos += $p.Trim('"') }
            } catch { }
        }
        if ($exe -eq 'chrome.exe') {
            $candidatos += "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
            $candidatos += "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            $candidatos += "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        } else {
            $candidatos += "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
            $candidatos += "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
        }
    }
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Iniciar-Processo([hashtable]$Parametros, [string]$Descricao) {
    for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
        try {
            Start-Process @Parametros -ErrorAction Stop
            Escrever-Log "Iniciado: $Descricao"
            return $true
        } catch {
            Escrever-Log "Falha ao iniciar $Descricao (tentativa $tentativa/3): $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

function Novo-Alvo([string]$Nome, [string]$RegexTitulo, [string[]]$Processos, $Tela, [bool]$TelaCheia) {
    return [pscustomobject]@{
        Nome        = $Nome
        RegexTitulo = $RegexTitulo
        Processos   = $Processos   # nomes sem .exe, '*' = qualquer janela nova
        Tela        = $Tela
        TelaCheia   = $TelaCheia
        Handle      = [IntPtr]::Zero
        AchadaEm    = $null
        Movimentos  = 0
    }
}

function Posicao-Correta($Alvo) {
    $r = New-Object AutoTelas.Win32+RECT
    if (-not [AutoTelas.Win32]::GetWindowRect($Alvo.Handle, [ref]$r)) { return $false }
    $cx = [int](($r.Left + $r.Right) / 2)
    $cy = [int](($r.Top + $r.Bottom) / 2)
    $b  = $Alvo.Tela.Bounds
    $dentro = ($cx -ge $b.Left -and $cx -lt $b.Right -and $cy -ge $b.Top -and $cy -lt $b.Bottom)
    if (-not $dentro) { return $false }
    if ($Alvo.TelaCheia) { return $true }
    return [AutoTelas.Win32]::IsZoomed($Alvo.Handle)
}

function Mover-Janela($Alvo) {
    $h = $Alvo.Handle
    $SWP_NOZORDER = 0x0004; $SWP_SHOWWINDOW = 0x0040
    if ([AutoTelas.Win32]::IsIconic($h) -or [AutoTelas.Win32]::IsZoomed($h)) {
        [void][AutoTelas.Win32]::ShowWindow($h, 9)   # SW_RESTORE
        Start-Sleep -Milliseconds 300
    }
    if ($Alvo.TelaCheia) {
        $a = $Alvo.Tela.Bounds
        [void][AutoTelas.Win32]::SetWindowPos($h, [IntPtr]::Zero, $a.X, $a.Y, $a.Width, $a.Height, ($SWP_NOZORDER -bor $SWP_SHOWWINDOW))
    } else {
        $a = $Alvo.Tela.WorkingArea
        # coloca a janela (menor) dentro do monitor certo e depois maximiza nele
        if (-not [AutoTelas.Win32]::SetWindowPos($h, [IntPtr]::Zero, $a.X + 40, $a.Y + 40, [Math]::Max(400, $a.Width - 80), [Math]::Max(300, $a.Height - 80), ($SWP_NOZORDER -bor $SWP_SHOWWINDOW))) {
            [void][AutoTelas.Win32]::MoveWindow($h, $a.X + 40, $a.Y + 40, [Math]::Max(400, $a.Width - 80), [Math]::Max(300, $a.Height - 80), $true)
        }
        Start-Sleep -Milliseconds 200
        [void][AutoTelas.Win32]::ShowWindow($h, 3)   # SW_MAXIMIZE
    }
}

$ignorar = @('powershell', 'powershell_ise', 'pwsh', 'conhost', 'cmd', 'windowsterminal', 'explorer', 'shellexperiencehost', 'searchui', 'searchapp', 'textinputhost', 'applicationframehost')

# Janelas que já existiam antes de abrirmos qualquer coisa
$antes = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
foreach ($j in [AutoTelas.Win32]::Listar()) { [void]$antes.Add($j.Handle) }

$alvos = New-Object System.Collections.ArrayList

# ============================================================== SAIPOS
$saiposAtalho = Valor-Config $cfg 'SAIPOS_ATALHO' ''
$saiposTitulo = Valor-Config $cfg 'SAIPOS_TITULO' 'saipos'

if (-not $saiposAtalho) {
    Escrever-Log 'SAIPOS_ATALHO vazio no config.txt - SAIPOS não será aberto.'
} elseif (-not (Test-Path -LiteralPath $saiposAtalho)) {
    Escrever-Log "ERRO: atalho do SAIPOS não encontrado: $saiposAtalho"
} else {
    $ext = [IO.Path]::GetExtension($saiposAtalho).ToLowerInvariant()
    $procs = @()
    $iniciou = $false
    if ($ext -eq '.lnk') {
        $shell = New-Object -ComObject WScript.Shell
        $lnk   = $shell.CreateShortcut($saiposAtalho)
        $exe   = $lnk.TargetPath
        $argumentos = $lnk.Arguments
        $wd    = $lnk.WorkingDirectory
        $exeNome = ''
        if ($exe) { $exeNome = [IO.Path]::GetFileName($exe).ToLowerInvariant() }
        Escrever-Log "Atalho SAIPOS: $saiposAtalho -> '$exe' $argumentos"

        if (($exeNome -in @('chrome.exe', 'chrome_proxy.exe', 'msedge.exe', 'msedge_proxy.exe')) -and ($argumentos -match '--app')) {
            # App/site do Chrome/Edge: força a posição na tela principal
            $b = $principal.Bounds
            $novosArgs = "$argumentos --window-position=$($b.X),$($b.Y) --start-maximized"
            $p = @{ FilePath = $exe; ArgumentList = $novosArgs }
            if ($wd -and (Test-Path -LiteralPath $wd)) { $p.WorkingDirectory = $wd }
            if ($exeNome -like 'chrome*') { $procs = @('chrome') } else { $procs = @('msedge') }
            $iniciou = Iniciar-Processo $p "SAIPOS (app do navegador): $exe $novosArgs"
        } else {
            if ($exeNome) { $procs = @([IO.Path]::GetFileNameWithoutExtension($exeNome)) }
            $iniciou = Iniciar-Processo @{ FilePath = $saiposAtalho } "SAIPOS (atalho $saiposAtalho)"
        }
    } else {
        if ($ext -eq '.exe') { $procs = @([IO.Path]::GetFileNameWithoutExtension($saiposAtalho).ToLowerInvariant()) }
        $iniciou = Iniciar-Processo @{ FilePath = $saiposAtalho } "SAIPOS ($saiposAtalho)"
    }
    if ($iniciou) {
        [void]$alvos.Add((Novo-Alvo 'SAIPOS' ('(?i)' + [regex]::Escape($saiposTitulo)) $procs $principal $false))
    }
}

# ========================================================= SEGUNDA TELA
$segundaArq = Valor-Config $cfg 'SEGUNDA_TELA' ''
$extNavegador = @('.pdf', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.htm', '.html', '.mht', '.mhtml')

if (-not $segundaArq) {
    Escrever-Log 'SEGUNDA_TELA vazio no config.txt - nada será aberto na segunda tela.'
} elseif (-not $segunda) {
    Escrever-Log "Segunda tela não disponível - '$segundaArq' não será aberto."
} else {
    $ehUrl = $segundaArq -match '^(?i)https?://'
    if ((-not $ehUrl) -and (-not (Test-Path -LiteralPath $segundaArq))) {
        Escrever-Log "SEGUNDA_TELA aponta para um arquivo que não existe: $segundaArq - nada aberto."
    } else {
        $ext = ''
        if (-not $ehUrl) { $ext = [IO.Path]::GetExtension($segundaArq).ToLowerInvariant() }
        $navegador = $null
        if ($ehUrl -or ($extNavegador -contains $ext)) { $navegador = Achar-Navegador }

        if ($navegador) {
            if ($ehUrl) { $endereco = $segundaArq } else { $endereco = ([Uri](Resolve-Path -LiteralPath $segundaArq).ProviderPath).AbsoluteUri }
            $b = $segunda.Bounds
            $perfil = Join-Path $Pasta 'ChromeSegundaTela'
            $argsNav = @(
                '--new-window',
                "--window-position=$($b.X),$($b.Y)",
                "--window-size=$($b.Width),$($b.Height)",
                '--kiosk',
                "--user-data-dir=`"$perfil`"",
                '--no-first-run',
                '--no-default-browser-check',
                '--disable-session-crashed-bubble',
                "`"$endereco`""
            ) -join ' '
            $procNav = [IO.Path]::GetFileNameWithoutExtension($navegador).ToLowerInvariant()
            $regex = ''
            if (-not $ehUrl) { $regex = '(?i)' + [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($segundaArq)) }
            if (Iniciar-Processo @{ FilePath = $navegador; ArgumentList = $argsNav } "Segunda tela (navegador em tela cheia): $endereco") {
                [void]$alvos.Add((Novo-Alvo 'SEGUNDA TELA' $regex @($procNav) $segunda $true))
            }
        } else {
            if ($ehUrl) {
                Escrever-Log 'AVISO: Chrome/Edge não encontrado; abrindo o endereço no navegador padrão.'
            } elseif ($extNavegador -contains $ext) {
                Escrever-Log 'AVISO: Chrome/Edge não encontrado; abrindo com o programa padrão.'
            }
            $regex = ''
            if (-not $ehUrl) { $regex = '(?i)' + [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($segundaArq)) }
            if (Iniciar-Processo @{ FilePath = $segundaArq } "Segunda tela (programa padrão): $segundaArq") {
                [void]$alvos.Add((Novo-Alvo 'SEGUNDA TELA' $regex @('*') $segunda $false))
            }
        }
    }
}

# ============================================ achar e posicionar janelas
$tempoMax = 120
[void][int]::TryParse((Valor-Config $cfg 'ESPERA_JANELA_SEGUNDOS' '120'), [ref]$tempoMax)
$estabilizar = 15   # depois de achar, continua conferindo por 15 s (telas de abertura etc.)
$limite = (Get-Date).AddSeconds($tempoMax)
$inicioBusca = Get-Date

while ($alvos.Count -gt 0 -and (Get-Date) -lt $limite) {
    $janelas = [AutoTelas.Win32]::Listar()

    # janela sumiu? (ex.: tela de abertura) -> procurar de novo
    foreach ($a in $alvos) {
        if ($a.Handle -ne [IntPtr]::Zero -and (-not [AutoTelas.Win32]::IsWindow($a.Handle) -or -not [AutoTelas.Win32]::IsWindowVisible($a.Handle))) {
            Escrever-Log "$($a.Nome): janela fechou/sumiu, procurando novamente..."
            $a.Handle = [IntPtr]::Zero
        }
    }
    $usadas = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
    foreach ($a in $alvos) { if ($a.Handle -ne [IntPtr]::Zero) { [void]$usadas.Add($a.Handle) } }

    # passo 1: pelo título
    foreach ($a in $alvos) {
        if ($a.Handle -ne [IntPtr]::Zero -or -not $a.RegexTitulo) { continue }
        foreach ($j in $janelas) {
            if ($usadas.Contains($j.Handle)) { continue }
            if ((Nome-Processo $j.Pid) -in $ignorar) { continue }
            if ($j.Titulo -match $a.RegexTitulo) {
                $a.Handle = $j.Handle; [void]$usadas.Add($j.Handle)
                if (-not $a.AchadaEm) { $a.AchadaEm = Get-Date }
                Escrever-Log "$($a.Nome): janela encontrada pelo título '$($j.Titulo)'"
                break
            }
        }
    }
    # passo 2: janela nova do processo esperado
    foreach ($a in $alvos) {
        if ($a.Handle -ne [IntPtr]::Zero -or $a.Processos.Count -eq 0) { continue }
        # dá 8 s para a janela com o título certo aparecer antes de aceitar qualquer janela nova
        if ($a.RegexTitulo -and ((Get-Date) - $inicioBusca).TotalSeconds -lt 8) { continue }
        foreach ($j in $janelas) {
            if ($antes.Contains($j.Handle) -or $usadas.Contains($j.Handle)) { continue }
            $np = Nome-Processo $j.Pid
            if ($np -in $ignorar) { continue }
            if (($a.Processos -contains '*') -or ($a.Processos -contains $np)) {
                $a.Handle = $j.Handle; [void]$usadas.Add($j.Handle)
                if (-not $a.AchadaEm) { $a.AchadaEm = Get-Date }
                Escrever-Log "$($a.Nome): janela nova encontrada ($np): '$($j.Titulo)'"
                break
            }
        }
    }

    # posiciona
    foreach ($a in $alvos) {
        if ($a.Handle -eq [IntPtr]::Zero) { continue }
        if (-not (Posicao-Correta $a)) {
            if ($a.Movimentos -lt 10) {
                $a.Movimentos++
                Mover-Janela $a
                $onde = 'tela principal'; if ($a.Tela -ne $principal) { $onde = 'segunda tela' }
                Escrever-Log "$($a.Nome): janela movida para a $onde (tentativa $($a.Movimentos))"
            }
        }
    }

    # terminou?
    $pronto = $true
    foreach ($a in $alvos) {
        if ($a.Handle -eq [IntPtr]::Zero -or -not $a.AchadaEm -or ((Get-Date) - $a.AchadaEm).TotalSeconds -lt $estabilizar) { $pronto = $false }
    }
    if ($pronto) { break }
    Start-Sleep -Seconds 1
}

foreach ($a in $alvos) {
    if ($a.Handle -eq [IntPtr]::Zero) {
        Escrever-Log "AVISO: $($a.Nome) - nenhuma janela encontrada em $tempoMax s (não foi possível posicionar)."
    } elseif (Posicao-Correta $a) {
        Escrever-Log "OK: $($a.Nome) está na tela certa."
    } else {
        Escrever-Log "AVISO: $($a.Nome) - a janela não ficou na posição esperada."
    }
}

Escrever-Log '================ AutoTelas finalizado ================'
$mutex.ReleaseMutex()
