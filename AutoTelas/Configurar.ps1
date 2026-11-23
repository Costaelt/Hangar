#requires -Version 5.1
<#
    AutoTelas - Configurar.ps1
    Assistente que prepara o computador. NADA é alterado sem você responder "S".

      Passo 1  Detecta os monitores (resolução, posição, tipo de conexão, principal)
      Passo 2  Procura o atalho do SAIPOS e mostra para onde ele aponta
      Passo 5a Verifica se o SAIPOS já abre sozinho na inicialização
      Passo 3/4 Cria C:\AutoTelas (script, .bat, config.txt)
      Passo 5  Cria o atalho na pasta Inicializar (shell:startup)
      Passo 6  (opcional) roda o teste - Testar.ps1
      Passo 7  Pergunta sobre login automático
#>

$ErrorActionPreference = 'Continue'
$Origem  = $PSScriptRoot
$Destino = 'C:\AutoTelas'

function Titulo([string]$t) {
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}
function Perguntar-SN([string]$Pergunta) {
    while ($true) {
        $r = (Read-Host "$Pergunta (S/N)").Trim().ToUpperInvariant()
        if ($r -in @('S', 'SIM')) { return $true }
        if ($r -in @('N', 'NAO', 'NÃO')) { return $false }
    }
}
function Sair([int]$Codigo = 0) {
    Write-Host ''
    Read-Host 'Pressione ENTER para fechar'
    exit $Codigo
}

if (-not ('AutoTelasCfg.Tela' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AutoTelasCfg
{
    public static class Tela
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);

        public static void TornarDpiAware()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        // Devolve "DISPLAY\XXX\instancia" do monitor ligado a \\.\DISPLAYn (para cruzar com o WMI)
        public static string InstanciaMonitor(string adaptador)
        {
            DISPLAY_DEVICE d = new DISPLAY_DEVICE();
            d.cb = Marshal.SizeOf(d);
            for (uint i = 0; EnumDisplayDevices(adaptador, i, ref d, 1); i++)
            {
                if ((d.StateFlags & 1) == 0) { d.cb = Marshal.SizeOf(d); continue; } // ativo
                string id = d.DeviceID; // \\?\DISPLAY#DEL4074#5&abc&0&UID4352#{guid}
                if (id.StartsWith(@"\\?\")) id = id.Substring(4);
                string[] p = id.Split('#');
                if (p.Length >= 3) return (p[0] + "\\" + p[1] + "\\" + p[2]).ToUpperInvariant();
                d.cb = Marshal.SizeOf(d);
            }
            return "";
        }
        public static string NomeMonitor(string adaptador)
        {
            DISPLAY_DEVICE d = new DISPLAY_DEVICE();
            d.cb = Marshal.SizeOf(d);
            if (EnumDisplayDevices(adaptador, 0, ref d, 0)) return d.DeviceString;
            return "";
        }
    }
}
'@
}
[AutoTelasCfg.Tela]::TornarDpiAware()
Add-Type -AssemblyName System.Windows.Forms

$nomesConexao = @{
    0 = 'VGA'; 1 = 'S-Video'; 2 = 'Composto'; 3 = 'Componente'; 4 = 'DVI'
    5 = 'HDMI'; 6 = 'LVDS (interna)'; 10 = 'DisplayPort'; 11 = 'DisplayPort (interna)'
    15 = 'Miracast'
}

function Detectar-Monitores {
    $conexoes = @{}
    try {
        foreach ($c in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop) {
            $inst = ($c.InstanceName -replace '_\d+$', '').ToUpperInvariant()
            $conexoes[$inst] = [int]$c.VideoOutputTechnology
        }
    } catch {
        Write-Host "  (não foi possível ler o tipo de conexão via WMI: $($_.Exception.Message))" -ForegroundColor Yellow
    }
    $lista = @()
    $n = 0
    foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        $n++
        $inst = [AutoTelasCfg.Tela]::InstanciaMonitor($s.DeviceName)
        $tec = $null
        if ($inst -and $conexoes.ContainsKey($inst)) { $tec = $conexoes[$inst] }
        $conexao = 'desconhecida'
        if ($null -ne $tec) {
            if ($nomesConexao.ContainsKey($tec)) { $conexao = $nomesConexao[$tec] } else { $conexao = "código $tec" }
        }
        $lista += [pscustomobject]@{
            Numero    = $n
            Dispositivo = $s.DeviceName
            Monitor   = [AutoTelasCfg.Tela]::NomeMonitor($s.DeviceName)
            Resolucao = '{0}x{1}' -f $s.Bounds.Width, $s.Bounds.Height
            Posicao   = '({0},{1})' -f $s.Bounds.X, $s.Bounds.Y
            Conexao   = $conexao
            Principal = $s.Primary
            Tecnologia = $tec
        }
    }
    return $lista
}

