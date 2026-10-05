# ============================================================
# FOS - Free Open System
# Version 1.1
# Real PlayFab accounts + Page Builder + GitHub uploads
# ============================================================

$ErrorActionPreference = "Stop"

$TitleId = "23EA5"
$GitHubRepo = "https://github.com/JuniHe100/FOS.git"
$MaxFileBytes = 95MB
$MinFileBytes = 10

$script:PlayFabSessionTicket = $null
$script:PlayFabId = $null
$script:CurrentUser = $null
$script:PageMode = $false
$script:CurrentPage = $null

$Data = Join-Path $PSScriptRoot "Data"
$Files = Join-Path $Data "Files"
$Pages = Join-Path $Data "Pages"
$Plugins = Join-Path $Data "Plugins"
$HTML = Join-Path $PSScriptRoot "HTML"
$Music = Join-Path $PSScriptRoot "MUSIC"
$Templates = Join-Path $PSScriptRoot "Templates"

@($Data,$Files,$Pages,$Plugins,$HTML,$Music,$Templates) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

$ConfigPath = Join-Path $PSScriptRoot "PlayFabConfig.json"
@{
    TitleId = $TitleId
    GitHubRepo = $GitHubRepo
    Version = "1.1"
    MaxFileBytes = $MaxFileBytes
    MinFileBytes = $MinFileBytes
} | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8

function Say($Text="") {
    Write-Host $Text
}

function Fail($Text) {
    Write-Host "[ERROR] $Text" -ForegroundColor Red
}

function Good($Text) {
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Parse-Command($Line) {
    $matches = [regex]::Matches($Line, '(?:"([^"]*)"|''([^'']*)''|(\S+))')
    $parts = @()
    foreach ($m in $matches) {
        if ($m.Groups[1].Success) { $parts += $m.Groups[1].Value }
        elseif ($m.Groups[2].Success) { $parts += $m.Groups[2].Value }
        else { $parts += $m.Groups[3].Value }
    }
    return $parts
}

function PlayFab-Request {
    param(
        [string]$Endpoint,
        [hashtable]$Body,
        [switch]$Authenticated
    )

    $Body["TitleId"] = $TitleId
    $uri = "https://$TitleId.playfabapi.com/Client/$Endpoint"

    $headers = @{}
    if ($Authenticated) {
        if ([string]::IsNullOrWhiteSpace($script:PlayFabSessionTicket)) {
            throw "You are not logged in."
        }
        $headers["X-Authorization"] = $script:PlayFabSessionTicket
    }

    try {
        return Invoke-RestMethod `
            -Uri $uri `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json" `
            -Body ($Body | ConvertTo-Json -Depth 20)
    }
    catch {
        $msg = $_.Exception.Message

        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $raw = $reader.ReadToEnd()
            $reader.Close()

            if ($raw) {
                $json = $raw | ConvertFrom-Json
                if ($json.errorMessage) {
                    $msg = $json.errorMessage
                }
                elseif ($json.errorDetails) {
                    $msg = "$($json.errorMessage) $($json.errorDetails | Out-String)"
                }
            }
        } catch {}

        throw $msg
    }
}

function PlayFab-Create($Username,$Password,$Email) {
    if ($Password.Length -lt 6 -or $Password.Length -gt 100) {
        throw "Password must be 6-100 characters."
    }

    if ([string]::IsNullOrWhiteSpace($Email)) {
        throw "Email is required for FOS account creation."
    }

    $body = @{
        Username = $Username
        Password = $Password
        Email = $Email
        RequireBothUsernameAndEmail = $true
        DisplayName = $Username
    }

    $r = PlayFab-Request "RegisterPlayFabUser" $body

    $script:PlayFabSessionTicket = $r.data.SessionTicket
    $script:PlayFabId = $r.data.PlayFabId
    $script:CurrentUser = $Username

    Good "PlayFab account created."
    Say "Username: $Username"
    Say "PlayFab ID: $($script:PlayFabId)"
    Say "Logged in automatically."
}

function PlayFab-Login($Username,$Password) {
    $body = @{
        Username = $Username
        Password = $Password
        InfoRequestParameters = @{
            GetPlayerProfile = $true
        }
    }

    $r = PlayFab-Request "LoginWithPlayFab" $body

    $script:PlayFabSessionTicket = $r.data.SessionTicket
    $script:PlayFabId = $r.data.PlayFabId
    $script:CurrentUser = $Username

    Good "Logged in."
    Say "Username: $Username"
    Say "PlayFab ID: $($script:PlayFabId)"
}

