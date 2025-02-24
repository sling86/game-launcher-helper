function Remove-UnwantedWords {
    param (
        [string]$string
    )
    #tm symbol, registered trademark symbol, copyright symbol etc.
    $unwantedWords = @('Microsoft', '- Windows10', 'Windows', 'Xbox', 'Store', 'Game', 'App', 'Appx', 'Launcher', '™' , '®' , '©' )
    $output = $string
    foreach ($word in $unwantedWords) {
        $output = $output -replace $word, ''
    }
    return $output.Trim()
}

function Convert-Config {
    [CmdletBinding()]
    param (
        $configPath
    )

    $infoRaw = Get-Content $configPath -ErrorAction SilentlyContinue
    if ($null -eq $infoRaw) {
        Write-Host "Game config not found"
        return
    }
    $infoXML = [xml]$infoRaw
    $hash = [ordered]@{
        configVersion     = $infoXML.Game.configVersion         
        Identity          = $infoXML.Game.Identity | ForEach-Object { new-Object psobject -Property @{
                Name      = $_.Name
                Publisher = $_.Publisher
                Version   = $_.Version
            } }      

        MSAAppId          = $infoXML.Game.MSAAppId              
        TitleId           = $infoXML.Game.TitleId               
        StoreId           = $infoXML.Game.StoreId               
        AdvancedUserModel = $infoXML.Game.AdvancedUserModel     
        RequiresXboxLive  = $infoXML.Game.RequiresXboxLive
    
        ExecutableList    = $infoXML.Game.ExecutableList.Executable | ForEach-Object { new-Object psobject -Property @{
                Name               = $_.Name
                TargetDeviceFamily = $_.TargetDeviceFamily
                Id                 = $_.Id
            } }

        MainExecutable    = Split-Path $($infoXML.Game.ExecutableList.Executable.Name | Select-Object -First 1) -Leaf

        ShellVisuals      = $infoXML.Game.ShellVisuals | ForEach-Object { new-Object psobject -Property @{
                DefaultDisplayName   = $_.DefaultDisplayName
                PublisherDisplayName = $_.PublisherDisplayName
                StoreLogo            = $_.StoreLogo
                Square150x150Logo    = $_.Square150x150Logo
                Square44x44Logo      = $_.Square44x44Logo
                Description          = $_.Description
                BackgroundColor      = $_.BackgroundColor
                SplashScreenImage    = $_.SplashScreenImage
            } }    

        Resources         = $infoXML.Game.Resources.Resource | ForEach-Object { new-Object psobject -Property @{
                Language = $_.Language
            } }           
        # DesktopRegistration   = $infoXML.Game.DesktopRegistration   
        # ExtendedAttributeList = $infoXML.Game.ExtendedAttributeList 
    }

    return new-object PSObject -Property $hash
    
}

function Convert-Manifest {
    [CmdletBinding()]
    param (
        $manifestPath
    )

    $infoRaw = Get-Content $manifestPath -ErrorAction SilentlyContinue
    if ($null -eq $infoRaw) {
        Write-Host "Game manifest not found"
        return
    }
    $infoXML = [xml]$infoRaw
    $hash = [ordered]@{      

        Name                  = $infoXML.Package.Identity.Name
        Publisher             = $infoXML.Package.Identity.Publisher
        Version               = $infoXML.Package.Identity.Version
        ProcessorArchitecture = $infoXML.Package.Identity.ProcessorArchitecture

        DisplayName           = $infoXML.Package.Properties.DisplayName
        PublisherDisplayName  = $infoXML.Package.Properties.PublisherDisplayName
        Logo                  = $infoXML.Package.Properties.Logo
        Description           = $infoXML.Package.Properties.Description

        ApplicationId         = $infoXML.Package.Applications.Application.Id
        Executable            = $infoXML.Package.Applications.Application.Executable
        EntryPoint            = $infoXML.Package.Applications.Application.EntryPoint    

        VisualElements        = $infoXML.Package.Applications.Application.VisualElements | ForEach-Object { 
            new-Object psobject -Property @{
                DisplayName       = $_.DisplayName
                Square150x150Logo = $_.Square150x150Logo
                Square44x44Logo   = $_.Square44x44Logo
                Description       = $_.Description
                ForegroundText    = $_.ForegroundText
                BackgroundColor   = $_.BackgroundColor
                SplashScreenImage = $_.SplashScreen.Image
            }
        }
    }

    return new-object PSObject -Property $hash
    
}