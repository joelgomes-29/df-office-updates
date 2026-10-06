param(
  [string]$ManifestUrl,
  [switch]$NoPause,
  [switch]$SomenteVerificar
)

# Atualiza o DF Office baixando o pacote publicado, sem precisar copiar arquivos.
# Le o endereco do manifesto de config.json (chave updateManifestUrl) ou do parametro.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$nomeTarefa = "DF Office - Servidor"
$temporario = Join-Path ([System.IO.Path]::GetTempPath()) ("df-office-online-" + [guid]::NewGuid().ToString("N"))
$exitCode = 0

function Versao-Local {
  $arquivo = Join-Path $root "VERSION.txt"
  if (-not (Test-Path -LiteralPath $arquivo)) { return "desconhecida" }
  $linha = (Get-Content -LiteralPath $arquivo -First 1 -Encoding UTF8).Trim()
  if ($linha -match "(\d+\.\d+\.\d+)") { return $Matches[1] }
  return $linha
}

function Comparar-Versao([string]$a, [string]$b) {
  # Devolve 1 se a > b, -1 se a < b, 0 se iguais.
  try {
    $va = [version]$a
    $vb = [version]$b
    return $va.CompareTo($vb)
  } catch {
    return [string]::Compare($a, $b)
  }
}

try {
  if ([string]::IsNullOrWhiteSpace($ManifestUrl)) {
    $configPath = Join-Path $root "config.json"
    if (Test-Path -LiteralPath $configPath) {
      $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($config.PSObject.Properties.Name -contains "updateManifestUrl") { $ManifestUrl = $config.updateManifestUrl }
    }
  }

  if ([string]::IsNullOrWhiteSpace($ManifestUrl)) {
    throw "Endereco das atualizacoes nao configurado. Acrescente a chave updateManifestUrl em config.json ou rode com -ManifestUrl."
  }
  if ($ManifestUrl -notmatch "^https://") {
    throw "O endereco das atualizacoes precisa comecar com https://"
  }

  $versaoLocal = Versao-Local
  Write-Host "Versao instalada: $versaoLocal" -ForegroundColor Cyan
  Write-Host "Consultando $ManifestUrl" -ForegroundColor DarkGray

  $manifesto = Invoke-RestMethod -Uri $ManifestUrl -TimeoutSec 30
  foreach ($campo in @("version", "url", "sha256")) {
    if (-not $manifesto.PSObject.Properties.Name.Contains($campo)) { throw "Manifesto invalido: falta o campo $campo." }
  }
  if ($manifesto.url -notmatch "^https://") { throw "O endereco do pacote precisa comecar com https://" }

  Write-Host "Versao publicada: $($manifesto.version)" -ForegroundColor Cyan
  if ($manifesto.PSObject.Properties.Name -contains "notes" -and $manifesto.notes) {
    Write-Host "Novidades: $($manifesto.notes)" -ForegroundColor DarkGray
  }

  if ((Comparar-Versao $manifesto.version $versaoLocal) -le 0) {
    Write-Host "`nO sistema ja esta atualizado. Nada a fazer." -ForegroundColor Green
    if (-not $NoPause) { Read-Host "Pressione Enter para fechar" | Out-Null }
    exit 0
  }

  if ($SomenteVerificar) {
    Write-Host "`nExiste atualizacao disponivel: $($manifesto.version)." -ForegroundColor Yellow
    if (-not $NoPause) { Read-Host "Pressione Enter para fechar" | Out-Null }
    exit 0
  }

  New-Item -ItemType Directory -Path $temporario -Force | Out-Null
  $pacote = Join-Path $temporario "atualizacao.zip"
  Write-Host "`nBaixando o pacote..." -ForegroundColor Cyan
  Invoke-WebRequest -Uri $manifesto.url -OutFile $pacote -TimeoutSec 300

  $hash = (Get-FileHash -LiteralPath $pacote -Algorithm SHA256).Hash.ToLower()
  if ($hash -ne $manifesto.sha256.ToLower()) {
    throw "O arquivo baixado nao confere com a assinatura publicada. Atualizacao cancelada por seguranca."
  }
  Write-Host "Integridade conferida." -ForegroundColor Green

  # Se o sistema sobe pelo Agendador, encerra a tarefa antes de aplicar.
  $tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
  if ($tarefa) {
    Write-Host "Encerrando a tarefa agendada..." -ForegroundColor DarkGray
    Stop-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  & (Join-Path $PSScriptRoot "atualizar-servidor.ps1") -UpdateZip $pacote -NoPause
  if ($LASTEXITCODE -ne 0) { throw "A atualizacao falhou. A versao anterior foi restaurada." }

  # Devolve o controle para a tarefa agendada, para o sistema subir sozinho no boot.
  if ($tarefa) {
    Write-Host "Devolvendo o controle para a tarefa agendada..." -ForegroundColor DarkGray
    & (Join-Path $PSScriptRoot "parar-servidor.ps1")
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName $nomeTarefa
    Start-Sleep -Seconds 3
  }

  $config = Get-Content -LiteralPath (Join-Path $root "config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  $saude = Invoke-RestMethod -Uri ("http://127.0.0.1:" + [int]$config.port + "/api/health") -TimeoutSec 15
  Write-Host "`nSistema no ar na versao $($saude.version)." -ForegroundColor Green
  Write-Host "Peca Ctrl + F5 uma vez nos computadores da equipe." -ForegroundColor Yellow
} catch {
  $exitCode = 1
  Write-Host "`nFalha: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  if (Test-Path -LiteralPath $temporario) { Remove-Item -LiteralPath $temporario -Recurse -Force -ErrorAction SilentlyContinue }
}

if (-not $NoPause) { Read-Host "Pressione Enter para fechar" | Out-Null }
exit $exitCode