function PlayFab-Logout {
    $script:PlayFabSessionTicket = $null
    $script:PlayFabId = $null
    $script:CurrentUser = $null
    Good "Logged out."
}

function Require-Login {
    if ([string]::IsNullOrWhiteSpace($script:PlayFabSessionTicket)) {
        throw "Log in first."
    }
}

function PlayFab-Profile {
    Require-Login

    $body = @{
        PlayFabId = $script:PlayFabId
    }

    $r = PlayFab-Request "GetPlayerProfile" $body -Authenticated
    $p = $r.data.PlayerProfile

    Say ""
    Say "PROFILE"
    Say "----------------------------"
    Say "Username: $script:CurrentUser"
    Say "PlayFab ID: $($p.PlayerId)"
    Say "Display Name: $($p.DisplayName)"
    Say "Created: $($p.Created)"
    Say "Last Login: $($p.LastLogin)"
    Say "Title ID: $($p.TitleId)"
    Say "----------------------------"
}

function Friend-Command($Args) {
    Require-Login

    if ($Args.Count -lt 1) {
        Say "Usage:"
        Say "/friend add <PlayFabID>"
        Say "/friend remove <PlayFabID>"
        Say "/friend list"
        return
    }

    switch ($Args[0].ToLower()) {
        "add" {
            if ($Args.Count -lt 2) { throw "Usage: /friend add <PlayFabID>" }

            $r = PlayFab-Request "AddFriend" @{
                FriendPlayFabId = $Args[1]
            } -Authenticated

            Good "Friend added."
        }

        "remove" {
            if ($Args.Count -lt 2) { throw "Usage: /friend remove <PlayFabID>" }

            PlayFab-Request "RemoveFriend" @{
                FriendPlayFabId = $Args[1]
            } -Authenticated | Out-Null

            Good "Friend removed."
        }

        "list" {
            $r = PlayFab-Request "GetFriendsList" @{
                IncludeSteamFriends = $false
            } -Authenticated

            Say ""
            Say "FRIENDS"
            Say "----------------------------"

            if (-not $r.data.Friends -or $r.data.Friends.Count -eq 0) {
                Say "No friends found."
            }
            else {
                foreach ($f in $r.data.Friends) {
                    Say "$($f.TitleDisplayName) [$($f.FriendPlayFabId)]"
                }
            }

            Say "----------------------------"
        }

        default {
            throw "Unknown friend command."
        }
    }
}

function New-Page {
    Require-Login

    $name = Read-Host "Page name"
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Page name cannot be empty."
    }

    $safe = $name -replace '[^\w\-]','_'
    $pageDir = Join-Path $Pages $safe

    New-Item -ItemType Directory -Path $pageDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pageDir "PFP") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pageDir "MUSIC") -Force | Out-Null

    $obj = [ordered]@{
        OwnerUsername = $script:CurrentUser
        OwnerPlayFabId = $script:PlayFabId
        Name = $safe
        DisplayName = $script:CurrentUser
        Title = "$script:CurrentUser's Page"
        Bio = ""
        Theme = "dark"
        PFP = ""
        Music = @{
            Name = "Hey Two!"
            Artist = "Anthony Kos"
            Source = "default"
        }
        Socials = @{}
        Created = (Get-Date).ToUniversalTime().ToString("o")
        Published = $false
    }

    $obj | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $pageDir "page.json") -Encoding UTF8

    $script:CurrentPage = $safe
    $script:PageMode = $true

    Good "Page started."
    Say ""
    Say "PAGE BUILDER"
    Say "============================"
    Say "Step 1/8 - Page name"
    Say "Next command:"
    Say "  /page set name <name>"
    Say ""
}

function Get-CurrentPageObject {
    if ([string]::IsNullOrWhiteSpace($script:CurrentPage)) {
        throw "No page is currently selected."
    }

    $path = Join-Path $Pages "$($script:CurrentPage)\page.json"

    if (-not (Test-Path $path)) {
        throw "Page data not found."
    }

    return (Get-Content $path -Raw | ConvertFrom-Json)
}

function Save-PageObject($Obj) {
    $path = Join-Path $Pages "$($script:CurrentPage)\page.json"
    $Obj | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding UTF8
}

