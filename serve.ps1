# Minimal static server for the scenario viewer: http://localhost:8765/
param([int]$Port = 8765, [string]$Root = (Join-Path $PSScriptRoot 'site'))
$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.png' = 'image/png'; '.json' = 'application/json'; '.jpg' = 'image/jpeg'; '.svg' = 'image/svg+xml' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "serving $Root at http://localhost:$Port/"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if (-not $rel) { $rel = 'index.html' }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $rel))
    if ($path.StartsWith([IO.Path]::GetFullPath($Root)) -and (Test-Path $path -PathType Leaf)) {
        $bytes = [IO.File]::ReadAllBytes($path)
        $ext = [IO.Path]::GetExtension($path).ToLower()
        $ctx.Response.ContentType = $(if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' })
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else { $ctx.Response.StatusCode = 404 }
    $ctx.Response.Close()
}
