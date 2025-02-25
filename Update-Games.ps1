[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $username = 'apollo', # Change this to your apollo/sunshine username
    [Parameter()]
    [SecureString]
    $password = $(ConvertTo-SecureString -AsPlainText 'password' -Force) # Only choose to enter your password here at your own risk, otherwise you can enter it in the console when prompted. If its 'password', it will prompt you for the password no matter what.
)

$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
$logsPath = "$path\Logs"
if (-not (Test-Path $logsPath)) {
    New-Item -Path $logsPath -ItemType Directory
}

. .\Helpers.ps1

Write-Host "Scanning for installed Xbox games..." -ForegroundColor Cyan

$xboxApps = Get-AppxPackage | Select-Object `
    Name, PackageFullName, PackageFamilyName, @{l = 'InstallLocation'; e = {
        # Return the junction target instead of the local install folder
        If ((Get-Item $_.InstallLocation).LinkType -eq 'Junction') {
          (Get-Item $_.InstallLocation).Target
        }
        Else { $_.InstallLocation }
    }
} | Where-Object { Test-Path "$($_.InstallLocation)\MicrosoftGame.config" } # Filter to Xbox games

if ($xboxApps.Count -eq 0) {
    Write-Host "No Xbox games found" -ForegroundColor Yellow
    return
}
else {
    Write-Host "Found $($xboxApps.Count) Xbox games" -ForegroundColor Green
}

Write-Host "Parsing game configs..." -ForegroundColor Cyan
$xboxApps | ForEach-Object {
    $config = Convert-Config -configPath "$($_.InstallLocation)\MicrosoftGame.config"
    $manifest = Convert-Manifest -manifestPath "$($_.InstallLocation)\appxmanifest.xml"
    $gameName = Remove-UnwantedWords -string $manifest.DisplayName

    $_ | Add-Member -MemberType NoteProperty -Name gameName -Value $gameName
    $_ | Add-Member -MemberType NoteProperty -Name config -Value $config
    $_ | Add-Member -MemberType NoteProperty -Name manifest -Value $manifest
}

Write-Host "Game configs parsed!" -ForegroundColor Magenta

if ((ConvertFrom-SecureStringToPlainText -secureString $password) -eq 'password') {
    $password = Read-Host "Please enter your sunshine password for user - $username" -AsSecureString
}

Write-Host "Checking sunshine for games already added..." -ForegroundColor Cyan

$session = $null
function Test-CookieNeeded {
    $cookieValue = $null
    try {
        $response = Invoke-WebRequest -Method Post -Uri "https://localhost:47990/api/login" `
            -Body (@{username = $username; password = (ConvertFrom-SecureStringToPlainText -secureString $password) } | ConvertTo-Json -Depth 1) `
            -ContentType "application/json" `
            -SkipCertificateCheck -SessionVariable webSession
  
        # Extract the 'Set-Cookie' header from the response
        $setCookie = $response.Headers["Set-Cookie"]
        # Print the cookie to the console
        $cookieValue = $setCookie -split ';' | Select-Object -First 1
    }
    catch {
        try {
            Disable-CertificateErrors
            $response = Invoke-WebRequest -Method Post -Uri "https://localhost:47990/api/login" `
                -Body (@{username = $username; password = (ConvertFrom-SecureStringToPlainText -secureString $password) } | ConvertTo-Json -Depth 1) `
                -ContentType "application/json" ` -SessionVariable webSession
                
            $setCookie = $response.Headers["Set-Cookie"]
            $cookieValue = $setCookie -split ';' | Select-Object -First 1
        }
        catch {
            Write-Error "Failed to get cookie, $_"
            return $null
        }
    }
    $script:session = $webSession
    return $cookieValue

}

$headers = $null
$cookie = Test-CookieNeeded

if ($null -eq $cookie) {
    $headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($username + ":" + (ConvertFrom-SecureStringToPlainText -secureString $password))) }
}
else {
    $headers = @{Cookie = $cookie }
}

$currentInstalledApps = @()
try {
    $currentInstalledApps = Invoke-RestMethod `
        -Uri 'https://localhost:47990/api/apps' `
        -Method GET `
        -Headers $headers `
        -SkipCertificateCheck `
        -WebSession $session
}
catch {
    try {
        Disable-CertificateErrors
        $currentInstalledApps = Invoke-RestMethod `
            -Uri 'https://localhost:47990/api/apps' `
            -Method GET `
            -Headers $headers `
            -WebSession $session
    
    }
    catch {
        Write-Error "Failed to get installed apps from sunshine, $_"
        return
    }
}

$installedApps = $currentInstalledApps | Select-Object -ExpandProperty apps

Write-Host "Sunshine games already added: $($installedApps.Count)" -ForegroundColor Green

$excludedNames = @('ms-resource:AppDisplayName', 'ms-resource:ApplicationDisplayName')

$gamesAdded = 0
foreach ($xboxApp in ($xboxApps | Where-Object { $_.manifest.VisualElements.DisplayName -notin $installedApps.name })) {
    $gameName = $xboxApp.Name
    $gameDisplayName = $xboxApp.manifest.VisualElements.DisplayName
    if ($gameDisplayName -in $excludedNames) {
        $gameDisplayName = $xboxApp.gameName
    }

    if ($installedApps | Where-Object { $_.name -eq $gameDisplayName }) {
        # Should'nt happen
        Write-Host "Game already added: $gameDisplayName" -ForegroundColor Yellow
        continue
    }

    $newApp = @{
        name         = $gameDisplayName
        output       = "$logsPath\$gameName.log"
        cmd          = "powershell.exe -executionpolicy bypass -file `"$path\Start-WindowsStoreGame.ps1`" -GameName `"$gameName`"" 
        index        = -1
        # 'exclude-global-prep-cmd' = $false
        # elevated = $false
        # 'auto-detach' = $true
        # 'wait-all' = $true
        # 'exit-timeout' = 5
        'prep-cmd'   = @(
            #     @{
            #         do = "powershell.exe -executionpolicy bypass -file "" -GameName $gameName -Prep"
            #         undo = "powershell.exe -executionpolicy bypass -file "" -GameName $gameName -Unprep"
            #         elevated = $false
            #     }
        )
        'detached'   = @(
            #     "powershell.exe -executionpolicy bypass -file "" -GameName $gameName -Start"
        )
        'image-path' = (Join-Path -Path $xboxApp.InstallLocation -ChildPath $xboxApp.manifest.Logo)
    }

    Write-Host "Adding game: $gameDisplayName" -ForegroundColor Blue
    $newAppResponse = $null
    try {
        $newAppResponse = Invoke-RestMethod `
            -Uri 'https://localhost:47990/api/apps' `
            -Method POST `
            -Headers $headers `
            -Body (ConvertTo-Json $newApp) `
            -SkipCertificateCheck `
            -WebSession $session
    }
    catch {
        try {
            $newAppResponse = Invoke-RestMethod `
                -Uri 'https://localhost:47990/api/apps' `
                -Method POST `
                -Headers $headers `
                -Body (ConvertTo-Json $newApp) `
                -WebSession $session
        }
        catch {
            write-error "Failed to add game: $gameDisplayName, $_"
        }
    }

    if ($newAppResponse -and $newAppResponse.status -eq 'true') {
        Write-Host "Game added: $gameDisplayName successfully!" -ForegroundColor Green
        $gamesAdded++
    }
}

Write-Host "Games added: $gamesAdded" -ForegroundColor Green