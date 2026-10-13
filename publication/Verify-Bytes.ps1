$ErrorActionPreference='Stop'
$root='E:\Audit Gauntlet'
$records=foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'publication') -Filter 'admission-*.json'){
 $admission=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json
 $path=Join-Path $root $admission.programme;$safe=$path.Replace('\','/')
 $tree=@{};foreach($line in (& git -c "safe.directory=$safe" -C $path ls-tree -r HEAD)){if($line -match '^\d+ blob (\S+)\t(.+)$'){$tree[$Matches[2]]=$Matches[1]}}
 $psi=[Diagnostics.ProcessStartInfo]::new('git');$psi.WorkingDirectory=$path;$psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true
 foreach($a in @('-c',"safe.directory=$safe",'cat-file','--batch')){$psi.ArgumentList.Add($a)}
 $process=[Diagnostics.Process]::Start($psi);$stream=$process.StandardOutput.BaseStream;$hashes=@{};$failures=[Collections.Generic.List[object]]::new()
 foreach($entry in $admission.staged){
  $oid=$tree[$entry.path];if(-not $oid){$failures.Add([pscustomobject]@{path=$entry.path;reason='not-in-published-tree'});continue}
  if(-not $hashes.ContainsKey($oid)){
   $process.StandardInput.WriteLine($oid);$process.StandardInput.Flush();$header=[Text.StringBuilder]::new();while(($b=$stream.ReadByte()) -ne 10){if($b -lt 0){throw 'Object EOF'};[void]$header.Append([char]$b)}
   $size=[int](($header.ToString() -split ' ')[2]);$buffer=[byte[]]::new($size);$offset=0;while($offset -lt $size){$n=$stream.Read($buffer,$offset,$size-$offset);if(-not $n){throw 'Incomplete blob'};$offset+=$n};[void]$stream.ReadByte()
   $hashes[$oid]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($buffer)).ToLowerInvariant()
  }
  if($hashes[$oid] -ne $entry.sha256){$failures.Add([pscustomobject]@{path=$entry.path;reason='published-bytes-differ-from-admitted-local-bytes'})}
 }
 $process.StandardInput.Close();$process.WaitForExit()
 $record=[pscustomobject]@{programme=$admission.programme;files=$admission.staged.Count;failures=@($failures);passed=($failures.Count -eq 0);checkedUtc=[datetime]::UtcNow.ToString('o')}
 Write-Host "$($record.programme): $($record.files) admitted files; $($failures.Count) byte mismatches"
 $record
}
$records|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'publication/byte-verification.json') -Encoding utf8