function Page-Set($Args) {
    Require-Login

    if ($Args.Count -lt 2) {
        Say "/page set name <name>"
        Say "/page set title <title>"
        Say "/page set bio <text>"
        Say "/page set pfp <file>"
        Say "/page set music <file>"
        Say "/page set theme <theme>"
        Say "/page set social <platform> <url>"
        return
    }

    if (-not $script:CurrentPage) {
        throw "Start a page first with /page start."
    }

    $field = $Args[0].ToLower()
    $value = ($Args[1..($Args.Count-1)] -join " ")

    $p = Get-CurrentPageObject

    switch ($field) {
        "name" {
            $p.DisplayName = $value
            Good "Page display name saved."
            Say "Next: /page set title <title>"
        }

        "title" {
            $p.Title = $value
            Good "Page title saved."
            Say "Next: /page set bio <text>"
        }

        "bio" {
            $p.Bio = $value
            Good "Bio saved."
            Say "Next: /page set pfp <file>"
        }

        "pfp" {
            $file = ($Args[1..($Args.Count-1)] -join " ")

            if (-not (Test-Path $file)) {
                throw "PFP file not found."
            }

            $dest = Join-Path $Pages "$script:CurrentPage\PFP\$([IO.Path]::GetFileName($file))"
            Copy-Item $file $dest -Force
            $p.PFP = "PFP/$([IO.Path]::GetFileName($file))"

            Good "Profile picture saved."
            Say "Next: /page set music <file> OR /page set music default"
        }

        "music" {
            if ($value.ToLower() -eq "default") {
                $p.Music = @{
                    Name = "Hey Two!"
                    Artist = "Anthony Kos"
                    Source = "default"
                }

                Good "Music set to Hey Two! - Anthony Kos."
            }
            else {
                if (-not (Test-Path $value)) {
                    throw "Music file not found."
                }

                $dest = Join-Path $Pages "$script:CurrentPage\MUSIC\$([IO.Path]::GetFileName($value))"
                Copy-Item $value $dest -Force

                $p.Music = @{
                    Name = [IO.Path]::GetFileNameWithoutExtension($value)
                    Artist = ""
                    Source = "MUSIC/$([IO.Path]::GetFileName($value))"
                }

                Good "Music saved."
            }

            Say "Next: /page set theme <theme>"
        }

        "theme" {
            $allowed = @("dark","light","neon","glass","classic")

            if ($allowed -notcontains $value.ToLower()) {
                throw "Themes: dark, light, neon, glass, classic"
            }

            $p.Theme = $value.ToLower()
            Good "Theme saved."
            Say "Next: /page set social <platform> <url>"
        }

        "social" {
            if ($Args.Count -lt 3) {
                throw "Usage: /page set social <platform> <url>"
            }

            $platform = $Args[1]
            $url = $Args[2]

            if ($url -notmatch '^https?://') {
                throw "Social URL must start with http:// or https://"
            }

            if (-not $p.Socials) {
                $p.Socials = @{}
            }

            $p.Socials | Add-Member -NotePropertyName $platform -NotePropertyValue $url -Force

            Good "$platform link saved."
            Say "Add more socials with:"
            Say "  /page set social <platform> <url>"
            Say "When done:"
            Say "  /page finish"
        }

        default {
            throw "Unknown page field."
        }
    }

    Save-PageObject $p
}

