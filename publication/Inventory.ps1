param([string]$Root = 'E:\Audit Gauntlet', [string[]]$Names = @())
$ErrorActionPreference = 'Stop'
$skip = '(?i)^(\.git|\.venv.*|venv|__pycache__|\.pytest_cache|\.deps|\.kine_deps|_vendor|vendor|PYDEPS|python_packages.*|wheels|node_modules|\.build|\.codex.*|tmp|publication|source_at_registration|backend_build|final_source_bundle|source_bundle|blind_inputs|blind_metrics|blind_comparison|shared_grids|interrupted_products|custodian)$'
$allow = '(?i)\.(py|ps1|sh|bat|c|cpp|h|hpp|f90|toml|ini|cfg|yaml|yml|json|csv|tsv|md|rst|txt|log|sha256|graphql|xml|vot|ipynb|html|css|js|png|svg|pdf|gif)$'
$sensitive = '(?i)(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|(?-i:AKIA[0-9A-Z]{16})|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|(?:https?://)[^\s/:]+:[^\s/@]+@|(?:api[_-]?key|password|client_secret|access_token)\s*[=:]\s*["''][A-Za-z0-9_+/=.-]{16,}["''])'
$inventory = foreach($programme in (Get-ChildItem -LiteralPath $Root -Directory -Force | Where-Object {$_.Name -notmatch '^\.' -and $_.Name -notin @('tmp','publication') -and (-not $Names.Count -or $_.Name -in $Names)})) {
    Write-Host "Inspecting $($programme.Name)"
    $files = [Collections.Generic.List[object]]::new()
    $boundaries = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    $omittedDirectories = [Collections.Generic.List[string]]::new()
    $stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($programme.FullName)
    while($stack.Count) {
        $dir = $stack.Pop()
        try { $entries = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) } catch { $errors.Add($dir); continue }
        $gitEntry = $entries | Where-Object Name -eq '.git'
        if($gitEntry) {
            $rel = $dir.Substring($programme.FullName.Length).TrimStart('\').Replace('\','/')
            $boundaries.Add([pscustomobject]@{path=$rel;absolute=$dir;kind=if($gitEntry.PSIsContainer){'repository'}else{'worktree-or-submodule'}})
            if($dir -ne $programme.FullName){continue}
        }
        foreach($entry in $entries) {
            if($entry.PSIsContainer) {if($entry.Name -notmatch $skip -and -not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)){$stack.Push($entry.FullName)}else{$omittedDirectories.Add($entry.FullName.Substring($programme.FullName.Length+1).Replace('\','/'))};continue}
            if($entry.Name -eq '.git'){continue}
            $relative = $entry.FullName.Substring($programme.FullName.Length+1).Replace('\','/')
            $reason = ''
            if($entry.Length -ge 50MB){$reason='bulk-or-oversized'}
            elseif($relative -match '(?i)(^|/)(RAW|03_raw|data_raw|originals|data|01_inputs|01_source|PYDEPS)(/|$)' -and $entry.Name -notmatch '(?i)(manifest|inventory|hash|sha256|acquis|receipt|readme|\.gitkeep)'){$reason='observational-input-or-original'}
            elseif($entry.Name -match '(?i)\.(fits?(\.gz)?|uvfits|h5|hdf5|npz|npy|bin|dat|data|gz|zip|tar|whl|exe|dll|pyd|pyc|part|tmp|temp)$'){$reason='dataset-runtime-or-temporary'}
            elseif($entry.Name -notmatch $allow -and $entry.Name -notmatch '^(\.gitignore|\.gitattributes|\.gitkeep|LICENSE|Makefile)$'){$reason='unclassified-format'}
            elseif($relative -match '(?i)(^|/)(temporary|test_temp.*|.*_test_temp.*|mplconfig|\.matplotlib)(/|$)'){$reason='temporary-products'}
            elseif($entry.Length -gt 10MB){$reason='large-review-required'}
            $secret = $false
            if(-not $reason -and $entry.Extension -notmatch '(?i)^\.(png|gif|pdf)$') {
                try {$content=[IO.File]::ReadAllText($entry.FullName);$secret=$content -match $sensitive} catch {$reason='read-error'}
                if($secret){$reason='credential-pattern-review'}
            }
            $files.Add([pscustomobject]@{path=$relative;bytes=$entry.Length;eligible=(-not $reason);reason=$reason;modified=$entry.LastWriteTimeUtc.ToString('o')})
        }
    }
    $record = [pscustomobject]@{programme=$programme.Name;path=$programme.FullName;boundaries=@($boundaries);files=@($files);omittedDirectories=@($omittedDirectories);errors=@($errors)}
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root ('publication/inventory-'+$programme.Name+'.json')) -Encoding utf8
    $record
}
foreach($p in $inventory){$eligible=@($p.files|Where-Object eligible);'{0}: {1} eligible ({2:N1} MB), {3} excluded, boundaries: {4}, errors: {5}' -f $p.programme,$eligible.Count,(($eligible|Measure-Object bytes -Sum).Sum/1MB),@($p.files|Where-Object {-not $_.eligible}).Count,($p.boundaries.path -join ','),$p.errors.Count}
