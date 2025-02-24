# Moonlight/Sunshine Game launcher Helper

This repository currently contains PowerShell scripts to manage and launch Xbox games installed from the Windows Store using Sunshine.

## Scripts

### Update-Games.ps1

This script scans for installed Xbox games, parses their configurations, and adds them to Sunshine.

#### Parameters

- `username`: The username for Sunshine authentication. Default is 'sunshine'.
- `password`: The password for Sunshine authentication. Default is 'password'. If the default password is used, the script will prompt for the password.

#### Usage

Run `UpdateGames.cmd` or...

- Using default `sunshine` user and prompt for password.

  ```powershell
  .\Update-Games.ps1
  ```

- Using alternative username and prompt for password.

  ```powershell
  .\Update-Games.ps1 -username 'your_username'
  ```

- Using alternative username and password.

  Powershell 7+

  ```powershell
  .\Update-Games.ps1 -username 'your_username' -password (ConvertTo-SecureString -AsPlainText 'your_password' -Force)
  ```

  Powershell 5+

  ```powershell
  $password = Read-Host -AsSecureString
  .\Update-Games.ps1 -username 'your_username' -password $password
  ```

### Helpers.ps1

This script contains helper functions used by the other scripts.

- `Remove-UnwantedWords`: Removes unwanted words from a string.
- `Convert-Config`: Converts a game configuration file to a PowerShell object.
- `Convert-Manifest`: Converts a game manifest file to a PowerShell object.

## Logs

Logs are stored in the `Logs` directory within the script's directory.

## Requirements

- PowerShell
- Sunshine

## Notes

- Ensure that Sunshine is running and accessible at `https://localhost:47990`.
- The scripts assume that the game configurations and manifests are located in the game's installation directory.
- You only need to run the `Update-Games.ps1` script. The `Start-WindowsStoreGame.ps1` script is added to Sunshine and executed with the game name when loaded via Moonlight.
- The updater will prompt for a password if the script is still using the default. The script will add an application entry for each game not already added with a command that will run the start script, which checks to see if the executables are loaded so Moonlight doesn't close too early.
