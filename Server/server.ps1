$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Config = Get-Content (Join-Path $Root "Server\config.json") -Raw | ConvertFrom-Json

$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add("http://$($Config.Host):$($Config.Port)/")
$Listener.Start()

Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host " FOS LOCAL SERVER v1.0" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Listening on http://$($Config.Host):$($Config.Port)/"
Write-Host "Press CTRL+C to stop."
Write-Host ""

function Send-Response($Context, $Status, $Body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $Status
    $Context.Response.ContentType = "application/json"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes,0,$bytes.Length)
    $Context.Response.OutputStream.Close()
}

while ($Listener.IsListening) {
    try {
        $Context = $Listener.GetContext()
        $Path = $Context.Request.Url.AbsolutePath

        switch ($Path) {
            "/" {
                Send-Response $Context 200 '{"name":"FOS","version":"1.0","status":"online"}'
            }
            "/api/status" {
                Send-Response $Context 200 '{"status":"online","server":"FOS Local Server"}'
            }
            "/api/help" {
                Send-Response $Context 200 '{"commands":["create","login","upload","load","view","page","template","chat","server","plugin","settings"]}'
            }
            default {
                Send-Response $Context 404 '{"error":"Unknown FOS API endpoint"}'
            }
        }
    }
    catch {
        Write-Host $_ -ForegroundColor Red
    }
}
