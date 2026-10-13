param([switch]$Push)
$ErrorActionPreference='Stop'
$root='E:\Audit Gauntlet'
$credentialInput="protocol=https`nhost=github.com`n`n"
$credential=($credentialInput|git credential fill)|ConvertFrom-StringData
$headers=@{Authorization="Bearer $($credential.password)";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$me=Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/user'
if($me.login -ne 'Rikxar'){throw 'Unexpected GitHub account'}
$records=foreach($dir in Get-ChildItem -LiteralPath $root -Directory -Force|Where-Object {$_.Name -notmatch '^\.' -and $_.Name -notin @('tmp','publication','PRIMORDIAL_TICK_CENTRIFUGE')}){
 $name=$dir.Name;$path=$dir.FullName;$safe=$path.Replace('\','/')
 $repo=Invoke-RestMethod -Headers $headers -Uri ('https://api.github.com/repos/Rikxar/'+$name)
 if($repo.owner.login -ne 'Rikxar' -or -not $repo.private){throw "Wrong owner/visibility: $name"}
 $url=& git -c "safe.directory=$safe" -C $path remote get-url publishing
 if($url -ne "https://github.com/Rikxar/$name.git"){throw "Unexpected publishing remote: $name"}
 if($Push){& git -c "safe.directory=$safe" -C $path push publishing --all --quiet;if($LASTEXITCODE){throw "Branch push failed: $name"};& git -c "safe.directory=$safe" -C $path push publishing --tags --quiet;if($LASTEXITCODE){throw "Tag push failed: $name"}}
 $local=@(& git -c "safe.directory=$safe" -C $path for-each-ref '--format=%(refname) %(objectname)' refs/heads refs/tags)
 $remote=@(& git -c "safe.directory=$safe" -C $path ls-remote --heads --tags publishing)
 if($LASTEXITCODE){throw "Remote verification failed: $name"}
 $remoteMap=@{};foreach($line in $remote){$s=$line -split "`t",2;$remoteMap[$s[1]]=$s[0]}
 $verifiedRefs=foreach($line in $local){$s=$line -split ' ',2;[pscustomobject]@{ref=$s[0];local=$s[1];remote=$remoteMap[$s[0]];matches=($remoteMap[$s[0]] -eq $s[1])}}
 if(@($verifiedRefs|Where-Object {-not $_.matches}).Count){throw "Remote ref mismatch: $name"}
 $head=& git -c "safe.directory=$safe" -C $path rev-parse HEAD
 $record=[pscustomobject]@{programme=$name;path=$path;github=$repo.html_url;owner=$repo.owner.login;private=$repo.private;branch=(& git -c "safe.directory=$safe" -C $path branch --show-current);commit=$head;refs=@($verifiedRefs);remotes=@(& git -c "safe.directory=$safe" -C $path remote -v);worktrees=@(& git -c "safe.directory=$safe" -C $path worktree list --porcelain);localChanges=@(& git -c "safe.directory=$safe" -C $path status --short);untracked=@(& git -c "safe.directory=$safe" -C $path ls-files --others --exclude-standard);verifiedUtc=[datetime]::UtcNow.ToString('o')}
 $record|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $root ('publication/verified-'+$name+'.json')) -Encoding utf8
 Write-Host "$name verified private; $($head.Substring(0,12)); $(@($verifiedRefs).Count) refs matched"
 $record
}
$records|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $root 'publication/verified-repositories.json') -Encoding utf8
