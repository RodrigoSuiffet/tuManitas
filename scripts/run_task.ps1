# run_task.ps1
# Uso: .\scripts\run_task.ps1 -issue TUM-5
#
# Requisitos:
#   - gh CLI autenticado (gh auth login)
#   - Claude Code instalado (claude)
#   - Fichero .env en la raiz del repo con LINEAR_API_TOKEN=lin_api_...

param(
    [Parameter(Mandatory=$true)]
    [string]$issue
)

function Write-Step { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  AVISO  $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  ERROR  $msg" -ForegroundColor Red }

# Cargar .env
$rootDir = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $rootDir ".env"

if (-not (Test-Path $envFile)) {
    Write-Fail "No se encontro el fichero .env en la raiz del repo."
    Write-Fail "Crea el fichero con: LINEAR_API_TOKEN=lin_api_tu_token_aqui"
    exit 1
}

Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*)\s*$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

$LINEAR_TOKEN = $env:LINEAR_API_TOKEN
if (-not $LINEAR_TOKEN) {
    Write-Fail "LINEAR_API_TOKEN no encontrado en el fichero .env"
    exit 1
}

# Verificar herramientas
Write-Step "Verificando herramientas"

if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Fail "GitHub CLI (gh) no esta instalado."
    exit 1
}
if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
    Write-Fail "Claude Code no esta instalado."
    exit 1
}
Write-Ok "gh y claude disponibles"

# Obtener issue de Linear
Write-Step "Obteniendo issue $issue de Linear"

$issueKey = $issue.ToUpper()

$query = '{ "query": "{ issue(id: \"' + $issueKey + '\") { id title description gitBranchName url state { name } } }" }'

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.linear.app/graphql" `
        -Method POST `
        -Headers @{
            "Authorization" = $LINEAR_TOKEN
            "Content-Type"  = "application/json"
        } `
        -Body $query

    $issueData   = $response.data.issue
    $title       = $issueData.title
    $description = $issueData.description
    $branchName  = $issueData.gitBranchName
    $issueUrl    = $issueData.url
    $issueState  = $issueData.state.name
} catch {
    Write-Fail "No se pudo obtener el issue de Linear: $_"
    exit 1
}

if (-not $title) {
    Write-Fail "Issue $issueKey no encontrado en Linear"
    exit 1
}

Write-Ok "Issue: $title"
Write-Ok "Rama:  $branchName"
Write-Ok "Estado: $issueState"

# Gestionar rama
Write-Step "Preparando rama git"

Set-Location $rootDir
git fetch origin 2>$null

$localBranch  = git branch --list $branchName
$remoteBranch = git ls-remote --heads origin $branchName 2>$null

if ($localBranch -or $remoteBranch) {
    Write-Warn "La rama '$branchName' ya existe - reanudando tarea"
    if ($remoteBranch -and -not $localBranch) {
        git checkout -b $branchName "origin/$branchName"
    } else {
        git checkout $branchName
        if ($remoteBranch) {
            git pull origin $branchName 2>$null
        }
    }
} else {
    Write-Ok "Creando rama desde main"
    git checkout main
    git pull origin main
    git checkout -b $branchName
}

# Preparar prompt
Write-Step "Preparando prompt para Claude Code"

$developerPrompt = Get-Content (Join-Path $rootDir "prompts" "developer.md") -Raw

$fullPrompt = $developerPrompt + "`n`n---`n`n# TAREA A DESARROLLAR`n`n**Issue:** $issueKey - $title`n**Linear:** $issueUrl`n`n$description`n`n---`n`n# INSTRUCCIONES FINALES`n`nRevisa el codigo existente en el repositorio antes de empezar.`nLa rama actual es: $branchName`n`nAl finalizar la implementacion completa con tests:`n1. git add de todos los ficheros creados o modificados`n2. git commit -m 'feat($issueKey): $title'`n3. git push origin $branchName"

$tempPrompt = Join-Path $env:TEMP "elgremio_$issueKey.txt"
$fullPrompt | Out-File -FilePath $tempPrompt -Encoding utf8

Write-Ok "Prompt preparado"

# Lanzar Claude Code
Write-Step "Lanzando Claude Code"
Write-Host ""
Write-Host "  Si Claude Code se interrumpe por limite de uso," -ForegroundColor Yellow
Write-Host "  vuelve a ejecutar este mismo comando cuando el plan se renueve." -ForegroundColor Yellow
Write-Host "  El script detectara la rama existente y continuara." -ForegroundColor Yellow
Write-Host ""

$promptContent = Get-Content $tempPrompt -Raw
claude $promptContent

# Verificar resultado
Write-Step "Verificando resultado"

$uncommitted = git status --porcelain

if ($uncommitted) {
    Write-Warn "Hay cambios sin commitear. Haciendo commit de seguridad..."
    git add -A
    git commit -m "wip($issueKey): trabajo parcial - sesion interrumpida"
    git push origin $branchName
    Write-Warn "Relanza el script cuando el plan se renueve para continuar."
    exit 0
}

$unpushed = git log "origin/$branchName..HEAD" --oneline 2>$null
if ($unpushed) {
    Write-Step "Haciendo push"
    git push origin $branchName
    Write-Ok "Push realizado"
}

# Crear Pull Request
Write-Step "Creando Pull Request"

$existingPR = gh pr list --head $branchName --json number --jq '.[0].number' 2>$null

if ($existingPR) {
    Write-Ok "Ya existe PR #$existingPR para esta rama"
} else {
    $prBody = "## $title`n`n**Issue Linear:** $issueUrl`n`n### Checklist`n- [ ] Tests en verde`n- [ ] Sin credenciales hardcodeadas`n- [ ] Migracion Flyway numerada correctamente`n- [ ] Audit log implementado donde corresponde`n- [ ] Ownership checks presentes`n- [ ] Endpoints protegidos con @PreAuthorize"

    gh pr create `
        --title "${issueKey}: $title" `
        --body $prBody `
        --base main `
        --head $branchName

    Write-Ok "Pull Request creada"
}

# Resumen final
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  Tarea $issueKey completada" -ForegroundColor Green
Write-Host "  Rama: $branchName" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Siguiente paso: revisar la PR en GitHub y mergear."
Write-Host "Luego lanza: .\scripts\run_task.ps1 -issue TUM-XX"