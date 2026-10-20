# Xuất SilverCare (ASP.NET MVC) ra HTML tĩnh trong thư mục dist/ để deploy lên Cloudflare Pages.
# Mọi xác thực/dữ liệu chạy phía client qua Supabase nên mỗi View chỉ cần render một lần.
#
# Cách dùng:  powershell -ExecutionPolicy Bypass -File scripts/export-static.ps1
param(
    [int]$Port = 5199,
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$actions = @(
    "Staff", "Family", "Dashboard", "Residents", "Health", "Schedule", "CareLog",
    "Profile", "Report", "Billing", "Notifications", "UserManagement",
    "SystemSettings", "AccessDenied", "LoginSuccess"
)

$out = Join-Path $root $OutDir
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force (Join-Path $out "Home") | Out-Null

Write-Host "Build project..."
dotnet build -c Release --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

$baseUrl = "http://localhost:$Port"
$env:ASPNETCORE_ENVIRONMENT = "Production"
$server = Start-Process dotnet -ArgumentList "run", "-c", "Release", "--no-build", "--no-launch-profile", "--urls", $baseUrl `
    -PassThru -WindowStyle Hidden

try {
    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8

    Write-Host "Waiting for server at $baseUrl ..."
    $ready = $false
    for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
        try { $null = $client.DownloadString("$baseUrl/"); $ready = $true } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $ready) { throw "Server did not start" }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    function Save-Page($path, $file) {
        $html = $client.DownloadString("$baseUrl$path")
        [IO.File]::WriteAllText((Join-Path $out $file), $html, $utf8)
        Write-Host "  $path -> $file"
    }

    Save-Page "/" "index.html"
    foreach ($a in $actions) { Save-Page "/Home/$a" "Home/$a.html" }
}
finally {
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    Get-Process -Name "SilverCare*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "Copy wwwroot..."
Copy-Item -Recurse -Force (Join-Path $root "wwwroot\*") $out

# Cloudflare Pages tự phục vụ /Home/Dashboard từ Home/Dashboard.html.
# Các route MVC không có file tương ứng thì chuyển hướng về trang chủ.
$redirects = @(
    "/Home         /  301",
    "/Home/Index   /  301",
    "/Home/Logout  /  302"
) -join "`n"
[IO.File]::WriteAllText((Join-Path $out "_redirects"), $redirects + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Done -> $out"
