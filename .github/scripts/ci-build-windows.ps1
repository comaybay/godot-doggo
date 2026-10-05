# Compile Windows x86_64 editor + export templates and pack GitHub Release assets.
# Asset names match what the-battle-dogs fetch-godot-doggo.ps1 / update-godot-experimental.ps1 download.
#
# CI uses debug_symbols=no so the runner is not filled by PDBs; the zip never included them.

[CmdletBinding()]
param(
	[string]$SourceDir,
	[Parameter(Mandatory = $true)]
	[string]$OutDir,
	[switch]$SkipTemplates,
	[switch]$SkipDeps
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $scriptDir "_godot_scons.ps1")
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $SourceDir) {
	$SourceDir = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
}

function Get-GodotVersionField([string]$Text, [string]$Name) {
	$m = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(.+?)\s*$")
	if (-not $m.Success) { throw "version.py has no $Name" }
	return $m.Groups[1].Value.Trim().Trim("'").Trim('"')
}

function Get-GodotVersionInfo([string]$Dir) {
	$py = Join-Path $Dir "version.py"
	if (-not (Test-Path -LiteralPath $py)) {
		throw "version.py missing in $Dir"
	}
	$text = Get-Content -LiteralPath $py -Raw
	$major = [int](Get-GodotVersionField $text "major")
	$minor = [int](Get-GodotVersionField $text "minor")
	$patch = [int](Get-GodotVersionField $text "patch")
	$status = Get-GodotVersionField $text "status"
	$verCore = "{0}.{1}" -f $major, $minor
	if ($patch -ne 0) { $verCore = "{0}.{1}.{2}" -f $major, $minor, $patch }
	return [PSCustomObject]@{
		Dash = "{0}-{1}" -f $verCore, $status
		Dot  = "{0}.{1}" -f $verCore, $status
	}
}

function Add-ZipEntry($Zip, [string]$Src, [string]$EntryName) {
	[IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
		$Zip, $Src, $EntryName, [IO.Compression.CompressionLevel]::Optimal
	) | Out-Null
}

function New-ZipFromMap([string]$ZipPath, $Map) {
	if (Test-Path -LiteralPath $ZipPath) {
		Remove-Item -LiteralPath $ZipPath -Force
	}
	$parent = Split-Path -Parent $ZipPath
	if ($parent) {
		New-Item -ItemType Directory -Force -Path $parent | Out-Null
	}
	$zip = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
	try {
		foreach ($pair in $Map.GetEnumerator()) {
			if (-not (Test-Path -LiteralPath $pair.Value)) {
				throw "Missing file for zip entry $($pair.Key): $($pair.Value)"
			}
			Add-ZipEntry $zip $pair.Value $pair.Key
		}
	} finally {
		$zip.Dispose()
	}
}

