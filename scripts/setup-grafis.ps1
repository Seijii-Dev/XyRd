# ============================================================================
#  setup-grafis.ps1 — "GPU software" for RDP sessions on runners WITHOUT a physical GPU.
#
#  GitHub runners don't have a GPU: the only adapter = Microsoft Basic Render
#  Driver (WARP / Direct3D software). This script installs SOFTWARE renderers
#  so applications that require OpenGL/Vulkan/DirectX can still run:
#    - Mesa3D llvmpipe  -> OpenGL 4.5+/4.6 core software (installed system-wide)
#    - Mesa3D lavapipe  -> Vulkan (CPU) via VK_DRIVER_FILES
#    - WARP (D3D11/D3D12) is built into Windows
#  All CPU-based: suitable for lightweight 2D apps & tools needing GL/Vulkan
#  contexts; heavy 3D games / GPU video rendering will remain slow (no
#  NVENC, no VRAM). This VM is ephemeral, so replacing system opengl32.dll
#  is not permanent (and the original is backed up to C:\XyRDP\grafis\orig).
# ============================================================================
$XyTag = 'XyRDP:grafis'
. "$PSScriptRoot/lib-common.ps1"

$root = 'C:\XyRDP\grafis'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$bkp = Join-Path $root 'orig'
New-Item -ItemType Directory -Force -Path $bkp | Out-Null

$gMode = 'software'; $gMesa = ''; $gOpenGL = ''; $gVulkan = ''
$gAdapters = ''; $gNote = ''

# ---- 1) current adapters (evidence of no physical GPU) --------------------
try {
  $ad = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { "$($_.Name)" })
  $gAdapters = ($ad -join ' | ')
} catch { $gAdapters = '' }
Log "  adapter grafis: $(if ($gAdapters) { $gAdapters } else { '(tidak terbaca)' })"

# ---- 2) download Mesa3D (pal1000/mesa-dist-win, MSVC build) ----------------
$asset = Get-GhAssetUrl 'pal1000/mesa-dist-win' 'mesa3d-.*-release-msvc\.7z$'
if (-not $asset) { $asset = Get-GhAssetUrl 'pal1000/mesa-dist-win' 'release-msvc.*\.7z$' }
if (-not $asset) {
  Log '  Mesa: release asset not found (API/rate-limit) - skipping software graphics'
  Update-Status @{ grafis = @{ mode = 'gagal'; mesa = ''; adapters = $gAdapters; note = 'Mesa download not available' } } | Out-Null
  return
}
$gMesa = ($asset.name -replace '^mesa3d-', '' -replace '-release-msvc\.7z$', '')
Log "  Mesa3D: $($asset.name) (tag $($asset.tag))"

$arc = Join-Path $root $asset.name
if (-not (Get-File $asset.url $arc 300)) {
  Log '  Mesa download failed'
  Update-Status @{ grafis = @{ mode = 'gagal'; mesa = $gMesa; adapters = $gAdapters; note = 'download failed' } } | Out-Null
  return
}

# ---- 3) extract (GitHub runner has 7-Zip) ---------------------------------
$sevenZip = $null
foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
  if (Test-Path $p) { $sevenZip = $p; break }
}
if (-not $sevenZip) { $c = Get-Command 7z.exe -ErrorAction SilentlyContinue; if ($c) { $sevenZip = $c.Source } }
$ext = Join-Path $root 'mesa'
Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
if ($sevenZip) {
  & $sevenZip x $arc "-o$ext" -y 2>&1 | Out-Null
  Log "  7z: extracted to $ext"
} else {
  Log '  7z.exe not found - trying tar ( .7z archives often fail )'
  try { tar -xf $arc -C $ext 2>&1 | Out-Null } catch {}
}

