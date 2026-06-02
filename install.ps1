# install.ps1 — instalador da Skill Pagou PIX Integrator para Windows
#
# Uso:
#   .\install.ps1                  # copia para %USERPROFILE%\.claude\skills\
#   .\install.ps1 -Link            # cria symlink (precisa de Developer Mode ou Admin)
#   .\install.ps1 -Force           # sobrescreve instalação existente
#   .\install.ps1 -Path C:\custom  # destino customizado

[CmdletBinding()]
param(
    [switch]$Link,
    [switch]$Force,
    [string]$Path
)

$ErrorActionPreference = "Stop"

$SkillName = "pagou-pix-integrator"
$SourceDir = $PSScriptRoot

if (-not $Path) {
    $Path = Join-Path $env:USERPROFILE ".claude\skills"
}

$Dest = Join-Path $Path $SkillName

Write-Host "Pagou PIX Integrator — instalador" -ForegroundColor Cyan
Write-Host "  Origem:  $SourceDir"
Write-Host "  Destino: $Dest"
Write-Host ""

# Verificar source
if (-not (Test-Path (Join-Path $SourceDir "SKILL.md"))) {
    Write-Host "ERRO: SKILL.md não encontrado em $SourceDir" -ForegroundColor Red
    Write-Host "Rode este script de dentro da pasta da skill." -ForegroundColor Red
    exit 1
}

# Criar pasta pai se não existir
$ParentDir = Split-Path $Dest -Parent
if (-not (Test-Path $ParentDir)) {
    Write-Host "Criando $ParentDir..."
    New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
}

# Tratar instalação existente
if (Test-Path $Dest) {
    if ($Force) {
        Write-Host "Removendo instalação existente..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $Dest
    } else {
        Write-Host "ERRO: já existe uma instalação em $Dest" -ForegroundColor Red
        Write-Host "Use -Force para sobrescrever." -ForegroundColor Red
        exit 1
    }
}

# Instalar
if ($Link) {
    Write-Host "Criando symbolic link..." -ForegroundColor Green
    try {
        New-Item -ItemType SymbolicLink -Path $Dest -Target $SourceDir | Out-Null
    } catch {
        Write-Host "ERRO ao criar symlink: $_" -ForegroundColor Red
        Write-Host "Symlinks no Windows requerem Developer Mode ou execução como Administrador." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Copiando arquivos..." -ForegroundColor Green
    Copy-Item -Recurse -Path $SourceDir -Destination $Dest -Exclude @("install.ps1", "install.sh", ".git", ".gitignore")
}

# Verificar
if (-not (Test-Path (Join-Path $Dest "SKILL.md"))) {
    Write-Host "ERRO: instalação falhou — SKILL.md não chegou ao destino." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Instalado com sucesso." -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Cyan
Write-Host "  1. Reinicie o Claude Code"
Write-Host "  2. Em qualquer projeto, invoque: /pagou-pix-integrator"
Write-Host ""
Write-Host "Para verificar: dir `"$Dest`""
