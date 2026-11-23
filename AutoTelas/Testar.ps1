#requires -Version 5.1
<#
    AutoTelas - Testar.ps1  (passo 6)
    1. Cria um arquivo de teste e coloca TEMPORARIAMENTE em SEGUNDA_TELA no config.txt
    2. Roda IniciarTelas.ps1 sem a espera de 20 s
    3. Pergunta se cada coisa abriu na tela certa
    4. Devolve SEGUNDA_TELA ao valor anterior (vazio) - sempre, mesmo se der erro
#>
param([switch]$NaoPausar)

$ErrorActionPreference = 'Continue'
$Pasta   = $PSScriptRoot
$cfgPath = Join-Path $Pasta 'config.txt'
$script  = Join-Path $Pasta 'IniciarTelas.ps1'

function Perguntar-SN([string]$Pergunta) {
    while ($true) {
        $r = (Read-Host "$Pergunta (S/N)").Trim().ToUpperInvariant()
        if ($r -in @('S', 'SIM')) { return $true }
        if ($r -in @('N', 'NAO', 'NÃO')) { return $false }
    }
}
function Definir-SegundaTela([string]$Valor) {
    $linhas = @(Get-Content -LiteralPath $cfgPath -Encoding UTF8)
    $achou = $false
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^\s*SEGUNDA_TELA\s*=') { $linhas[$i] = "SEGUNDA_TELA=$Valor"; $achou = $true }
    }
    if (-not $achou) { $linhas += "SEGUNDA_TELA=$Valor" }
    Set-Content -LiteralPath $cfgPath -Value $linhas -Encoding UTF8
}
function Log([string]$m) {
    Add-Content -LiteralPath (Join-Path $Pasta 'log.txt') -Value ('{0}  [TESTE] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Host "config.txt não encontrado em $Pasta. Rode o Configurar primeiro." -ForegroundColor Red; if (-not $NaoPausar) { Read-Host 'ENTER para sair' }; exit 1 }

$original = ''
foreach ($l in Get-Content -LiteralPath $cfgPath -Encoding UTF8) {
    if ($l -match '^\s*SEGUNDA_TELA\s*=(.*)$') { $original = $Matches[1].Trim() }
}

$pastaTeste = Join-Path $Pasta 'teste'
New-Item -ItemType Directory -Path $pastaTeste -Force | Out-Null

Write-Host ''
Write-Host 'Qual tipo de arquivo de teste usar na segunda tela?'
Write-Host '  1 = .txt  (abre no Bloco de Notas e a janela é movida via SetWindowPos)'
Write-Host '  2 = .html (abre no Chrome em tela cheia/kiosk - mesmo caminho usado para PDF e imagem)'
$op = Read-Host 'Escolha 1 ou 2 [1]'
if ($op -eq '2') {
    $arq = Join-Path $pastaTeste 'TESTE_SEGUNDA_TELA.html'
    Set-Content -LiteralPath $arq -Encoding UTF8 -Value @'
<!doctype html><html><head><meta charset="utf-8"><title>TESTE_SEGUNDA_TELA</title></head>
<body style="margin:0;display:flex;align-items:center;justify-content:center;height:100vh;background:#0b5;color:#fff;font:bold 6vw sans-serif;text-align:center">
SEGUNDA TELA (DisplayPort)<br><span style="font-size:2.5vw">Teste do AutoTelas - feche com Alt+F4</span></body></html>
'@
} else {
    $arq = Join-Path $pastaTeste 'TESTE_SEGUNDA_TELA.txt'
    Set-Content -LiteralPath $arq -Encoding UTF8 -Value @(
        'TESTE DO AUTOTELAS',
        '',
        'Este Bloco de Notas deve estar MAXIMIZADO na SEGUNDA TELA (monitor da DisplayPort).',
        'Pode fechar esta janela depois do teste.'
    )
}

Write-Host ''
Write-Host 'Vou alterar TEMPORARIAMENTE o config.txt:'
Write-Host "  SEGUNDA_TELA=$arq"
Write-Host 'e depois executar o IniciarTelas.ps1 (o SAIPOS vai abrir agora).'
if (-not (Perguntar-SN 'Pode fazer o teste?')) { if (-not $NaoPausar) { Read-Host 'ENTER para sair' }; exit 0 }

try {
    Definir-SegundaTela $arq
    Log "Início do teste com $arq"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -SemEspera

    Write-Host ''
    $okSaipos  = Perguntar-SN 'O SAIPOS abriu MAXIMIZADO na TELA PRINCIPAL (VGA)?'
    $okSegunda = Perguntar-SN 'O arquivo de teste abriu na SEGUNDA TELA (DisplayPort)?'
    Log "Resultado - SAIPOS na tela principal: $okSaipos / Segunda tela: $okSegunda"
    if ($okSaipos -and $okSegunda) {
        Write-Host 'Teste OK!' -ForegroundColor Green
    } else {
        Write-Host "Algo não ficou certo. Veja o log em $Pasta\log.txt e me envie o conteúdo." -ForegroundColor Yellow
    }
} finally {
    Definir-SegundaTela $original
    Log "config.txt restaurado: SEGUNDA_TELA=$original"
    Write-Host "config.txt restaurado (SEGUNDA_TELA=$original)." -ForegroundColor Cyan
}
if (-not $NaoPausar) { Read-Host 'ENTER para sair' }
