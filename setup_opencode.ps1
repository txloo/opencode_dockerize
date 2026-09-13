# 1. Get project details for dynamic isolation names
$ProjectName = (Get-Item .).Name
$ContainerName = "opencode-$($ProjectName.ToLower())"
$LocalImageName = "opencode-local-$($ProjectName.ToLower())"

# 2. Dynamic Image Verification & .dockerignore management
if (Test-Path "Dockerfile") {
    Write-Host "🛠️ Project-level Dockerfile detected! Assembling workspace tools..." -ForegroundColor Cyan
    
    # Ensure .dockerignore exists to keep build context optimized
    if (-not (Test-Path ".dockerignore")) {
        Write-Host "📝 Creating missing .dockerignore file..." -ForegroundColor DarkCyan
        ".opencode_data/" | Out-File -FilePath ".dockerignore" -Encoding utf8
    } elseif (-not (Get-Content ".dockerignore" | Select-String -Pattern "\.opencode_data/")) {
        Write-Host "📝 Appending .opencode_data/ to existing .dockerignore..." -ForegroundColor DarkCyan
        Add-Content -Path ".dockerignore" -Value "`n.opencode_data/"
    }

    docker build -t $LocalImageName .
    $TargetImage = $LocalImageName
} else {
    Write-Host "💡 No local Dockerfile found. Using the global OpenCode base image..." -ForegroundColor Yellow
    $TargetImage = "custom-opencode:latest"
}

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