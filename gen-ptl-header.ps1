param(
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$ptlDir = Join-Path $RepoRoot 'PTL'
$genDir = Join-Path $RepoRoot 'build\generated'
New-Item -ItemType Directory -Force $genDir | Out-Null
$outFile = Join-Path $genDir 'ptl_rules_generated.h'

if (-not (Test-Path $ptlDir)) { throw "missing PTL directory: $ptlDir" }

$pairs = @()
foreach ($file in Get-ChildItem $ptlDir -File -Filter *.json | Sort-Object Name) {
    $raw = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $json = $raw | ConvertFrom-Json
    if ($null -eq $json.pair -or $json.pair.Count -ne 2) {
        throw "PTL file missing pair: $($file.Name)"
    }
    $name = "$($json.pair[0])-$($json.pair[1])"
    if ($raw.Contains(')PTLJSON"')) {
        throw "PTL file contains raw string terminator: $($file.Name)"
    }
    $pairs += [pscustomobject]@{ Name = $name; Rules = $raw }
}
if ($pairs.Count -eq 0) { throw "no PTL rule files found in $ptlDir" }

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine('// auto-generated from PTL/*.json')
[void]$sb.AppendLine('#pragma once')
[void]$sb.AppendLine('#include <cstdint>')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('struct JercpldPtlEmbeddedPair {')
[void]$sb.AppendLine('    char const* name;')
[void]$sb.AppendLine('    char const* rules;')
[void]$sb.AppendLine('};')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('static const JercpldPtlEmbeddedPair kJercpldPtlPairs[] = {')
foreach ($p in $pairs) {
    [void]$sb.AppendLine("    { `"$($p.Name)`", R`"PTLJSON($($p.Rules))PTLJSON`" },")
}
[void]$sb.AppendLine('};')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('static const uint32_t kJercpldPtlPairCount =')
[void]$sb.AppendLine('    static_cast<uint32_t>(sizeof(kJercpldPtlPairs) / sizeof(kJercpldPtlPairs[0]));')
[void]$sb.AppendLine('')

[IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Output "generated $outFile with $($pairs.Count) pair(s)"