function Pick-X64([string]$name) {
  $all = @(Get-ChildItem -Path $ext -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
  $x64 = @($all | Where-Object { $_.FullName -match '\\x64\\' })
  if ($x64.Count -gt 0) { return $x64[0].FullName }
  if ($all.Count -gt 0) { return $all[0].FullName }
  return $null
}

$sys32 = "$env:SystemRoot\System32"
$opengl = Pick-X64 'opengl32.dll'
$galium = Pick-X64 'libgallium_wgl.dll'
$dxil   = Pick-X64 'dxil.dll'
$lvpDll = Pick-X64 'vulkan_lvp.dll'
$lvpIcd = Pick-X64 'lvp_icd.x86_64.json'
$files = @()
if ($opengl) { $files += 'opengl32.dll' }
if ($galium) { $files += 'libgallium_wgl.dll' }
if ($lvpDll) { $files += 'vulkan_lvp.dll' }

# ---- 4) install llvmpipe (OpenGL) system-wide ------------------------------
# Files in System32 are owned by TrustedInstaller -> must takeown + icacls first,
# otherwise: "Access to the path 'C:\Windows\System32\opengl32.dll' is denied".
function Install-SysFile([string]$src, [string]$dst) {
  if (-not $src) { return $false }
  if (-not (Test-Path $dst)) { Copy-Item $src $dst -Force -ErrorAction Stop; return $true }
  $company = ''
  try { $company = (Get-Item $dst).VersionInfo.CompanyName } catch {}
  if ($company -like 'Mesa*') { Copy-Item $src $dst -Force -ErrorAction Stop; return $true }
  & takeown.exe /f $dst /a 2>&1 | Out-Null
  & icacls.exe $dst /grant '*S-1-5-32-544:F' 2>&1 | Out-Null
  Copy-Item $src $dst -Force -ErrorAction Stop
  & icacls.exe $dst /setowner 'NT SERVICE\TrustedInstaller' 2>&1 | Out-Null
  return $true
}

$gGLInstall = 'belum'
if ($opengl) {
  Copy-Item "$sys32\opengl32.dll" (Join-Path $bkp 'opengl32.dll') -Force -ErrorAction SilentlyContinue
  try {
    Install-SysFile $opengl "$sys32\opengl32.dll" | Out-Null
    Install-SysFile $galium "$sys32\libgallium_wgl.dll" | Out-Null
    Install-SysFile $dxil   "$sys32\dxil.dll" | Out-Null
    $vi = (Get-Item "$sys32\opengl32.dll").VersionInfo
    $gGLInstall = "mesa $($vi.FileVersion) [$($vi.CompanyName)]"
    Log "  llvmpipe installed: $sys32\opengl32.dll -> $gGLInstall (original backed up to $bkp)"
  } catch {
    $gGLInstall = 'gagal: ' + $_.Exception.Message
    Log "  FAILED to install Mesa into System32: $($_.Exception.Message)"
    $glDir = Join-Path $root 'gl'
    New-Item -ItemType Directory -Force -Path $glDir | Out-Null
    foreach ($f in @($opengl, $galium, $dxil)) { if ($f) { Copy-Item $f $glDir -Force -ErrorAction SilentlyContinue } }
    Log "  fallback: Mesa DLLs copied to $glDir (need to copy into app folder)"
  }
} else {
  Log '  Mesa opengl32.dll not found in archive (OpenGL skipped)'
}
[Environment]::SetEnvironmentVariable('GALLIUM_DRIVER', 'llvmpipe', 'Machine')
[Environment]::SetEnvironmentVariable('LIBGL_ALWAYS_SOFTWARE', '1', 'Machine')

# ---- 5) install lavapipe (Vulkan CPU) -------------------------------------
if ($lvpDll -and $lvpIcd) {
  $vkDir = Join-Path $root 'vulkan'
  New-Item -ItemType Directory -Force -Path $vkDir | Out-Null
  Copy-Item $lvpDll $vkDir -Force
  Copy-Item $lvpIcd $vkDir -Force
  $icd = Join-Path $vkDir (Split-Path $lvpIcd -Leaf)
  [Environment]::SetEnvironmentVariable('VK_DRIVER_FILES', $icd, 'Machine')
  [Environment]::SetEnvironmentVariable('VK_ADD_DRIVER_FILES', $icd, 'Machine')
  $gVulkan = 'lavapipe (CPU)'
  Log "  lavapipe registered: VK_DRIVER_FILES=$icd"
} else {
  Log '  lavapipe not present in archive (Vulkan skipped)'
}

# ---- 5b) Vulkan loader (vulkan-1.dll): runners without GPU driver often lack it -
# Without a loader, Vulkan apps cannot use lavapipe. LunarG provides a
# "Vulkan Runtime Components" package (small zip containing x64/vulkan-1.dll).
$gVkLoader = ''
$loaderDst = "$sys32\vulkan-1.dll"
if (Test-Path $loaderDst) {
  $gVkLoader = 'already present'
  Log "  Vulkan loader already present: $loaderDst"
} else {
  $vkrt = Join-Path $root 'vulkan-runtime.zip'
  if (Get-File 'https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-runtime-components.zip' $vkrt 300) {
    $zvk = Join-Path $root 'vkrt'
    Remove-Item $zvk -Recurse -Force -ErrorAction SilentlyContinue
    try {
      if ($sevenZip) { & $sevenZip x $vkrt "-o$zvk" -y 2>&1 | Out-Null }
      else { Expand-Archive -Path $vkrt -DestinationPath $zvk -Force }
      $dll = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkan-1.dll' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match '\\x64\\' })
      if ($dll.Count -eq 0) { $dll = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkan-1.dll' -ErrorAction SilentlyContinue) }
      if ($dll.Count -gt 0) {
        Copy-Item $dll[0].FullName $loaderDst -Force -ErrorAction Stop
        $vi = (Get-Item $loaderDst).VersionInfo
        $gVkLoader = "vulkan-1.dll $($vi.FileVersion) (LunarG)".Trim()
        $files += 'vulkan-1.dll'
        Log "  Vulkan loader installed: $loaderDst -> $gVkLoader"
      } else {
        Log '  vulkan-1.dll not found in LunarG runtime package'
      }
      $vex = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkaninfo.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match '\\x64\\' })
      if ($vex.Count -gt 0) { Copy-Item $vex[0].FullName (Join-Path $root 'vulkaninfo.exe') -Force -ErrorAction SilentlyContinue }
    } catch { Log "  failed to install Vulkan loader: $($_.Exception.Message)" }
  } else {
    Log '  download of Vulkan runtime (LunarG) failed - loader skipped'
  }
}

