[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $username = 'apollo', # Change this to your apollo/sunshine username
    [Parameter()]
    [SecureString]
    $password = $(ConvertTo-SecureString -AsPlainText 'password' -Force), # Only choose to enter your password here at your own risk, otherwise you can enter it in the console when prompted. If its 'password', it will prompt you for the password no matter what.
    [Parameter()]
    [switch]
    $deleteOldGames = $true
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

$excludedNames = @('ms-resource*', 'ms-resource:IDS_Title2', 'ms-resource:AppDisplayName', 'ms-resource:ApplicationDisplayName')

Write-Host "Parsing game configs..." -ForegroundColor Cyan
$xboxApps | ForEach-Object {
    $config = Convert-Config -configPath "$($_.InstallLocation)\MicrosoftGame.config"
    $manifest = Convert-Manifest -manifestPath "$($_.InstallLocation)\appxmanifest.xml"
    $gameName = Remove-UnwantedWords -string $manifest.DisplayName

    # $gameName = $_.Name
    $gameDisplayName = $manifest.VisualElements.DisplayName

    foreach ($excludedName in $excludedNames) {
        if ($gameDisplayName -like $excludedName) {
            $gameDisplayName = $gameName
        }
        if ($gameDisplayName -like $excludedName) {
            $gameDisplayName = $_.Name
        }
    }

    $_ | Add-Member -MemberType NoteProperty -Name gameName -Value $gameName
    $_ | Add-Member -MemberType NoteProperty -Name gameDisplayName -Value $gameDisplayName
    $_ | Add-Member -MemberType NoteProperty -Name config -Value $config
    $_ | Add-Member -MemberType NoteProperty -Name manifest -Value $manifest

}

Write-Host "Game configs parsed!" -ForegroundColor Magenta

$serviceNames = @(
    'SunshineService',
    'ApolloService'
)

$existingServices = Get-Service -Name $serviceNames -ErrorAction SilentlyContinue
$runningService = $existingServices | Where-Object { $_.Status -eq 'Running' }
if ($null -eq $existingServices) {
    Write-Host "Sunshine/Apollo service not found, is it installed and running?" -ForegroundColor Red
    exit
}

if ($existingServices.Count -gt 1) {
    Write-Host "Multiple services found!" -ForegroundColor Yellow
    $servicesRunning = 0
    foreach ($service in $existingServices) {
        if ($service.Status -eq 'Running') {
            $servicesRunning++
        }
    }

    if ($servicesRunning -eq 0) {
        Write-Host "No services running!" -ForegroundColor Yellow
        Write-Host "Please start one of the services and try again" -ForegroundColor Yellow
        exit
    }
    if ($servicesRunning -gt 1) {
        Write-Host "Multiple services running!" -ForegroundColor Yellow
        Write-Host "Please stop and disable one of the services and try again" -ForegroundColor Yellow
        Write-Host $runningService.DisplayName
        exit
    }

    Write-Host "Using service: $($runningService.Name)" -ForegroundColor Green

}

$currentSystemName = $runningService.DisplayName -split ' ' | Select-Object -First 1
Write-Host "Current system: $currentSystemName" -ForegroundColor Green

$serviceInfo = Get-CimInstance win32_service | Where-Object { $_.Name -eq $runningService.Name } | Select-Object Name, DisplayName, PathName
$configPath = Join-Path -Path ( Split-Path -Path (Split-Path -Path $serviceInfo.PathName -Parent) -Parent) -ChildPath 'config'
$configApps = $null
if (Test-Path -Path "$configPath\apps.json") {
    $rawConfig = Get-Content -Path "$configPath\apps.json"
    $configApps = $rawConfig | ConvertFrom-Json
    # $configApps = Get-Content -Path "$configPath\apps.json" | ConvertFrom-Json
}

$excludedApps = @(
    'Desktop',
    'Steam Big Picture',
    'Virtual Desktop'
)

if ($deleteOldGames -and $configApps) {
    $removedGames = 0
    Write-Host "Checking for games to delete..." -ForegroundColor Cyan
    foreach ($existingApp in $configApps.apps) {
        if ($existingApp.name -notin $xboxApps.gameDisplayName -and $existingApp.name -notin $excludedApps) {
            $confirmDelete = Read-Host "Do you want to delete the game: $($existingApp.name)? (Y/N)"
            if ($confirmDelete.ToLower() -ne 'y') {
                continue
            }
            Write-Host "Removing game: $($existingApp.name) from config!" -ForegroundColor Yellow
            
            $configApps.apps = $configApps.apps | Where-Object { $_.name -ne $existingApp.name }
            $removedGames++
        }
    }

    if ($removedGames -gt 0) {
        $newConfig = $configApps | ConvertTo-Json -Depth 10
        $newConfigFileTemp = $env:TEMP + '\apps.json'
        $newConfig | Set-Content -Path $newConfigFileTemp -Force
        # This needs to run as admin then restart the service as admin
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Copy-Item -Path '$configPath\apps.json' -Destination '$configPath\apps.json.bak' -Force; Copy-Item -Path '$newConfigFileTemp' -Destination '$configPath\apps.json' -Force; Restart-Service -Name $($runningService.Name) -Force`"" -Verb RunAs -Wait
        Write-Host "Games removed: $removedGames" -ForegroundColor Green
    }
}

if ($username -eq 'apollo' -and $username -ne $currentSystemName.ToLower()) {
    $username = $currentSystemName.ToLower()
    Write-Host "Username changed to: $username" -ForegroundColor Yellow
}
elseif ($username -eq 'sunshine' -and $username -ne $currentSystemName.ToLower()) {
    $username = $currentSystemName.ToLower()
    Write-Host "Username changed to: $username" -ForegroundColor Yellow
}

if ((ConvertFrom-SecureStringToPlainText -secureString $password) -eq 'password') {
    $password = Read-Host "Please enter your $currentSystemName password for user - $username" -AsSecureString
}

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
    # $script:session = $webSession
    return @{
        cookie  = $cookieValue
        session = $webSession
    }

}

$headers = $null
# $cookie = Test-CookieNeeded
Write-Host "Checking $currentSystemName for games already added..." -ForegroundColor Cyan
$cookieAndSession = Test-CookieNeeded

if ($null -eq $cookieAndSession) {
    $headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($username + ":" + (ConvertFrom-SecureStringToPlainText -secureString $password))) }
}
else {
    $headers = @{Cookie = $cookieAndSession.cookie }
}

$configuredApps = $null
if ($configApps.apps) {
    $configuredApps = $configApps.apps
}
else {
    $currentConfiguredApps = @()
    try {
        $currentConfiguredApps = Invoke-RestMethod `
            -Uri 'https://localhost:47990/api/apps' `
            -Method GET `
            -Headers $headers `
            -SkipCertificateCheck `
            -WebSession $cookieAndSession.session
    }
    catch {
        try {
            Disable-CertificateErrors
            $currentConfiguredApps = Invoke-RestMethod `
                -Uri 'https://localhost:47990/api/apps' `
                -Method GET `
                -Headers $headers `
                -WebSession $cookieAndSession.session
    
        }
        catch {
            Write-Error "Failed to get installed apps from $currentSystemName, $_"
            return
        }
    }


    $configuredApps = $currentConfiguredApps | Select-Object -ExpandProperty apps | Where-Object { $_.name -notin $excludedApps }
}



Write-Host "$currentSystemName games already added: $($configuredApps.Count)" -ForegroundColor Green



$gamesAdded = 0
$gamesDeleted = 0
foreach ($xboxApp in ($xboxApps)) {

    $runName = $xboxApp.name
    $gameName = $xboxApp.gameName
    $gameDisplayName = $xboxApp.gameDisplayName

    $existingApp = $configuredApps | Where-Object { $_.name -eq $gameDisplayName }
    
    if (!$existingApp ) {
        $newApp = @{
            name         = $gameDisplayName
            output       = "$logsPath\$gameName.log"
            cmd          = "powershell.exe -WindowStyle Maximized -executionpolicy bypass -file `"$path\Start-WindowsStoreGame.ps1`" -GameName `"$runName`"" 
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
                -WebSession $cookieAndSession.session
        }
        catch {
            try {
                $newAppResponse = Invoke-RestMethod `
                    -Uri 'https://localhost:47990/api/apps' `
                    -Method POST `
                    -Headers $headers `
                    -Body (ConvertTo-Json $newApp) `
                    -WebSession $cookieAndSession.session
            }
            catch {
                write-error "Failed to add game: $gameDisplayName, $_"
            }
        }
    
        if ($newAppResponse -and $newAppResponse.status -eq 'true') {
            Write-Host "Game added: $gameDisplayName successfully!" -ForegroundColor Green
            $gamesAdded++
        }
        else {
            Write-Host "Failed to add game: $gameDisplayName" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Game already added: $gameDisplayName" -ForegroundColor Yellow
    }
}

if ($gamesDeleted -gt 0) {
    Write-Host "Games deleted: $gamesDeleted" -ForegroundColor Yellow
}

if ($gamesAdded -gt 0) {
    Write-Host "Games added: $gamesAdded" -ForegroundColor Green
}

Write-Host "Script complete!" -ForegroundColor Green

Write-Host "Exiting in 5 seconds..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
