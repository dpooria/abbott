$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$build = Join-Path $PSScriptRoot '.build/windows'
$mpv = Join-Path $build 'mpv'
$output = Join-Path $PSScriptRoot 'dist/windows'
New-Item -ItemType Directory -Force $mpv | Out-Null

$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (!(Test-Path $vswhere)) { throw 'Install Visual Studio C++ Build Tools with the Windows SDK.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory |
    Sort-Object FullName | Select-Object -Last 1
if (!$crt) { throw 'Could not find the Visual C++ redistributable DLLs.' }

$libTool = Get-ChildItem "$vs/VC/Tools/MSVC/*/bin/Hostx64/x64/lib.exe" |
    Sort-Object FullName | Select-Object -Last 1
if (!$libTool) { throw 'Could not find the Visual C++ library tool.' }
$exports = Select-String -Path mpv.odin -Pattern '^\s+(mpv_\w+) :: proc' |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
@('LIBRARY libmpv-2.dll', 'EXPORTS') + $exports | Set-Content "$mpv/mpv.def" -Encoding ascii
& $libTool.FullName "/def:$mpv/mpv.def" /machine:x64 "/out:$mpv/mpv.lib" /nologo
if ($LASTEXITCODE) { throw 'Could not create the libmpv import library.' }

New-Item -ItemType Directory -Force $output | Out-Null
& odin build . -target:windows_amd64 "-out:$output/abbott.exe" '-extra-linker-flags:/subsystem:windows'
if ($LASTEXITCODE) { throw 'Odin build failed.' }

Copy-Item "$($crt.FullName)/*.dll" $output -Force
Copy-Item LICENSE "$output/LICENSE" -Force
Copy-Item assets/JetBrainsMono-OFL.txt "$output/JetBrainsMono-OFL.txt" -Force
Copy-Item assets/raylib-LICENSE.txt "$output/raylib-LICENSE.txt" -Force
Copy-Item assets/raygui-LICENSE.txt "$output/raygui-LICENSE.txt" -Force
@'
Abbott for Windows x64

Open abbott.exe from this folder.
Install 64-bit libmpv separately. Put libmpv-2.dll and its dependencies on PATH
or beside abbott.exe. The mpv.exe command alone is not sufficient.
Your library and progress are saved in data/library.json beside abbott.exe.
Audio files stay in their original locations.

raylib and raygui are bundled with Odin.
'@ | Set-Content "$output/README.txt" -Encoding UTF8

Write-Host "Windows build: $output"