$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $SourceDir "SConstruct"))) {
	throw "Not a Godot engine tree (missing SConstruct): $SourceDir"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$sha = (& git -C $SourceDir rev-parse HEAD).Trim()
$short = (& git -C $SourceDir rev-parse --short=9 HEAD).Trim()
$ver = Get-GodotVersionInfo $SourceDir
$stamp = "doggo-{0}" -f $short
$tag = "doggo-{0}-{1}" -f $ver.Dash, $short
$assetStem = "Godot_v{0}-{1}" -f $ver.Dash, $stamp
$title = "Godot {0} doggo ({1})" -f $ver.Dash, $short

Write-Host ("Source {0}  {1}" -f $short, $sha)
Write-Host ("Tag    {0}" -f $tag)

if (-not $SkipDeps) {
	Install-GodotWindowsDeps -Dir $SourceDir
	$angle = Join-Path $SourceDir "misc\scripts\install_angle.py"
	if (Test-Path -LiteralPath $angle) {
		Push-Location $SourceDir
		try {
			& python $angle
			if ($LASTEXITCODE -ne 0) {
				Write-Host "install_angle.py failed (exit $LASTEXITCODE); continuing without ANGLE."
			}
		} finally {
			Pop-Location
		}
	}
}

$bin = Join-Path $SourceDir "bin"
$common = @("platform=windows", "arch=x86_64")

Write-Host ""
Write-Host "Building editor ..."
Invoke-GodotScons -Dir $SourceDir -SconsArgs ($common + @("target=editor", "debug_symbols=no"))

$gui = Join-Path $bin "godot.windows.editor.x86_64.exe"
$console = Join-Path $bin "godot.windows.editor.x86_64.console.exe"
if (-not (Test-Path -LiteralPath $gui)) { throw "Editor GUI missing: $gui" }
if (-not (Test-Path -LiteralPath $console)) { throw "Editor console missing: $console" }

$editorZip = Join-Path $OutDir ($assetStem + "_win64.exe.zip")
New-ZipFromMap $editorZip ([ordered]@{
		($assetStem + "_win64.exe")         = $gui
		($assetStem + "_win64_console.exe") = $console
	})
Write-Host ("Packed {0}  ({1:N0} bytes)" -f (Split-Path -Leaf $editorZip), (Get-Item $editorZip).Length)

$templatesTpz = ""
if (-not $SkipTemplates) {
	Write-Host ""
	Write-Host "Building template_release ..."
	Invoke-GodotScons -Dir $SourceDir -SconsArgs ($common + @("target=template_release", "debug_symbols=no"))
	Write-Host ""
	Write-Host "Building template_debug ..."
	Invoke-GodotScons -Dir $SourceDir -SconsArgs ($common + @("target=template_debug", "debug_symbols=no"))

	$relGui = Join-Path $bin "godot.windows.template_release.x86_64.exe"
	$relCon = Join-Path $bin "godot.windows.template_release.x86_64.console.exe"
	$dbgGui = Join-Path $bin "godot.windows.template_debug.x86_64.exe"
	$dbgCon = Join-Path $bin "godot.windows.template_debug.x86_64.console.exe"
	foreach ($p in @($relGui, $relCon, $dbgGui, $dbgCon)) {
		if (-not (Test-Path -LiteralPath $p)) { throw "Template binary missing: $p" }
	}

	$stage = Join-Path $OutDir "templates-stage"
	if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
	$tplDir = Join-Path $stage "templates"
	New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
	Set-Content -LiteralPath (Join-Path $tplDir "version.txt") -Value $ver.Dot -Encoding ascii -NoNewline
	Copy-Item -LiteralPath $relGui -Destination (Join-Path $tplDir "windows_release_x86_64.exe")
	Copy-Item -LiteralPath $relCon -Destination (Join-Path $tplDir "windows_release_x86_64_console.exe")
	Copy-Item -LiteralPath $dbgGui -Destination (Join-Path $tplDir "windows_debug_x86_64.exe")
	Copy-Item -LiteralPath $dbgCon -Destination (Join-Path $tplDir "windows_debug_x86_64_console.exe")

	$templatesTpz = Join-Path $OutDir ($assetStem + "_export_templates.tpz")
	if (Test-Path -LiteralPath $templatesTpz) { Remove-Item -LiteralPath $templatesTpz -Force }
	[IO.Compression.ZipFile]::CreateFromDirectory($stage, $templatesTpz, [IO.Compression.CompressionLevel]::Optimal, $false)
	Remove-Item -LiteralPath $stage -Recurse -Force
	Write-Host ("Packed {0}  ({1:N0} bytes)" -f (Split-Path -Leaf $templatesTpz), (Get-Item $templatesTpz).Length)
}

if ($env:GITHUB_OUTPUT) {
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "tag=$tag"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "title=$title"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "sha=$sha"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "short=$short"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "editor_zip=$editorZip"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "templates_tpz=$templatesTpz"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "version_dash=$($ver.Dash)"
	Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "version_dot=$($ver.Dot)"
}

Write-Host ""
Write-Host "Done."
