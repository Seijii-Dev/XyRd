# Official game preparation on a dedicated self-hosted Windows desktop only.
# No VM spoofing, anti-cheat bypass, copied commercial game or license bypass.
$XyTag='RdpFree:games'
. "$PSScriptRoot/lib-common.ps1"
$games=@{}
$hosted=$env:RDPFREE_RUNNER -ne 'self-hosted'
$os=Get-CimInstance Win32_OperatingSystem
$server=[int]$os.ProductType -ne 1
$cs=Get-CimInstance Win32_ComputerSystem
$dir='C:\Users\Public\Desktop\RdpFree Installers'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Prepare-Installer([string]$Url,[string]$Name,[string]$Publisher) {
  $file=Join-Path $dir $Name
  if (-not (Get-File $Url $file 120)) { return @{status='download_failed';note='Redownload from the official website';path=''} }
  $sig=Get-AuthenticodeSignature $file
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $Publisher) { Remove-Item $file -Force -ErrorAction SilentlyContinue;return @{status='signature_failed';note='Installer not run because signature is invalid';path=''} }
  return @{status='installer_ready';path=$file;note='Open the installer in a Windows session, sign in with a licensed account, then test the game. This does not mean the game will run.'}
}
foreach ($game in @('roblox','minecraft_java','minecraft_bedrock')) {
  $enabled=[Environment]::GetEnvironmentVariable($game.ToUpper()) -eq 'ya'
  if (-not $enabled) { $games[$game]=@{status='disabled';note='Not selected'};continue }
  if ($hosted) { $games[$game]=@{status='requires_self_hosted';note='Game preparation is only for your dedicated self-hosted Windows machine.'};continue }
  switch ($game) {
    'roblox' {
      $games[$game]=Prepare-Installer 'https://setup.rbxcdn.com/RobloxPlayerInstaller.exe' 'RobloxPlayerInstaller.exe' 'Roblox'
      $games[$game].compatibility=$(if ($cs.HypervisorPresent) {'Hypervisor detected. Roblox may reject this environment; there is no bypass.'} else {'DirectX/GPU testing and Roblox login are required; not guaranteed by the installer.'})
    }
    'minecraft_java' {
      $games[$game]=Prepare-Installer 'https://launcher.mojang.com/download/MinecraftInstaller.msi' 'MinecraftInstaller.msi' 'Microsoft|Mojang'
      $games[$game].compatibility='The official launcher manages the Java runtime. A licensed account and OpenGL/GPU support are still required.'
    }
    'minecraft_bedrock' {
      $store=Get-AppxPackage -AllUsers -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
      if ($server -or -not $store) { $games[$game]=@{status='unsupported_environment';note='Bedrock requires a Windows desktop with Microsoft Store/Xbox. Windows Server is not a supported target for this setup.'} }
      else {
        "[InternetShortcut]`r`nURL=https://www.minecraft.net/download" | Set-Content (Join-Path $dir 'Minecraft Bedrock.url')
        $games[$game]=@{status='store_required';note='Open the official Minecraft link, install via the Store, then sign in with a licensed account. Not installed or tested automatically.'}
      }
    }
  }
}
$st=Read-Status
if ($env:SAMP -eq 'ya' -and $hosted) { $games.samp=@{status='requires_self_hosted';note='Game installation only on a dedicated self-hosted machine.'} }
elseif ($st.samp) { $games.samp=@{status=$st.samp.status;note=$st.samp.note;game_dir=$st.samp.game_dir;gta_installed=$st.samp.gta_installed;samp_installed=$st.samp.samp_installed} }
else { $games.samp=@{status='disabled';note='Not selected'} }
Update-Status @{games=$games;game_environment=@{os=$os.Caption;windows_server=$server;hypervisor_present=[bool]$cs.HypervisorPresent;runner=$env:RDPFREE_RUNNER;play_tested=$false}} | Out-Null
Log 'Game preparation status written. Does not claim the games have been successfully run.'