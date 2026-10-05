# Shared MSVC/scons helpers for the windows-release workflow.

function Get-VsVcvars64 {
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (-not (Test-Path -LiteralPath $vswhere)) {
		throw "vswhere.exe not found. Install Visual Studio with the C++ workload."
	}
	$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
	if (-not $vsPath) {
		throw "No Visual Studio with VC tools found."
	}
	$vcvars = Join-Path $vsPath.Trim() "VC\Auxiliary\Build\vcvars64.bat"
	if (-not (Test-Path -LiteralPath $vcvars)) {
		throw "vcvars64.bat not found under $vsPath"
	}
	return $vcvars
}

function Install-GodotWindowsDeps([string]$Dir) {
	$depsRoot = Join-Path $env:LOCALAPPDATA "Godot\build_deps"
	$accesskit = Join-Path $depsRoot "accesskit"
	$mesa = Join-Path $depsRoot "mesa-x86_64-msvc"
	$needAccesskit = -not (Test-Path -LiteralPath $accesskit)
	$needD3d12 = -not (Test-Path -LiteralPath $mesa)
	if (-not $needAccesskit -and -not $needD3d12) {
		Write-Host "Windows build deps already present in $depsRoot"
		return
	}
	if ($needAccesskit) {
		Write-Host "Installing AccessKit into $depsRoot ..."
		Push-Location $Dir
		try {
			& python "misc\scripts\install_accesskit.py"
			if ($LASTEXITCODE -ne 0) { throw "install_accesskit.py failed (exit $LASTEXITCODE)" }
		} finally {
			Pop-Location
		}
	}
	if ($needD3d12) {
		Write-Host "Installing D3D12 SDK / Mesa NIR into $depsRoot ..."
		Push-Location $Dir
		try {
			& python "misc\scripts\install_d3d12_sdk_windows.py"
			if ($LASTEXITCODE -ne 0) { throw "install_d3d12_sdk_windows.py failed (exit $LASTEXITCODE)" }
		} finally {
			Pop-Location
		}
	}
}

function Invoke-GodotScons([string]$Dir, [string[]]$SconsArgs) {
	$vcvars = Get-VsVcvars64
	$joined = ($SconsArgs | ForEach-Object { $_ }) -join " "
	Write-Host "scons $joined"
	Write-Host "vcvars: $vcvars"
	$cmd = "call `"$vcvars`" && cd /d `"$Dir`" && scons $joined"
	cmd.exe /c $cmd
	if ($LASTEXITCODE -ne 0) {
		throw "scons failed (exit $LASTEXITCODE) in $Dir : $joined"
	}
}