# 5c) register lavapipe ICD in the registry (official GPU driver approach)
#     so loader and any app can find it, not relying on env vars alone.
if ($icd) {
  try {
    $vkKey = 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers'
    New-Item -Path $vkKey -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $vkKey -Name $icd -PropertyType DWord -Value 0 -Force | Out-Null
    Log "  lavapipe ICD registered in registry: $vkKey"
  } catch { Log "  registering ICD to registry failed: $($_.Exception.Message)" }
}

# ---- 6) real test: actual OpenGL/Vulkan versions obtained ------------------
$py = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py.exe -ErrorAction SilentlyContinue }
$env:GALLIUM_DRIVER = 'llvmpipe'; $env:LIBGL_ALWAYS_SOFTWARE = '1'
$gVkDbg = ''
if ($icd) {
  $env:VK_DRIVER_FILES = $icd; $env:VK_ADD_DRIVER_FILES = $icd; $env:VK_ICD_FILENAMES = $icd
  $env:VK_LOADER_DEBUG = 'error,warn,driver'
}

if ($py -and $opengl) {
  try { & $py.Source -m pip install --quiet --disable-pip-version-check moderngl 2>&1 | Out-Null } catch {}
  $code = 'import moderngl;c=moderngl.create_standalone_context();i=c.info;print(i.get("GL_VERSION",""),"|",i.get("GL_RENDERER",""),"|",i.get("GL_VENDOR",""))'
  try {
    $out = ((& $py.Source -c $code 2>&1) | Out-String).Trim()
    if ($out -match '\|') { $gOpenGL = ($out -replace '\s+', ' ') } else { Log "  OpenGL test: $(($out -split "`n" | Select-Object -Last 1))" }
  } catch { Log "  OpenGL test failed: $($_.Exception.Message)" }
}

# Vulkan: request vulkaninfo (most authoritative), then fallback to ctypes loader
$vkOk = $false
$vkinfo = Join-Path $root 'vulkaninfo.exe'
if (Test-Path $vkinfo) {
  try {
    $vo = ((& $vkinfo --summary 2>&1) | Out-String)
    $dn = [regex]::Match($vo, 'deviceName\s*=\s*(.+)').Groups[1].Value.Trim()
    $dt = [regex]::Match($vo, 'deviceType\s*=\s*(.+)').Groups[1].Value.Trim()
    if ($dn) {
      $gVulkan = "$dn $(if ($dt) { "($dt)" })".TrimEnd() -replace '^\s+|\s+$', ''
      $vkOk = $true
      Log "  Vulkan test: $gVulkan"
    } else {
      $gVkDbg = (($vo -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 20) -join ' ; ')
      Log "  vulkaninfo without device; debug: $gVkDbg"
    }
  } catch { Log "  vulkaninfo failed: $($_.Exception.Message)" }
}
if ($py -and -not $vkOk) {
  $vkCode = @'
import ctypes
try:
    vk = ctypes.CDLL("vulkan-1.dll")
except OSError:
    print("loader-tidak-ada")
    raise SystemExit
class App(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_uint32), ("pNext", ctypes.c_void_p),
                ("pApplicationName", ctypes.c_char_p), ("applicationVersion", ctypes.c_uint32),
                ("pEngineName", ctypes.c_char_p), ("engineVersion", ctypes.c_uint32),
                ("apiVersion", ctypes.c_uint32)]
class ICI(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_uint32), ("pNext", ctypes.c_void_p), ("flags", ctypes.c_uint32),
                ("pApplicationInfo", ctypes.c_void_p), ("enabledLayerCount", ctypes.c_uint32),
                ("ppEnabledLayerNames", ctypes.c_void_p), ("enabledExtensionCount", ctypes.c_uint32),
                ("ppEnabledExtensionNames", ctypes.c_void_p)]
vk.vkCreateInstance.argtypes = [ctypes.POINTER(ICI), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
vk.vkCreateInstance.restype = ctypes.c_int
vk.vkEnumeratePhysicalDevices.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_void_p)]
vk.vkGetPhysicalDeviceProperties.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
app = App(0, None, b"xyrdp", 1, b"xyrdp", 1, (1 << 22))
ici = ICI(1, None, 0, ctypes.cast(ctypes.pointer(app), ctypes.c_void_p), 0, None, 0, None)
inst = ctypes.c_void_p()
rc = vk.vkCreateInstance(ctypes.byref(ici), None, ctypes.byref(inst))
if rc != 0:
    print("create-instance-error-%d" % rc)
    raise SystemExit
n = ctypes.c_uint32()
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), None)
if n.value == 0:
    print("tanpa-device")
    raise SystemExit
arr = (ctypes.c_void_p * n.value)()
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), arr)
buf = ctypes.create_string_buffer(2048)
vk.vkGetPhysicalDeviceProperties(arr[0], buf)
print(buf.raw[20:276].split(b"\x00")[0].decode("utf-8", "replace"))
'@
  $vkf = Join-Path $root 'vk-probe.py'
  Set-Content -Path $vkf -Value $vkCode -Encoding UTF8
  try {
    $vout = ((& $py.Source $vkf 2>&1) | Out-String).Trim()
    if (-not $gVkDbg -and $vout) { $gVkDbg = (($vout -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 20) -join ' ; ') }
    if ($vout -eq 'loader-tidak-ada') { $gVulkan = "$gVulkan / loader vulkan-1.dll tidak ada" }
    elseif ($vout -match 'create-instance-error|tanpa-device') { $gVulkan = "$gVulkan / uji: $([regex]::Match($vout, 'create-instance-error-\d+|tanpa-device').Value)" }
    elseif ($vout) { $gVulkan = $vout; Log "  Vulkan test: device = $vout" }
  } catch { Log "  Vulkan test failed: $($_.Exception.Message)" }
}

if (-not $gOpenGL) { $gOpenGL = "llvmpipe (Mesa $gMesa) - not yet verified" }
$glVer = [regex]::Match($gOpenGL, '^(\d+\.\d+)').Groups[1].Value
if (-not $glVer) { $glVer = '4.5+' }
if ($gGLInstall -like 'mesa*') {
  $gNote = "Software GPU (CPU): OpenGL $glVer (llvmpipe) + Vulkan lavapipe + built-in WARP. GitHub runner without physical GPU; heavy 3D remains slow."
} else {
  $gNote = "Installing OpenGL software into System32 failed ($gGLInstall). Vulkan lavapipe & WARP remain active; Mesa DLLs are available in $root\gl for per-application use."
}
Log "  done: OpenGL=$gOpenGL | Vulkan=$(if ($gVulkan) { $gVulkan } else { '-' }) | loader=$(if ($gVkLoader) { $gVkLoader } else { '-' }) | install=$gGLInstall"

try {
  Update-Status @{ grafis = @{
    mode = $gMode; mesa = $gMesa; opengl = $gOpenGL; vulkan = $gVulkan; install = $gGLInstall
    loader = $gVkLoader; debug = $gVkDbg; adapters = $gAdapters; files = ($files -join ','); dir = $root; note = $gNote
  } } | Out-Null
  Log '  graphics status written (grafis.*)'
} catch { Log "  writing graphics status failed: $($_.Exception.Message)" }