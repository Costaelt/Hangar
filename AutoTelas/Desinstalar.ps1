#requires -Version 5.1
<#
    AutoTelas - Desinstalar.ps1
    Remove o atalho da pasta Inicializar e (opcionalmente) a pasta C:\AutoTelas.
#>
function Perguntar-SN([string]$Pergunta) {
    while ($true) {
        $r = (Read-Host "$Pergunta (S/N)").Trim().ToUpperInvariant()
        if ($r -in @('S', 'SIM')) { return $true }
        if ($r -in @('N', 'NAO', 'NÃO')) { return $false }
    }
}

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'AutoTelas.lnk'
if (Test-Path -LiteralPath $lnk) {
    if (Perguntar-SN "Apagar o atalho de inicialização $lnk ?") {
        Remove-Item -LiteralPath $lnk -Force
        Write-Host 'Atalho removido: o AutoTelas não abre mais ao ligar.' -ForegroundColor Green
    }
} else {
    Write-Host 'Atalho de inicialização não encontrado (já estava desativado).'
}

$pasta = 'C:\AutoTelas'
if (Test-Path -LiteralPath $pasta) {
    if (Perguntar-SN "Apagar também a pasta $pasta (scripts, config.txt, log.txt)?") {
        Set-Location $env:TEMP
        Remove-Item -LiteralPath $pasta -Recurse -Force
        Write-Host 'Pasta removida.' -ForegroundColor Green
    }
}
Read-Host 'ENTER para sair'
