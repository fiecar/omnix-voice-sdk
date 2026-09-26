# SDK-059 license scan (Windows).
$ErrorActionPreference = 'Stop'
$py = Join-Path $PSScriptRoot 'check-licenses.py'
python $py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
