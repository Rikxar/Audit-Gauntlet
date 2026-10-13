$ErrorActionPreference='Stop'
$root='E:\Audit Gauntlet';$folder=Join-Path $root 'publication'
$verified=@(Get-ChildItem -LiteralPath $folder -Filter 'verified-*.json'|Where-Object Name -ne 'verified-repositories.json'|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName|ConvertFrom-Json})
if($verified.Count -ne 30){throw 'Expected 30 verified programme records'}
$verified|Sort-Object programme|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $folder 'verified-repositories.json') -Encoding utf8
$history=@(Get-ChildItem -LiteralPath $folder -Filter 'history-audit-*.json'|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName|ConvertFrom-Json})
$latest=@($history|Group-Object programme|ForEach-Object{$_.Group|Sort-Object checkedUtc -Descending|Select-Object -First 1})
foreach($p in $verified){$audit=$latest|Where-Object programme -eq $p.programme;if(-not $audit -or -not $audit.passed){throw "History audit is not passed for $($p.programme)"}}
$latest|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $folder 'history-reviewed.json') -Encoding utf8
$unpublished=foreach($record in $verified){
 $path=$record.path;$safe=$path.Replace('\','/')
 $tracked=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($p in (& git -c "safe.directory=$safe" -C $path ls-files)){[void]$tracked.Add($p)}
 $inventoryPath=Join-Path $folder ('inventory-'+$record.programme+'.json')
 if(Test-Path $inventoryPath){$inventory=Get-Content -Raw -LiteralPath $inventoryPath|ConvertFrom-Json;$files=@($inventory.files|Where-Object {-not $tracked.Contains($_.path)}|ForEach-Object{[pscustomobject]@{path=$_.path;bytes=$_.bytes;reason=if($_.reason){$_.reason}else{'existing-ignore-or-curated-omission'}}});$dirs=@($inventory.omittedDirectories)}
 else {$files=@();$dirs=@('Excluded raw/data/calibration/venv trees remain governed by the programme .gitignore and original data manifests.')}
 [pscustomobject]@{programme=$record.programme;path=$record.path;files=$files;omittedDirectories=$dirs;untracked=@($record.untracked);nestedOrExternalHistoriesNotRepublished=if($record.programme -eq 'SGR1935_FLICK_AUDIT'){@()}else{@()}}
}
$unpublished|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $folder 'unpublished.json') -Encoding utf8
'Consolidated 30 verified repositories, passed history audits and explicit omitted-file records.'
