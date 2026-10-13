param([Parameter(Mandatory)][string[]]$Repositories)
$ErrorActionPreference='Stop'
$root='E:\Audit Gauntlet'
$results=foreach($name in $Repositories){
 $path=Join-Path $root $name
 $refs=@(& git -c "safe.directory=$($path.Replace('\','/'))" -C $path for-each-ref '--format=%(refname)' refs/heads refs/tags)
 if(-not $refs){continue}
 $objects=@(& git -c "safe.directory=$($path.Replace('\','/'))" -C $path rev-list --objects $refs)
 if($LASTEXITCODE){throw "Cannot list history: $name"}
 $sizes=@($objects | & git -c "safe.directory=$($path.Replace('\','/'))" -C $path cat-file '--batch-check=%(objectname) %(objecttype) %(objectsize) %(rest)')
 $blobs=@($sizes|Where-Object {$_ -match '^\S+ blob '})
 $blocked=[Collections.Generic.List[object]]::new()
 $secrets=[Collections.Generic.List[object]]::new()
 $psi=[Diagnostics.ProcessStartInfo]::new('git')
 $psi.WorkingDirectory=$path;$psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true
 foreach($a in @('-c',"safe.directory=$($path.Replace('\','/'))",'cat-file','--batch')){$psi.ArgumentList.Add($a)}
 $process=[Diagnostics.Process]::Start($psi);$stream=$process.StandardOutput.BaseStream
 foreach($line in $blobs){
  $parts=$line -split ' ',4;$oid=$parts[0];$size=[long]$parts[2];$file=$parts[3]
  # Reviewed exceptions: tiny manufactured runner fixtures and historically
  # committed source literature are provenance, not observational archives.
  $synthetic = $file -match '^08_validation/SGR1935_2A_AMENDMENT_001_COMPLETE_RUNNER_SYNTHETIC_V[34]/' -and $size -lt 1MB
  $literature = $name -eq 'SGR1806_20_2004_GIANT_FLARE_AUDIT' -and $file -match '^03_raw/g1f_receivers/.*\.(pdf|html)$' -and $size -lt 1MB
  if($size -ge 100MB -or (-not $synthetic -and ($file -match '(?i)\.(fits?(\.gz)?|uvfits|h5|hdf5|zip|tar\.gz|npy|npz)$' -or (-not $literature -and $file -match '(?i)(^|/)(03_raw|RAW|data_raw)/' -and $file -notmatch '(?i)(manifest|sha256|hash|readme|\.gitkeep)')))){$blocked.Add([pscustomobject]@{oid=$oid;path=$file;bytes=$size;reason='excluded-data-or-oversized'});continue}
  if($size -gt 50MB){$blocked.Add([pscustomobject]@{oid=$oid;path=$file;bytes=$size;reason='large-object-review'});continue}
  $process.StandardInput.WriteLine($oid);$process.StandardInput.Flush()
  $header=[Text.StringBuilder]::new();while(($b=$stream.ReadByte()) -ne 10){if($b -lt 0){throw 'Unexpected object EOF'};[void]$header.Append([char]$b)}
  $buffer=[byte[]]::new([int]$size);$offset=0;while($offset -lt $size){$n=$stream.Read($buffer,$offset,[int]$size-$offset);if(-not $n){throw 'Incomplete object'};$offset+=$n};[void]$stream.ReadByte()
  $content=[Text.Encoding]::UTF8.GetString($buffer)
  if($content -match '(?i)(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|(?-i:AKIA[0-9A-Z]{16})|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|https?://[^\s/:]+:[^\s/@]+@|(?:api[_-]?key|password|client_secret|access_token)\s*[=:]\s*["''][A-Za-z0-9_+/=.-]{16,}["''])'){$secrets.Add([pscustomobject]@{oid=$oid;path=$file;reason='credential-pattern-review'})}
 }
 $process.StandardInput.Close();$process.WaitForExit()
 [pscustomobject]@{programme=$name;refs=$refs;blobs=$blobs.Count;largest=($blobs|ForEach-Object{[long](($_ -split ' ',4)[2])}|Measure-Object -Maximum).Maximum;blocked=@($blocked);credentialPatterns=@($secrets);passed=($blocked.Count -eq 0 -and $secrets.Count -eq 0);checkedUtc=[datetime]::UtcNow.ToString('o')}
}
$results | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $root ('publication/history-audit-'+($Repositories[0] -replace '[^A-Za-z0-9_-]','_')+'.json')) -Encoding utf8
foreach($r in $results){'{0}: {1} historical blobs, {2} excluded/large objects, {3} credential patterns, PASS={4}' -f $r.programme,$r.blobs,$r.blocked.Count,$r.credentialPatterns.Count,$r.passed}