function Page-Finish {
    Require-Login

    $p = Get-CurrentPageObject

    $missing = @()

    if ([string]::IsNullOrWhiteSpace($p.DisplayName)) { $missing += "display name" }
    if ([string]::IsNullOrWhiteSpace($p.Title)) { $missing += "title" }
    if ([string]::IsNullOrWhiteSpace($p.Theme)) { $missing += "theme" }

    if ($missing.Count -gt 0) {
        Fail "Page is not ready."
        Say "Missing: $($missing -join ', ')"
        return
    }

    $socialHtml = ""

    if ($p.Socials) {
        foreach ($prop in $p.Socials.PSObject.Properties) {
            $platform = [System.Net.WebUtility]::HtmlEncode([string]$prop.Name)
            $url = [System.Net.WebUtility]::HtmlEncode([string]$prop.Value)

            $socialHtml += "<a class='social' href='$url' target='_blank'>$platform</a>`n"
        }
    }

    $bio = [System.Net.WebUtility]::HtmlEncode([string]$p.Bio)
    $title = [System.Net.WebUtility]::HtmlEncode([string]$p.Title)
    $display = [System.Net.WebUtility]::HtmlEncode([string]$p.DisplayName)
    $theme = [System.Net.WebUtility]::HtmlEncode([string]$p.Theme)

    $musicName = [System.Net.WebUtility]::HtmlEncode([string]$p.Music.Name)
    $musicArtist = [System.Net.WebUtility]::HtmlEncode([string]$p.Music.Artist)

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title>
<style>
body{margin:0;font-family:Arial,sans-serif;background:#111;color:white;min-height:100vh;display:flex;align-items:center;justify-content:center}
.card{width:min(700px,90%);padding:40px;border-radius:25px;background:#1b1b1b;text-align:center;box-shadow:0 20px 60px #000}
h1{font-size:42px;margin:10px}
.bio{opacity:.8;font-size:18px;margin:20px}
.social{display:inline-block;margin:6px;padding:10px 16px;border-radius:12px;background:#333;color:white;text-decoration:none}
.music{margin-top:25px;padding:15px;border-radius:15px;background:#252525}
.theme{font-size:12px;opacity:.5}
</style>
</head>
<body>
<div class="card">
<div class="theme">$theme</div>
<h1>$display</h1>
<h2>$title</h2>
<div class="bio">$bio</div>
<div>$socialHtml</div>
<div class="music">
Music: <b>$musicName</b><br>
Artist: $musicArtist
</div>
</div>
</body>
</html>
"@

    $pagePath = Join-Path $Pages $script:CurrentPage
    $html | Set-Content (Join-Path $pagePath "index.html") -Encoding UTF8

    $p.Published = $false
    Save-PageObject $p

    Good "PAGE COMPLETE!"
    Say "index.html generated."
    Say "page.json saved."
    Say ""
    Say "Open:     /page open"
    Say "Publish:  /page publish"

    $script:PageMode = $false
}

function Page-Open {
    if (-not $script:CurrentPage) {
        $pages = Get-ChildItem $Pages -Directory
        if ($pages.Count -eq 0) {
            throw "No pages exist."
        }

        Say "Pages:"
        foreach ($x in $pages) { Say " - $($x.Name)" }

        $pick = Read-Host "Page name"
        $script:CurrentPage = $pick
    }

    $file = Join-Path $Pages "$script:CurrentPage\index.html"

    if (-not (Test-Path $file)) {
        throw "Finish the page first with /page finish."
    }

    Start-Process $file
    Good "Page opened."
}

function Page-List {
    $pages = Get-ChildItem $Pages -Directory

    if ($pages.Count -eq 0) {
        Say "No pages."
        return
    }

    Say ""
    Say "PAGES"
    Say "----------------------------"

    foreach ($dir in $pages) {
        $json = Join-Path $dir.FullName "page.json"

        if (Test-Path $json) {
            $p = Get-Content $json -Raw | ConvertFrom-Json
            Say "$($dir.Name) - $($p.DisplayName)"
        }
        else {
            Say $dir.Name
        }
    }
}

function Page-Delete {
    Require-Login

    $name = if ($Args.Count -gt 0) { $Args[0] } else { Read-Host "Page name" }
    $dir = Join-Path $Pages $name

    if (-not (Test-Path $dir)) {
        throw "Page not found."
    }

    Remove-Item $dir -Recurse -Force
    Good "Page deleted."
}

function Page-Publish {
    Require-Login

    if (-not $script:CurrentPage) {
        throw "Select/start a page first."
    }

    $p = Get-CurrentPageObject
    $p.Published = $true
    Save-PageObject $p

    Good "Page marked as published."
    Say "The page files are ready in:"
    Say "  Data\Pages\$script:CurrentPage"
}

function Page-Unpublish {
    Require-Login

    if (-not $script:CurrentPage) {
        throw "Select a page first."
    }

    $p = Get-CurrentPageObject
    $p.Published = $false
    Save-PageObject $p

    Good "Page unpublished."
}

function Page-Edit {
    Require-Login

    if (-not $script:CurrentPage) {
        $pages = Get-ChildItem $Pages -Directory

        if ($pages.Count -eq 0) {
            throw "No pages exist."
        }

        Say "Available pages:"
        foreach ($x in $pages) { Say " - $($x.Name)" }

        $script:CurrentPage = Read-Host "Page name"
    }

    $script:PageMode = $true

    Say ""
    Say "PAGE EDITOR"
    Say "Page:/>"
    Say ""
    Say "/page set name <name>"
    Say "/page set title <title>"
    Say "/page set bio <text>"
    Say "/page set pfp <file>"
    Say "/page set music <file|default>"
    Say "/page set theme <theme>"
    Say "/page set social <platform> <url>"
    Say "/page finish"
}

function Upload-File($Path,$DetailsPath) {
    Require-Login

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "File not found."
    }

    if (-not (Test-Path $DetailsPath -PathType Leaf)) {
        throw "Details.txt not found."
    }

    $item = Get-Item $Path

    if ($item.Length -lt $MinFileBytes) {
        throw "File is smaller than $MinFileBytes bytes."
    }

    if ($item.Length -gt $MaxFileBytes) {
        throw "File is larger than 95 MB."
    }

    $id = "FOS-" + ([guid]::NewGuid().ToString("N").Substring(0,8).ToUpper())
    $dir = Join-Path $Files $id

    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    Copy-Item $Path (Join-Path $dir $item.Name) -Force
    Copy-Item $DetailsPath (Join-Path $dir "Details.txt") -Force

    @{
        ID = $id
        OwnerUsername = $script:CurrentUser
        OwnerPlayFabId = $script:PlayFabId
        FileName = $item.Name
        Size = $item.Length
        Created = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content (Join-Path $dir "metadata.json") -Encoding UTF8

    Good "Upload prepared."
    Say "ID: $id"

    Push-Git "upload $id"
}

function Push-Git($Message="FOS update") {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is not installed."
    }

    git rev-parse --is-inside-work-tree *> $null

    if ($LASTEXITCODE -ne 0) {
        git init | Out-Null
    }

    $remote = git remote get-url origin 2>$null

    if (-not $remote) {
        git remote add origin $GitHubRepo
    }
    elseif ($remote -ne $GitHubRepo) {
        git remote set-url origin $GitHubRepo
    }

    git add --all

    if ($LASTEXITCODE -ne 0) {
        throw "git add failed."
    }

    git diff --cached --quiet

    if ($LASTEXITCODE -eq 0) {
        Say "Nothing new to commit."
        return
    }

    git commit -m "FOS: $Message"

    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed."
    }

    git branch -M main
    git push -u origin main

    if ($LASTEXITCODE -ne 0) {
        throw "git push failed. GitHub authentication may be required."
    }

    Good "GitHub push complete."
}

function Show-Help {
    Say ""
    Say "FOS COMMANDS"
    Say "================================================"
    Say "/create <username> <password> <email>"
    Say "/login <username> <password>"
    Say "/logout"
    Say "/whoami"
    Say "/profile"
    Say "/friend add <PlayFabID>"
    Say "/friend remove <PlayFabID>"
    Say "/friend list"
    Say ""
    Say "/upload <file> <Details.txt>"
    Say "/page start"
    Say "/page edit"
    Say "/page open"
    Say "/page list"
    Say "/page delete <name>"
    Say "/page publish"
    Say "/page unpublish"
    Say "/page set name <name>"
    Say "/page set title <title>"
    Say "/page set bio <text>"
    Say "/page set pfp <file>"
    Say "/page set music <file|default>"
    Say "/page set theme <dark|light|neon|glass|classic>"
    Say "/page set social <platform> <url>"
    Say "/page finish"
    Say ""
    Say "/git status"
    Say "/git push"
    Say "/template"
    Say "/plugin list"
    Say "/clear"
    Say "/version"
    Say "/about"
    Say "/help"
    Say "/exit"
    Say "================================================"
}

function Show-Banner {
    Clear-Host
    Say "========================================"
    Say "             FOS v1.1"
    Say "       Free Open System"
    Say "========================================"
    Say "Connected to PlayFab Title: $TitleId"
    Say ""
}

function Show-WhoAmI {
    if ($script:CurrentUser) {
        Say "Username: $script:CurrentUser"
        Say "PlayFab ID: $script:PlayFabId"
    }
    else {
        Say "Not logged in."
    }
}

Show-Banner

while ($true) {

    if ($script:PageMode) {
        $prompt = "Page:/> "
    }
    else {
        $prompt = "FOS:/> "
    }

    $line = Read-Host $prompt

    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    try {
        $a = Parse-Command $line

        if ($a.Count -eq 0) {
            continue
        }

        $cmd = $a[0].ToLower()
        $args = if ($a.Count -gt 1) { @($a[1..($a.Count-1)]) } else { @() }

        if ($script:PageMode -and $cmd -eq "/page") {

            if ($args.Count -eq 0) {
                Say "/page set ... | /page finish | /page done"
                continue
            }

            switch ($args[0].ToLower()) {
                "set" {
                    Page-Set $args[1..($args.Count-1)]
                }

                "finish" {
                    Page-Finish
                }

                "done" {
                    Page-Finish
                }

                "edit" {
                    Page-Edit
                }

                "open" {
                    Page-Open
                }

                default {
                    Fail "Unknown Page command."
                }
            }

            continue
        }

        switch ($cmd) {

            "/create" {
                if ($args.Count -lt 3) {
                    Say "Usage: /create <username> <password> <email>"
                    break
                }

                PlayFab-Create $args[0] $args[1] $args[2]
            }

            "/login" {
                if ($args.Count -lt 2) {
                    Say "Usage: /login <username> <password>"
                    break
                }

                PlayFab-Login $args[0] $args[1]
            }

            "/logout" {
                PlayFab-Logout
            }

            "/whoami" {
                Show-WhoAmI
            }

            "/profile" {
                PlayFab-Profile
            }

            "/view" {
                if ($args.Count -ge 2 -and $args[0].ToLower() -eq "profile" -and $args[1].ToLower() -eq "me") {
                    PlayFab-Profile
                }
                else {
                    Say "Usage: /view Profile me"
                }
            }

            "/friend" {
                Friend-Command $args
            }

            "/upload" {
                if ($args.Count -lt 2) {
                    Say "Usage: /upload <file> <Details.txt>"
                    break
                }

                Upload-File $args[0] $args[1]
            }

            "/page" {
                if ($args.Count -eq 0) {
                    Say "/page start"
                    Say "/page edit"
                    Say "/page open"
                    Say "/page list"
                    Say "/page delete <name>"
                    Say "/page publish"
                    Say "/page unpublish"
                    break
                }

                switch ($args[0].ToLower()) {
                    "start" {
                        New-Page
                    }

                    "edit" {
                        Page-Edit
                    }

                    "open" {
                        Page-Open
                    }

                    "list" {
                        Page-List
                    }

                    "delete" {
                        Page-Delete
                    }

                    "publish" {
                        Page-Publish
                    }

                    "unpublish" {
                        Page-Unpublish
                    }

                    "set" {
                        Page-Set $args[1..($args.Count-1)]
                    }

                    "finish" {
                        Page-Finish
                    }

                    "done" {
                        Page-Finish
                    }

                    default {
                        Fail "Unknown page command."
                    }
                }
            }

            "/git" {
                if ($args.Count -eq 0) {
                    Say "/git status"
                    Say "/git push"
                    break
                }

                switch ($args[0].ToLower()) {
                    "status" {
                        git status
                    }

                    "push" {
                        Push-Git "manual push"
                    }

                    default {
                        Say "/git status"
                        Say "/git push"
                    }
                }
            }

            "/template" {
                $template = Join-Path $Templates "Page.html"

                @"
<!DOCTYPE html>
<html>
<head>
<title>My FOS Page</title>
</head>
<body>
<h1>My FOS Page</h1>
<p>Made with FOS.</p>
</body>
</html>
"@ | Set-Content $template -Encoding UTF8

                Good "Page template created:"
                Say $template
            }

            "/plugin" {
                if ($args.Count -eq 0 -or $args[0].ToLower() -eq "list") {
                    $items = Get-ChildItem $Plugins -File -ErrorAction SilentlyContinue
                    if (-not $items) {
                        Say "No plugins installed."
                    }
                    else {
                        foreach ($x in $items) {
                            Say $x.Name
                        }
                    }
                }
                else {
                    Say "Plugin command available for local FOS plugins."
                }
            }

            "/clear" {
                Clear-Host
            }

            "/version" {
                Say "FOS v1.1"
            }

            "/about" {
                Say "FOS - Free Open System"
                Say "PlayFab Title: $TitleId"
                Say "GitHub: $GitHubRepo"
            }

            "/help" {
                Show-Help
            }

            "/exit" {
                break
            }

            default {
                Fail "Unknown command. Type /help."
            }
        }
    }
    catch {
        Fail $_.Exception.Message
    }
}
