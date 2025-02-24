[CmdletBinding()]
param (
    [Parameter()]
    [string]$GameName = "HOT WHEELS UNLEASHED 2 - Turbocharged"
)

$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path

$logsPath = "$path\Logs"
if (-not (Test-Path $logsPath)) {
    New-Item -Path $logsPath -ItemType Directory
}

$dateNow = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

Start-Transcript -Path "$logsPath\$GameName-$dateNow.log"

try {
    . .\Helpers.ps1

    $games = Get-StartApps -Name $GameName
    if ($games.Count -eq 0) {
        Write-Host "No games found with name '$GameName'"
        return
    }

    if ($games.Count -gt 1) {
        Write-Host "Multiple games found with name '$GameName'"
        return
    }

    $game = $games[0]

    $appIdSplit = $game.AppID.Split("!")

    $packageName = $appIdSplit[0]

    $appXInfo = Get-AppxPackage | Where-Object { $_.PackageFullName -eq $packageName -or $_.PackageFamilyName -eq $packageName } `
    | Select-Object -Property Name, PackageFullName, PackageFamilyName, @{
        Name       = 'InstallLocation'
        Expression = {
            If ((Get-Item $_.InstallLocation).LinkType -eq 'Junction') {
          (Get-Item $_.InstallLocation).Target
            }
            Else { $_.InstallLocation }
        }
    }

    if ($null -eq $appXInfo) {
        Write-Host "Game not found in AppxPackages"
        return
    }

    $gameInfo = Convert-Config -configPath "$($appXInfo.InstallLocation)\MicrosoftGame.config"
    $manifestInfo = Convert-Manifest -manifestPath "$($appXInfo.InstallLocation)\appxmanifest.xml"

    if (!$gameInfo.ExecutableList) {
        Write-Host "No executables found"
        return
    }

    Write-Host "Starting game: $($gameInfo.Name)..." -ForegroundColor Cyan
    Write-Host "=========== Game Info ==========="
    $gameInfo
    Write-Host "================================="
    Write-Host
    Write-Host "========= Manifest Info ========="
    $manifestInfo
    Write-Host "================================="

    $mainExe = $gameInfo.MainExecutable

    if (!$mainExe) {
        Write-Host "No main executable found"
        return
    }
    else {
        Write-Host "Starting $mainExe..." -ForegroundColor Cyan
    }

    $otherExes = Get-ChildItem -Path "$($appXInfo.InstallLocation)" -Filter "*.exe" -Recurse | Where-Object { $_.Name -ne $mainExe }
    if ($otherExes.Count -gt 0) {
        Write-Host "Other executables found:"
        $otherExes | Select-Object Name, FullName | Format-Table #| ForEach-Object { Write-Host $_.Name }
    }

    $exesRun = @()

    $gameStart = Start-Process -FilePath explorer.exe -ArgumentList "shell:AppsFolder\$($game.AppID)" -PassThru
    while ($gameStart.HasExited -eq $false) {
        Start-Sleep -Seconds 1
    }

    $gameProcess = $null
    $maxAttempts = 100
    $attempts = 0
    while ($null -eq $gameProcess -and $attempts -lt $maxAttempts) {
        $attempts++
        $gameProcess = Get-Process -Name ($mainExe -replace '.exe', '') -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    if ($null -eq $gameProcess) {
        Write-Host "Main game process ($mainExe) not found" -ForegroundColor Red
        return
    }
    
    write-host "Game process found: $($gameProcess.Name) - [$($gameProcess.Id)]" -ForegroundColor Green
    Wait-Process -Id $gameProcess.Id -ErrorAction SilentlyContinue
    
    if ($gameProcess.ExitCode) {
        "Game Process $($gameProcess.Name) ($($gameProcess.Id)) exited with code $($gameProcess.ExitCode)"
        exit $gameProcess.ExitCode
    }

    $exesRun += $mainExe

    if ($otherExes.Count -gt 0) {
        $otherExes | ForEach-Object {
            $exeName = $_.Name
            $exeProcess = $null
            $maxAttempts = 2
            $attempts = 0
            while ($null -eq $exeProcess -and $attempts -lt $maxAttempts) {
                $attempts++
                $exeProcess = Get-Process -Name ($exeName -replace '.exe', '') -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
            if ($null -eq $exeProcess) {
                Write-Host "Game process ($exeName) not found" -ForegroundColor Magenta
                return
            }
            write-host "Game process found: $($exeProcess.Name) - [$($exeProcess.Id)]" -ForegroundColor Green
            Wait-Process -Id $exeProcess.Id -ErrorAction SilentlyContinue
            if ($exeProcess.ExitCode) {
                "Game process $($exeProcess.Name) ($($exeProcess.Id)) exited with code $($exeProcess.ExitCode)"
                # exit $exeProcess.ExitCode
            }
            $exesRun += $exeName
        }
    }
}
catch {
    Write-Error $_

}
finally {
    Stop-Transcript
}

