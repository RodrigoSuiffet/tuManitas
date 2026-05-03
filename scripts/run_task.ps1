# run_task.ps1
# Uso: .\scripts\run_task.ps1 -issue TUM-5
#
# Requisitos:
#   - gh CLI autenticado (gh auth login)
#   - Claude Code instalado (claude)
#   - Fichero .env en la raiz del repo con LINEAR_API_TOKEN=lin_api_...
#
# El script es ATOMICO: si Claude Code se interrumpe por limite de uso,
# puedes relanzarlo con el mismo comando y retomara desde el ultimo commit.

param(
    [Parameter(Mandatory=$true)]
    [string]$issue
)

# ─── Colores para output ───────────────────────────────────────────────────────
function Write-Step  { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  AVISO  $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  ERROR  $msg" -ForegroundColor Red }

# ─── Cargar variables de entorno desde .env ───────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".." ".env"
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

# ─── Verificar herramientas necesarias ────────────────────────────────────────
Write-Step "Verificando herramientas"

if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
    Write-Fail "GitHub CLI (gh) no esta instalado. Instala desde: https://cli.github.com"
    exit 1
}
if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
    Write-Fail "Claude Code no esta instalado. Instala con: npm install -g @anthropic/claude-code"
    exit 1
}
Write-Ok "gh y claude disponibles"

# ─── Obtener datos del issue desde Linear API ─────────────────────────────────
Write-Step "Obteniendo issue $issue de Linear"

$issueKey = $issue.ToUpper()

$query = @"
{
  "query": "{ issue(id: \"$issueKey\") { id title description gitBranchName url state { name } } }"
}
"@

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.linear.app/graphql" `
        -Method POST `
        -Headers @{
            "Authorization" = $LINEAR_TOKEN
            "Content-Type"  = "application/json"
        } `
        -Body $query

    $issueData  = $response.data.issue
    $title      = $issueData.title
    $description = $issueData.description
    $branchName = $issueData.gitBranchName
    $issueUrl   = $issueData.url
    $issueState = $issueData.state.name
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
Write-Ok "Estado en Linear: $issueState"

# ─── Verificar si ya existe trabajo previo en esta rama (reanudacion) ─────────
Write-Step "Comprobando estado de la rama"

$rootDir = Split-Path $PSScriptRoot -Parent
Set-Location $rootDir

git fetch origin 2>$null
$branchExists = git branch --list $branchName
$remoteBranchExists = git ls-remote --heads origin $branchName

if ($branchExists -or $remoteBranchExists) {
    Write-Warn "La rama '$branchName' ya existe — reanudando tarea interrumpida"
    if ($remoteBranchExists -and -not $branchExists) {
        git checkout -b $branchName "origin/$branchName"
    } else {
        git checkout $branchName
        if ($remoteBranchExists) { git pull origin $branchName 2>$null }
    }
} else {
    Write-Ok "Nueva rama — creando desde main"
    git checkout main
    git pull origin main
    git checkout -b $branchName
}

# ─── Preparar el prompt para Claude Code ──────────────────────────────────────
Write-Step "Preparando contexto para Claude Code"

$developerPrompt = Get-Content (Join-Path $PSScriptRoot ".." "prompts" "developer.md") -Raw

$fullPrompt = @"
$developerPrompt

---

# TAREA A DESARROLLAR

**Issue:** $issueKey — $title
**Linear:** $issueUrl

$description

---

# CONTEXTO DE CÓDIGO EXISTENTE

Revisa el codigo existente en el repositorio antes de empezar.
La rama actual es: $branchName

Al finalizar la implementacion completa con tests:
1. Haz git add de todos los ficheros creados o modificados
2. Haz git commit con el mensaje: feat($issueKey): $title
3. Haz git push origin $branchName
"@

# Guardar prompt en fichero temporal
$tempPrompt = Join-Path $env:TEMP "elgremio_prompt_$issueKey.txt"
$fullPrompt | Out-File -FilePath $tempPrompt -Encoding utf8

Write-Ok "Prompt preparado"

# ─── Lanzar Claude Code ───────────────────────────────────────────────────────
Write-Step "Lanzando Claude Code para $issueKey"
Write-Host ""
Write-Host "  IMPORTANTE: Si Claude Code se interrumpe por limite de uso," -ForegroundColor Yellow
Write-Host "  vuelve a ejecutar este mismo comando cuando se reanude el plan." -ForegroundColor Yellow
Write-Host "  El script detectara la rama existente y continuara desde donde quedo." -ForegroundColor Yellow
Write-Host ""

$promptContent = Get-Content $tempPrompt -Raw
claude $promptContent

# ─── Verificar que hay commits nuevos tras la sesion ─────────────────────────
Write-Step "Verificando resultado"

$unpushedCommits = git log "origin/$branchName..HEAD" --oneline 2>$null
$uncommittedChanges = git status --porcelain

if ($uncommittedChanges) {
    Write-Warn "Hay cambios sin commitear. Haciendo commit de seguridad..."
    git add -A
    git commit -m "wip($issueKey): trabajo parcial — sesion interrumpida"
    git push origin $branchName
    Write-Warn "Commit de seguridad realizado. Relanza el script para continuar."
    exit 0
}

if (-not $unpushedCommits) {
    Write-Warn "No se detectaron commits nuevos. Puede que Claude Code no haya terminado."
    Write-Warn "Revisa el output de Claude Code y relanza el script si es necesario."
    exit 0
}

# ─── Push si no se hizo automaticamente ──────────────────────────────────────
$remoteHasCommit = git log "origin/$branchName" --oneline 2>$null
if ($unpushedCommits) {
    Write-Step "Haciendo push a origin/$branchName"
    git push origin $branchName
    Write-Ok "Push realizado"
}

# ─── Crear Pull Request ───────────────────────────────────────────────────────
Write-Step "Creando Pull Request"

$existingPR = gh pr list --head $branchName --json number --jq '.[0].number' 2>$null

if ($existingPR) {
    Write-Ok "Ya existe PR #$existingPR para esta rama"
    gh pr view $branchName --web
} else {
    $prBody = @"
## $title

**Issue Linear:** $issueUrl

### Cambios implementados
_(generado automaticamente — editar si es necesario)_

### Checklist
- [ ] Tests en verde (mvn test / npm run test)
- [ ] Sin credenciales hardcodeadas
- [ ] Migracion Flyway numerada correctamente
- [ ] Audit log implementado donde corresponde
- [ ] Ownership checks presentes
- [ ] Endpoints protegidos con @PreAuthorize
"@

    gh pr create `
        --title "$issueKey`: $title" `
        --body $prBody `
        --base main `
        --head $branchName

    Write-Ok "Pull Request creada"
}

# ─── Resumen final ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  Tarea $issueKey completada" -ForegroundColor Green
Write-Host "  Rama: $branchName" -ForegroundColor Green
Write-Host "  PR creada y lista para revision" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Siguiente paso: revisar la PR en GitHub y mergear si todo esta correcto."
Write-Host "Luego ejecuta el siguiente issue:"
Write-Host "  .\scripts\run_task.ps1 -issue TUM-XX"
