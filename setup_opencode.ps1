# 1. Get project details for dynamic isolation names
$ProjectName = (Get-Item .).Name
$ContainerName = "opencode-$($ProjectName.ToLower())"

# 2. Dynamic Image Verification & .dockerignore management
# Ensure .gitignore excludes the persistent session dir
if (-not (Test-Path ".gitignore")) {
    Write-Host "📝 Creating missing .gitignore file..." -ForegroundColor DarkCyan
    ".opencode_data/" | Out-File -FilePath ".gitignore" -Encoding utf8
} elseif (-not (Get-Content ".gitignore" | Select-String -Pattern "\.opencode_data")) {
    Write-Host "📝 Appending .opencode_data/ to existing .gitignore..." -ForegroundColor DarkCyan
    Add-Content -Path ".gitignore" -Value "`n.opencode_data/"
}

# Ensure .dockerignore excludes the persistent session dir
if (-not (Test-Path ".dockerignore")) {
    Write-Host "📝 Creating missing .dockerignore file..." -ForegroundColor DarkCyan
    ".opencode_data/" | Out-File -FilePath ".dockerignore" -Encoding utf8
} elseif (-not (Get-Content ".dockerignore" | Select-String -Pattern "\.opencode_data/")) {
    Write-Host "📝 Appending .opencode_data/ to existing .dockerignore..." -ForegroundColor DarkCyan
    Add-Content -Path ".dockerignore" -Value "`n.opencode_data/"
}

# Ensure the container-env skill is installed for this project
$SkillDir = Join-Path $PWD ".opencode\skills\container-env"
$SkillDest = Join-Path $SkillDir "SKILL.md"
if (Test-Path $SkillDest) {
    Write-Host "[SKIP] container-env skill already installed, leaving local copy untouched." -ForegroundColor DarkCyan
} elseif (Test-Path "$PSScriptRoot\container-env_SKILL.md") {
    Write-Host "📝 Installing container-env skill into .opencode/skills/container-env/..." -ForegroundColor DarkCyan
    New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
    Copy-Item -Path "$PSScriptRoot\container-env_SKILL.md" -Destination $SkillDest -Force
} else {
    Write-Warning "[WARN] container-env_SKILL.md not found next to setup_opencode.ps1. Skill not installed."
}

Write-Host "💡 Using the global OpenCode base image..." -ForegroundColor Yellow
$TargetImage = "custom-opencode:latest"

# 3. Check if Windows SSH keys exist to mount them safely
$SshDir = "$HOME\.ssh"
$SshMount = @()
if (Test-Path $SshDir) {
    $SshMount = @("-v", "$($HOME)\.ssh:/tmp/.ssh:ro")
}

# 4. Handle persistent OpenCode Session directory inside your PWD
$LocalDataDir = Join-Path $PWD ".opencode_data"

if (-not (Test-Path $LocalDataDir)) {
    New-Item -ItemType Directory -Force -Path $LocalDataDir | Out-Null
}

$TargetAuthDir = Join-Path $LocalDataDir "share\opencode"

if (-not (Test-Path $TargetAuthDir)) {
    New-Item -ItemType Directory -Force -Path $TargetAuthDir | Out-Null
}

# Check for auth.json in the current working directory or a secure master location
if (Test-Path "$PSScriptRoot\auth.json") {
    Write-Host "[INFO] Injecting secure LLM credentials for this session..." -ForegroundColor DarkGreen
    Copy-Item -Path "$PSScriptRoot\auth.json" -Destination (Join-Path $TargetAuthDir "auth.json") -Force
} else {
    Write-Warning "[WARN] auth.json not found in the current folder. You may need to authenticate manually."
}

Write-Host "🚀 Starting OpenCode container: $ContainerName using image: $TargetImage" -ForegroundColor Green

# 5. Run the customized infrastructure stack
docker run -it --rm `
  --name $ContainerName `
  -v "${PWD}:/workspace" `
  -v "${LocalDataDir}:/workspace/.opencode_data" `
  -e XDG_DATA_HOME=/workspace/.opencode_data/share `
  -e XDG_CONFIG_HOME=/workspace/.opencode_data/config `
  -e XDG_STATE_HOME=/workspace/.opencode_data/state `
  -e XDG_CACHE_HOME=/workspace/.opencode_data/cache `
  -e OPENCODE_CONFIG_DIR=/workspace/.opencode_data/config/opencode `
  $SshMount `
  $TargetImage