# ===================================================================== 1
Titulo 'PASSO 1 - Monitores conectados'
$monitores = Detectar-Monitores
$monitores | Format-Table Numero, Dispositivo, Monitor, Resolucao, Posicao, Conexao, @{n='Principal';e={ if ($_.Principal) { 'SIM' } else { '' } }} -AutoSize | Out-Host

if ($monitores.Count -lt 2) {
    Write-Host 'Só 1 monitor foi detectado.' -ForegroundColor Red
    Write-Host 'Verifique os cabos e se o Windows está em modo "Estender" (tecla Windows + P > Estender).'
    Write-Host 'Nada foi alterado. Rode este assistente de novo quando os dois monitores aparecerem.'
    Sair 1
}

$vga = @($monitores | Where-Object { $_.Tecnologia -eq 0 })
$principal = $monitores | Where-Object { $_.Principal } | Select-Object -First 1

if ($vga.Count -eq 1) {
    if ($vga[0].Principal) {
        Write-Host "OK: o monitor da VGA ($($vga[0].Dispositivo)) já é a TELA PRINCIPAL." -ForegroundColor Green
    } else {
        Write-Host "ATENÇÃO: o monitor da VGA ($($vga[0].Dispositivo)) NÃO é a tela principal." -ForegroundColor Yellow
        Write-Host 'Para corrigir: Configurações > Sistema > Vídeo > clique no monitor da VGA (use "Identificar")'
        Write-Host '             > marque "Tornar este meu vídeo principal".'
        if (Perguntar-SN 'Quer que eu abra essa tela de Configurações agora?') {
            Start-Process 'ms-settings:display'
            Read-Host 'Faça a alteração e depois pressione ENTER para eu conferir de novo'
            # o .NET guarda a lista de telas em cache; reabrir o assistente é o jeito seguro
            Write-Host 'Feche esta janela e rode o assistente de novo para eu confirmar a nova tela principal.' -ForegroundColor Yellow
            Sair 0
        } else {
            Write-Host 'Seguindo sem alterar. O SAIPOS vai abrir na tela que for a principal do Windows.' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host 'Não consegui identificar com certeza qual monitor está na VGA pelo Windows.' -ForegroundColor Yellow
    Write-Host 'Confira em Configurações > Sistema > Vídeo > "Identificar": o número que aparecer no'
    Write-Host 'monitor da VGA deve ser o que tem "Tornar este meu vídeo principal" marcado.'
    Write-Host "Hoje a tela principal é: $($principal.Dispositivo) $($principal.Monitor) $($principal.Resolucao)"
    if (Perguntar-SN 'Abrir as Configurações de Vídeo para você conferir?') {
        Start-Process 'ms-settings:display'
        if (-not (Perguntar-SN 'O monitor da VGA já é o principal? (se mudou agora, responda N e rode o assistente de novo)')) { Sair 0 }
    }
}

# ===================================================================== 2
Titulo 'PASSO 2 - Atalho do SAIPOS'
$pastas = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    'C:\Users\Public\Desktop',
    [Environment]::GetFolderPath('CommonDesktopDirectory'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$shell = New-Object -ComObject WScript.Shell
$achados = @()
foreach ($p in $pastas) {
    Write-Host "  procurando em $p"
    foreach ($f in Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.lnk', '.url') -and $_.Name -match '(?i)saipos' }) {
        if ($achados.Caminho -contains $f.FullName) { continue }
        $alvo = ''; $args2 = ''; $pastaTrab = ''
        if ($f.Extension -ieq '.lnk') {
            $l = $shell.CreateShortcut($f.FullName)
            $alvo = $l.TargetPath; $args2 = $l.Arguments; $pastaTrab = $l.WorkingDirectory
        } else {
            $alvo = ((Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue) | Where-Object { $_ -like 'URL=*' } | Select-Object -First 1) -replace '^URL=', ''
            $args2 = '(atalho de internet - abre no navegador padrão)'
        }
        $achados += [pscustomobject]@{ Caminho = $f.FullName; Alvo = $alvo; Argumentos = $args2; PastaTrabalho = $pastaTrab }
    }
}

if ($achados.Count -eq 0) {
    Write-Host 'Nenhum atalho com "SAIPOS" no nome foi encontrado.' -ForegroundColor Yellow
    $manual = (Read-Host 'Digite o caminho completo do atalho/programa do SAIPOS (ou ENTER para cancelar)').Trim().Trim('"')
    if (-not $manual -or -not (Test-Path -LiteralPath $manual)) { Write-Host 'Cancelado. Nada foi alterado.'; Sair 1 }
    $escolhido = $manual
} else {
    $i = 0
    foreach ($a in $achados) {
        $i++
        Write-Host ''
        Write-Host "[$i] Atalho:     $($a.Caminho)" -ForegroundColor White
        Write-Host "    Executável: $($a.Alvo)"
        Write-Host "    Argumentos: $($a.Argumentos)"
        if ($a.PastaTrabalho) { Write-Host "    Iniciar em: $($a.PastaTrabalho)" }
        if ("$($a.Alvo)" -match '(?i)\\(chrome|chrome_proxy|msedge|msedge_proxy)\.exe$' -and $a.Argumentos -match '--app') {
            Write-Host '    -> É um app/site do navegador: vou usar --window-position para a tela principal.' -ForegroundColor Cyan
        }
    }
    Write-Host ''
    if ($achados.Count -eq 1) {
        if (-not (Perguntar-SN 'Usar este atalho para abrir o SAIPOS?')) { Write-Host 'Cancelado. Nada foi alterado.'; Sair 1 }
        $escolhido = $achados[0].Caminho
    } else {
        do {
            $n = 0
            [void][int]::TryParse((Read-Host "Há $($achados.Count) atalhos. Qual número devo usar?"), [ref]$n)
        } while ($n -lt 1 -or $n -gt $achados.Count)
        $escolhido = $achados[$n - 1].Caminho
    }
}
Write-Host "SAIPOS: $escolhido" -ForegroundColor Green

# ==================================================================== 5a
Titulo 'Verificando se o SAIPOS já abre sozinho ao ligar'
$jaInicia = @()
$pastasStartup = @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))
foreach ($p in $pastasStartup) {
    if ($p -and (Test-Path -LiteralPath $p)) {
        foreach ($f in Get-ChildItem -LiteralPath $p -ErrorAction SilentlyContinue) {
            $txt = $f.Name
            if ($f.Extension -ieq '.lnk') { $l = $shell.CreateShortcut($f.FullName); $txt += " $($l.TargetPath) $($l.Arguments)" }
            if ($txt -match '(?i)saipos') { $jaInicia += "Pasta Inicializar: $($f.FullName)" }
        }
    }
}
foreach ($chave in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
    try {
        $props = Get-ItemProperty -LiteralPath $chave -ErrorAction Stop
        foreach ($pr in $props.PSObject.Properties) {
            if ($pr.Name -like 'PS*') { continue }
            if ("$($pr.Name) $($pr.Value)" -match '(?i)saipos') { $jaInicia += "Registro ${chave}: $($pr.Name) = $($pr.Value)" }
        }
    } catch { }
}
try {
    foreach ($t in Get-ScheduledTask -ErrorAction Stop) {
        $acoes = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
        if ("$($t.TaskName) $acoes" -match '(?i)saipos') { $jaInicia += "Tarefa agendada: $($t.TaskPath)$($t.TaskName) ($($t.State))" }
    }
} catch { }

if ($jaInicia.Count -gt 0) {
    Write-Host 'ATENÇÃO: o SAIPOS JÁ está configurado para abrir sozinho:' -ForegroundColor Yellow
    $jaInicia | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host 'Se continuar, ele pode abrir DUAS vezes. Recomendo desativar a entrada acima'
    Write-Host '(Gerenciador de Tarefas > aba Inicializar > Desabilitar) e deixar o AutoTelas cuidar disso.'
    if (-not (Perguntar-SN 'Continuar mesmo assim?')) { Sair 0 }
} else {
    Write-Host 'OK: não encontrei o SAIPOS configurado para iniciar sozinho.' -ForegroundColor Green
}

# =================================================================== 3/4
Titulo "PASSOS 3 e 4 - Criar a pasta $Destino"
$arquivosOrigem = @('IniciarTelas.ps1', 'IniciarTelas.bat', 'Testar.ps1', 'Desinstalar.ps1')
foreach ($a in $arquivosOrigem) {
    if (-not (Test-Path -LiteralPath (Join-Path $Origem $a))) { Write-Host "Arquivo $a não encontrado junto com este assistente." -ForegroundColor Red; Sair 1 }
}
$cfgPath = Join-Path $Destino 'config.txt'
$segundaAtual = ''
if (Test-Path -LiteralPath $cfgPath) {
    foreach ($l in Get-Content -LiteralPath $cfgPath -Encoding UTF8) {
        if ($l -match '^\s*SEGUNDA_TELA\s*=(.*)$') { $segundaAtual = $Matches[1].Trim() }
    }
}

Write-Host 'Vou criar/atualizar:'
Write-Host "  $Destino\IniciarTelas.ps1   (script que abre e posiciona as janelas)"
Write-Host "  $Destino\IniciarTelas.bat   (chama o script sem mostrar janela)"
Write-Host "  $Destino\Testar.ps1 e Desinstalar.ps1"
Write-Host "  $Destino\config.txt         (SAIPOS_ATALHO=$escolhido / SEGUNDA_TELA=$segundaAtual)"
Write-Host "  $Destino\log.txt            (criado quando o script rodar)"
if (-not (Perguntar-SN 'Posso criar esses arquivos?')) { Write-Host 'Cancelado. Nada foi alterado.'; Sair 0 }

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
foreach ($a in $arquivosOrigem) {
    Copy-Item -LiteralPath (Join-Path $Origem $a) -Destination (Join-Path $Destino $a) -Force
    Unblock-File -LiteralPath (Join-Path $Destino $a) -ErrorAction SilentlyContinue
}

$conteudo = @"
# ============================================================
#  AutoTelas - configuração
#  Linhas que começam com # são comentários (ignoradas).
#  Depois de editar, salve o arquivo. Vale no próximo login.
# ============================================================

# Atalho (ou programa) do SAIPOS - abre maximizado na TELA PRINCIPAL (VGA)
SAIPOS_ATALHO=$escolhido

# Parte do título da janela do SAIPOS (usado para achar a janela)
SAIPOS_TITULO=saipos

# Arquivo para abrir na SEGUNDA TELA (DisplayPort). Deixe vazio para não abrir nada.
# Pode ser PDF, imagem, .html, um endereço https://..., ou qualquer outro arquivo.
# Exemplos:
#   SEGUNDA_TELA=C:\Users\Public\Documents\cardapio.pdf
#   SEGUNDA_TELA=https://exemplo.com.br/painel
SEGUNDA_TELA=$segundaAtual

# Segundos de espera após o login antes de abrir tudo
ESPERA_SEGUNDOS=20
"@
Set-Content -LiteralPath $cfgPath -Value $conteudo -Encoding UTF8
Write-Host "OK: arquivos criados em $Destino" -ForegroundColor Green

# ===================================================================== 5
Titulo 'PASSO 5 - Abrir automaticamente ao ligar'
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'AutoTelas.lnk'
Write-Host "Vou criar o atalho: $lnkPath"
Write-Host "  -> $Destino\IniciarTelas.bat (janela minimizada)"
if (Perguntar-SN 'Posso criar o atalho na pasta Inicializar?') {
    $l = $shell.CreateShortcut($lnkPath)
    $l.TargetPath = Join-Path $Destino 'IniciarTelas.bat'
    $l.WorkingDirectory = $Destino
    $l.WindowStyle = 7
    $l.Description = 'AutoTelas - abre o SAIPOS e a segunda tela'
    $l.Save()
    Write-Host 'OK: atalho criado.' -ForegroundColor Green
} else {
    Write-Host 'Atalho NÃO criado. O AutoTelas não vai abrir sozinho ao ligar.' -ForegroundColor Yellow
}

# ===================================================================== 6
Titulo 'PASSO 6 - Teste'
Write-Host 'O teste abre o SAIPOS agora e um arquivo de teste na segunda tela,'
Write-Host 'pergunta se ficou tudo na tela certa e depois deixa SEGUNDA_TELA vazio de novo.'
if (Perguntar-SN 'Rodar o teste agora?') {
    & (Join-Path $Destino 'Testar.ps1') -NaoPausar
}

# ===================================================================== 7
Titulo 'PASSO 7 - Login automático (ligar sem pedir senha)'
Write-Host 'Opções:'
Write-Host '  A) netplwiz (já vem no Windows): desmarque "Os usuários devem digitar um nome de'
Write-Host '     usuário e uma senha para usar este computador" e informe a senha uma vez.'
Write-Host '     Se essa caixa não aparecer: Configurações > Contas > Opções de entrada >'
Write-Host '     desligue "Exigir entrada do Windows Hello para contas da Microsoft".'
Write-Host '  B) Autologon (Sysinternals/Microsoft): programinha oficial que grava a senha'
Write-Host '     criptografada (segredo LSA), não em texto puro no registro.'
Write-Host '     Download: https://learn.microsoft.com/sysinternals/downloads/autologon'
Write-Host '  Atenção: com login automático, qualquer pessoa que ligar o PC entra na sua conta.'
if (Perguntar-SN 'Quer configurar o login automático agora?') {
    if (Perguntar-SN 'Abrir o netplwiz (opção A)? (N = abrir a página do Autologon, opção B)') {
        Start-Process 'netplwiz.exe'
    } else {
        Start-Process 'https://learn.microsoft.com/sysinternals/downloads/autologon'
    }
} else {
    Write-Host 'Login automático não configurado.'
}

Titulo 'Concluído'
Write-Host "Configuração: $cfgPath"
Write-Host "Log:          $Destino\log.txt"
Write-Host "Para desativar: apague $lnkPath  (ou rode $Destino\Desinstalar.ps1)"
Sair 0
