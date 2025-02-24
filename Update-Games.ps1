[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $username = 'sunshine',
    [Parameter()]
    [SecureString]
    $password = $(ConvertTo-SecureString -AsPlainText 'password' -Force) # Only choose to enter your password here at your own risk, otherwise you can enter it in the console when prompted. If its 'password', it will prompt you for the password no matter what.
)

function ConvertFrom-SecureStringToPlainText {
    param (
        [SecureString] $secureString
    )
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Disable-CertificateErrors {
    # Ignore SSL certificate errors
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}


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

$headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($username + ":" + (ConvertFrom-SecureStringToPlainText -secureString $password))) }

$currentInstalledApps = @()
try {
    $currentInstalledApps = Invoke-RestMethod `
        -Uri 'https://localhost:47990/api/apps' `
        -Method GET `
        -Headers $headers `
        -SkipCertificateCheck
}
catch {
    try {
        Disable-CertificateErrors
        $currentInstalledApps = Invoke-RestMethod `
            -Uri 'https://localhost:47990/api/apps' `
            -Method GET `
            -Headers $headers `
    
    }
    catch {
        Write-Error "Failed to get installed apps from sunshine, $_"
        return
    }
}

$installedApps = $currentInstalledApps | Select-Object -ExpandProperty apps

Write-Host "Sunshine games already added: $($installedApps.Count)" -ForegroundColor Green

foreach ($xboxApp in ($xboxApps | Where-Object { $_.gameName -notin $installedApps.name })) {
    $gameName = $xboxApp.gameName

    if ($installedApps | Where-Object { $_.name -eq $gameName }) {
        # Should'nt happen
        Write-Host "Game already added: $gameName" -ForegroundColor Yellow
        continue
    }

    $newApp = @{
        name         = $gameName
        # output = "$logsPath\$gameName.log"
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

    Write-Host "Adding game: $gameName" -ForegroundColor Blue
    $newAppResponse = $null
    try {
        $newAppResponse = Invoke-RestMethod `
            -Uri 'https://localhost:47990/api/apps' `
            -Method POST `
            -Headers $headers `
            -Body (ConvertTo-Json $newApp) `
            -SkipCertificateCheck
    }
    catch {
        try {
            $newAppResponse = Invoke-RestMethod `
                -Uri 'https://localhost:47990/api/apps' `
                -Method POST `
                -Headers $headers `
                -Body (ConvertTo-Json $newApp)
        }
        catch {
            write-error "Failed to add game: $gameName, $_"
        }
    }

    if ($newAppResponse -and $newAppResponse.status -eq 'true') {
        Write-Host "Game added: $gameName successfully!" -ForegroundColor Green
    }
}