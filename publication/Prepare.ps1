param([Parameter(Mandatory)][string[]]$Names)
$ErrorActionPreference='Stop'
$root='E:\Audit Gauntlet'
foreach($name in $Names){
 $path=Join-Path $root $name;$safe=$path.Replace('\','/')
 $inventoryFile=Join-Path $root ('publication/inventory-'+$name+'.json')
 if(-not (Test-Path $inventoryFile)){throw "Inventory missing: $name"}
 $record=Get-Content -Raw -LiteralPath $inventoryFile|ConvertFrom-Json
 if($record.errors.Count){throw "Unreadable programme paths: $name"}
 $credentialFiles=@($record.files|Where-Object reason -eq 'credential-pattern-review')
 if($credentialFiles.Count){Write-Host "Holding $($credentialFiles.Count) credential-pattern file(s) locally in $name"}
 if(-not(Test-Path (Join-Path $path '.git'))){& git -C $path init --initial-branch=main;if($LASTEXITCODE){throw "init failed: $name"}}
 $top=& git -c "safe.directory=$safe" -C $path rev-parse --show-toplevel
 if($top -ne $safe){throw "Wrong repository boundary: $name"}
 $files=@($record.files|Where-Object eligible|ForEach-Object path)+@('.gitignore','.gitattributes','PUBLICATION.md')
 $files=@($files|Sort-Object -Unique)
 # Every path comes from the reviewed programme inventory. Never add a directory.
 $ignored=@($files|& git -c "safe.directory=$safe" -C $path check-ignore --no-index --stdin | ForEach-Object {if($_.StartsWith('"')){($_|ConvertFrom-Json).TrimEnd("`r")}else{$_.TrimEnd("`r")}})
 $ignoreSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($f in $ignored){[void]$ignoreSet.Add($f)}
 $ordinary=@($files|Where-Object {-not $ignoreSet.Contains($_)})
 $admittedReports=@($ignored|Where-Object {$_ -match '(?i)(\.md$|(?:seal|manifest|hash|sha256|gate|status|preservation|convergence|registration)[^/]*\.(json|csv|txt|sha256)$)' -and $_ -notmatch '(?i)(^|/)(\.venv.*|_vendor|vendor|RAW|03_raw|data_raw)/'})
 if($ordinary.Count){$ordinary|& git -c "safe.directory=$safe" -C $path add --pathspec-from-file=-;if($LASTEXITCODE){throw "add failed: $name"}}
 if($admittedReports.Count){$admittedReports|& git -c "safe.directory=$safe" -C $path add -f --pathspec-from-file=-;if($LASTEXITCODE){throw "report admission failed: $name"}}
 $staged=@(& git -c "safe.directory=$safe" -C $path diff --cached --name-only)
 $manifest=foreach($f in $staged){$item=Get-Item -LiteralPath (Join-Path $path $f);[pscustomobject]@{path=$f;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
 $reportSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($f in $admittedReports){[void]$reportSet.Add($f)}
 [pscustomobject]@{programme=$name;staged=$manifest;explicitReportAdmissions=$admittedReports;ignoredAndUnpublished=@($ignored|Where-Object {-not $reportSet.Contains($_)});reviewUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root ('publication/admission-'+$name+'.json')) -Encoding utf8
 '{0}: staged {1} files ({2:N1} MiB), {3} explicit report/provenance admissions' -f $name,$staged.Count,(($manifest|Measure-Object bytes -Sum).Sum/1MB),$admittedReports.Count
}
