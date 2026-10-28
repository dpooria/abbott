$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$build = Join-Path $PSScriptRoot '.build/windows'
$gtk = Join-Path $build 'gtk'
$mpv = Join-Path $build 'mpv'
$portable = Join-Path $PSScriptRoot 'dist/abbott-windows-x64'
$gtkUrl = 'https://github.com/wingtk/gvsbuild/releases/download/2026.4.1/GTK4_Gvsbuild_2026.4.1_x64.zip'
$mpvUrl = 'https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261021/mpv-dev-x86_64-20261021-git-e471496c56.7z'
New-Item -ItemType Directory -Force $build | Out-Null

if (!(Test-Path "$gtk/bin/glib-compile-resources.exe")) {
    Invoke-WebRequest $gtkUrl -OutFile "$build/gtk.zip"
    Expand-Archive "$build/gtk.zip" -DestinationPath $gtk -Force
}
if (!(Test-Path "$mpv/libmpv.dll.a")) {
    $sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
    if (!$sevenZip) { $sevenZip = "$env:ProgramFiles/7-Zip/7z.exe" }
    if (!(Test-Path $sevenZip)) { throw 'Install 7-Zip, then run this script again.' }
    Invoke-WebRequest $mpvUrl -OutFile "$build/mpv.7z"
    & $sevenZip x -y "-o$mpv" "$build/mpv.7z" | Out-Null
    if ($LASTEXITCODE) { throw 'Could not extract libmpv.' }
}

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

& "$gtk/bin/glib-compile-resources.exe" assets/abbott.gresource.xml --sourcedir=assets --target=.build/abbott.gresource
if ($LASTEXITCODE) { throw 'Resource compilation failed.' }
New-Item -ItemType Directory -Force $portable | Out-Null
& odin build . -target:windows_amd64 "-out:$portable/abbott.exe" '-extra-linker-flags:/subsystem:windows'
if ($LASTEXITCODE) { throw 'Odin build failed.' }

Copy-Item "$gtk/bin/*.dll" $portable -Force
Copy-Item "$mpv/libmpv-2.dll" $portable -Force
Copy-Item "$($crt.FullName)/*.dll" $portable -Force
foreach ($folder in 'share', 'etc') {
    Copy-Item "$gtk/$folder" $portable -Recurse -Force
}
New-Item -ItemType Directory -Force "$portable/lib" | Out-Null
Copy-Item "$gtk/lib/gdk-pixbuf-2.0" "$portable/lib" -Recurse -Force
if (Test-Path "$gtk/lib/gio") { Copy-Item "$gtk/lib/gio" "$portable/lib" -Recurse -Force }
Copy-Item LICENSE "$portable/LICENSE" -Force
@'
Abbott for Windows x64 (preview)

Extract the entire ZIP into a writable folder and open abbott.exe.
Keep all DLLs and runtime folders beside it. No installation is needed.
Your library and progress are saved in data/library.json beside abbott.exe.
Audio files stay in their original locations.

Build sources and dependency versions:
GTK: https://github.com/wingtk/gvsbuild/releases/tag/2026.4.1
libmpv: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261021
mpv: https://github.com/mpv-player/mpv/tree/e471496c56
'@ | Set-Content "$portable/README.txt" -Encoding UTF8

$archive = Join-Path $PSScriptRoot 'dist/abbott-windows-x64.zip'
Compress-Archive -Path $portable -DestinationPath $archive -Force
Write-Host "Portable build: $archive"
