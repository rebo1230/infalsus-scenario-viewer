# In Falsus scenario viewer: build site\data.js from your own copy of the game.
#
#   powershell -ExecutionPolicy Bypass -File build.ps1                 (finds the Steam install by itself)
#   powershell -ExecutionPolicy Bypass -File build.ps1 -Game "<install folder>"
#   add  -Images  to also decode song jackets, story text images and CGs from the game (slower)
#   powershell -ExecutionPolicy Bypass -File build.ps1 -Export "<AssetRipper export>"   (also gives images)
#   add  -Repo "<Korean fan translation folder>"  for Korean text when the game itself is not patched
#
# Game folder mode reads the installed game directly (unityread.cs): the story data assets
# inside the Addressables bundles, StringsMapping in resources.assets and the script files in
# StreamingAssets\sam. Nothing in the game folder is changed.
# If the Korean patch is installed, its Korean text is taken from the game itself.
# Output: .\site (viewer data) and .\out (work files)
#
# This file contains no game text or assets. Everything shown by the viewer is read
# at build time from the files you point it to, and written to .\site and .\out on
# your own computer only. Do not share those generated folders.

param(
    [string]$Game = '',     # game install folder (auto-detected from Steam when empty)
    [switch]$Images,        # game-folder mode: also decode song jackets, story text images and CGs (slower)
    [string]$Export = '',   # optional: AssetRipper export instead of the game folder
    [string]$Repo = '',     # optional: Korean fan translation folder (the one holding translation\)
    [string]$Out  = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Out) { $Out = Join-Path $PSScriptRoot 'out' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work    = Join-Path $Out '_scripts'

# start clean: images and extracted data from an earlier build would otherwise be reused
# (out\_repo: a fan translation downloaded by earlier versions of this script)
foreach ($old in (Join-Path $PSScriptRoot 'site\jackets'), (Join-Path $PSScriptRoot 'site\textimg'), (Join-Path $PSScriptRoot 'site\cg'),
                 (Join-Path $Out '_game'), (Join-Path $Out '_ko'), (Join-Path $Out '_img'), (Join-Path $Out '_repo'), $work) {
    if (Test-Path $old) { Remove-Item -Recurse -Force $old }
}

function FindGame {
    # Steam library folders from the registry + libraryfolders.vdf
    $roots = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try { $v = Get-ItemProperty $k -ErrorAction Stop; if ($v.SteamPath) { $roots += $v.SteamPath }; if ($v.InstallPath) { $roots += $v.InstallPath } } catch {}
    }
    $roots += 'C:\Program Files (x86)\Steam'
    foreach ($r in @($roots)) {
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) { foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $roots += $m.Groups[1].Value.Replace('\\', '\') } }
    }
    foreach ($r in ($roots | Select-Object -Unique)) {
        $p = Join-Path ($r -replace '/', '\') 'steamapps\common\In Falsus'
        if (Test-Path (Join-Path $p 'infalsus_Data')) { return $p }
    }
    return $null
}

$patchedKo = $false
# a .\source folder next to this script (saved AssetRipper data + fan translation) is used before the game folder
if (-not $Export -and -not $Game -and (Test-Path (Join-Path $PSScriptRoot 'source\assetripper\ExportedProject\Assets'))) {
    $Export = Join-Path $PSScriptRoot 'source\assetripper'
    Write-Host "source 폴더의 데이터를 읽습니다: $Export"
}
if (-not $Repo -and (Test-Path (Join-Path $PSScriptRoot 'source\kr-patch\translation\names.tsv'))) { $Repo = Join-Path $PSScriptRoot 'source\kr-patch' }
if ($Export) {
    $assets = Join-Path $Export 'ExportedProject\Assets'
    $samDir = Join-Path $assets 'StreamingAssets\sam'
} else {
    if (-not $Game) { $Game = FindGame }
    if (-not $Game -or -not (Test-Path (Join-Path $Game 'infalsus_Data\resources.assets'))) {
        throw 'In Falsus 설치 폴더를 찾지 못했습니다. -Game "설치 폴더" 로 직접 지정해 주세요. (Game folder not found; pass -Game.)'
    }
    $data = Join-Path $Game 'infalsus_Data'
    $samDir = Join-Path $data 'StreamingAssets\sam'
    Write-Host "게임 폴더에서 읽는 중: $Game"
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'unityread.cs')))
    $bundleDir = Join-Path $data 'StreamingAssets\aa\StandaloneWindows64'
    # write the data assets like an AssetRipper export (shorter folder names), under .\out\_game
    $Export = Join-Path $Out '_game'
    $assets = $Export
    $rel = Join-Path $assets 'release'; $release = $rel
    New-Item -ItemType Directory -Force $rel, (Join-Path $assets 'Resources') | Out-Null
    $names = 'StoryTranslationDetails', 'StoryDetails', 'StreamingAssetsMapping', 'DynamicStringMapping', 'SongData'
    $mb = [UnityRead]::FindMonoBehaviours($bundleDir, [string[]]$names)
    foreach ($n in $names) {
        if (-not $mb.ContainsKey($n)) { throw "게임 데이터에서 $n 을(를) 찾지 못했습니다. (asset not found: $n)" }
        [IO.File]::WriteAllText((Join-Path $rel "$n.asset"), [UnityRead]::ToYaml($mb[$n]), $utf8)
    }
    # StringsMapping is read by a fixed layout; if an update changes it, go on without the UI strings
    try { $sm = [UnityRead]::StringsMappingYaml((Join-Path $data 'resources.assets')) }
    catch {
        Write-Host "UI 문구(StringsMapping)를 읽지 못했습니다: 장 이름·시간대·RMI 표시가 비어 있습니다. ($($_.Exception.InnerException.Message))"
        $sm = "%YAML 1.1`n--- !u!114 &11400000`nMonoBehaviour:`n  m_Name: StringsMapping`n  Mappings:`n"
    }
    [IO.File]::WriteAllText((Join-Path $assets 'Resources\StringsMapping.asset'), $sm, $utf8)

    # Korean patch installed? It writes Korean into the English fields ("English-locale carry").
    $tr = @($mb['StoryTranslationDetails']['Translations'])
    $hangul = @($tr | Select-Object -First 400 | Where-Object { $_['English'] -match '[\uAC00-\uD7A3]' }).Count
    # (the English fields then hold Korean, also when -Repo brings a newer translation to use instead)
    if ($hangul -gt 200) { $patchedKo = $true }
    if ($patchedKo -and $Repo) { Write-Host "한국어 패치가 설치된 게임이지만, 한국어는 지정한 번역을 씁니다: $Repo" }
    if ($patchedKo -and -not $Repo) {
        Write-Host '한국어 패치가 설치된 게임입니다: 한국어는 게임에서 바로 가져옵니다.'
        # lay the Korean out like the fan translation's files, so the rest of the build reads it the same way
        $Repo = Join-Path $Out '_ko'
        $tdir = Join-Path $Repo 'translation\ko'
        New-Item -ItemType Directory -Force $tdir | Out-Null
        $nl = [string][char]0x23CE
        foreach ($g in ($tr | Where-Object { $_['Id'] -match '^\d{3}-\d+$' -and $_['English'] } | Group-Object { $_['Id'].Substring(0, 3) })) {
            $lines = $g.Group | ForEach-Object { "$($_['Id'])`t$($_['English'].Replace("`r", '').Replace("`n", $nl))" }
            [IO.File]::WriteAllLines((Join-Path $tdir "$($g.Name).txt"), [string[]]$lines, $utf8)
        }
        $dsm = $mb['DynamicStringMapping']
        $nm = $dsm['rawStoryNameTypeMapping']; $ids = @($nm['IdStr']); $vals = @($nm['IdValues'])
        $lines = for ($i = 0; $i -lt $ids.Count; $i++) { if ($ids[$i] -and $vals[$i]['English']) { "$($ids[$i])`t$($vals[$i]['English'])" } }
        [IO.File]::WriteAllLines((Join-Path $Repo 'translation\names.tsv'), [string[]]@($lines), $utf8)
        foreach ($pair in @(@('encounterIdTypeMapping', 'encounter_names.tsv'), @('encounterOpponentNameTypeMapping', 'encounter_opponent_names.tsv'))) {
            $t = $dsm[$pair[0]]; $ids = @($t['Ids']); $vals = @($t['IdValues'])
            $lines = for ($i = 0; $i -lt $ids.Count; $i++) { if ($vals[$i]['English']) { "$($ids[$i]['Value'])`t`t$($vals[$i]['English'])" } }
            [IO.File]::WriteAllLines((Join-Path $Repo "translation\$($pair[1])"), [string[]]@($lines), $utf8)
        }
        $lines = foreach ($m in [regex]::Matches($sm, '(?m)^  - Key: (\d+)\r?\n    English: ?(.*)$')) {
            $v = $m.Groups[2].Value
            if ($v -match '[\uAC00-\uD7A3]') { "$($m.Groups[1].Value)`t`t$(($v.Trim('"')).Replace('\n', $nl).Replace('\"', '"'))" }
        }
        [IO.File]::WriteAllLines((Join-Path $Repo 'translation\ui_strings.tsv'), [string[]]@($lines), $utf8)
    }
}
if (-not $release) { $release = Join-Path $assets 'BuildSpecificAssets\release' }
if (-not (Test-Path (Join-Path $release 'StoryDetails.asset'))) { throw "Not an AssetRipper export of the game: $Export" }
$hasKo = $Repo -and (Test-Path (Join-Path $Repo 'translation\names.tsv'))
if (-not $hasKo) { Write-Host '한국어 패치가 설치되어 있지 않아 한국어 칸은 비어 있습니다. (no Korean patch in the game: Korean is left empty; or pass -Repo)' }
function RepoLines([string]$rel) {   # lines of a fan-translation file, or nothing when -Repo is absent
    $p = if ($hasKo) { Join-Path $Repo $rel } else { $null }
    if ($p -and (Test-Path $p)) { [IO.File]::ReadAllLines($p, $utf8) } else { @() }
}

# --- 1. decrypt SAM scripts --------------------------------------------------
$key = [byte[]](0xF0,0x16,0x28,0x4B,0x7D,0x9E,0xC3,0xA5)
$map = Get-Content (Join-Path $release 'StreamingAssetsMapping.asset') -Encoding UTF8
for ($i = 0; $i -lt $map.Count; $i++) {
    if ($map[$i] -notmatch '^\s*- FullLookupPath: (.+)$') { continue }
    $p = $matches[1].Trim().Trim("'").Trim('"')
    if ($p -notmatch '\.(sps|spp|spi)$' -or $map[$i+1] -notmatch 'Guid: (\w+)') { continue }
    $b = [IO.File]::ReadAllBytes((Join-Path $samDir $matches[1]))
    for ($j = 0; $j -lt $b.Length; $j++) { $b[$j] = $b[$j] -bxor $key[$j % 8] }
    $dst = Join-Path $work $p
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    [IO.File]::WriteAllBytes($dst, $b)
}

# --- 2. names ----------------------------------------------------------------
$alias = @{}   # script alias ($Xx) -> English name
foreach ($ln in [IO.File]::ReadAllLines((Join-Path $work 'assets\scripts\names.spp'), $utf8)) {
    if ($ln -match '^alias\s+(\$\w+)\s+"(.*)"') { $alias[$matches[1]] = $matches[2] }
}
$ko = @{}      # English name -> Korean name
foreach ($ln in (RepoLines 'translation\names.tsv')) {
    if ($ln -match '^#' -or $ln -notmatch "`t") { continue }
    $a = $ln.Split("`t"); $ko[$a[0]] = ($a[1] -replace '<ruby>(.*?)<rt>.*?</rt></ruby>', '$1')
}
function KoName([string]$en) {
    $base = $en.TrimStart('*')
    if ($ko.ContainsKey($base)) { return $ko[$base] }
    return $base
}
$povCode = @{ 0='Ni'; 1='Me'; 2='Ay'; 3='Ir'; 4='St'; 14='Xt' }
# viewpoint names come from the script's own alias table ($Ni -> its English name)
$povEn = @{}
foreach ($c in $povCode.Values) { $povEn[$c] = if ($c -ne 'Xt' -and $alias.ContainsKey("`$$c")) { $alias["`$$c"] } else { 'Special' } }
# Xt ("special") episodes never name their viewpoint in-game, so it stays blank (KO, TC, SC, JP)
$povSpecial = @{
    Special = @('', '', '', '')
}
function Unyaml([string[]]$parts) {
    $first = $parts[0]
    if ($first.StartsWith('"')) {
        $s = ($parts | ForEach-Object { $_.Trim() }) -join ' '
        $s = $s.Substring(1, $s.Length - 2)
        $s = [regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
        return $s.Replace('\ ', '').Replace('\n', "`n").Replace('\"', '"').Replace('\\', '\')
    }
    if ($first.StartsWith("'")) {
        $s = ($parts | ForEach-Object { $_.Trim() }) -join ' '
        return $s.Substring(1, $s.Length - 2).Replace("''", "'")
    }
    return (($parts | ForEach-Object { $_.Trim() }) -join ' ')
}
# UI strings (chapter names, time slots, RMI coverage) come from the game's StringsMapping,
# Korean from the fan translation's ui_strings.tsv (same integer keys)
$uiStr = @{}   # key -> @{ en; jp; tc; sc; ko }
$sm = [IO.File]::ReadAllLines((Join-Path $assets 'Resources\StringsMapping.asset'), $utf8)
$k = $null
foreach ($ln in $sm) {
    if ($ln -match '^  - Key: (\d+)') { $k = [int]$matches[1]; $uiStr[$k] = @{ en = ''; jp = ''; tc = ''; sc = ''; ko = '' }; continue }
    if ($null -eq $k) { continue }
    if ($ln -match '^    (English|Japanese|TraditionalChinese|SimplifiedChinese): ?(.*)$') {
        $f = @{ English = 'en'; Japanese = 'jp'; TraditionalChinese = 'tc'; SimplifiedChinese = 'sc' }[$matches[1]]
        $uiStr[$k][$f] = Unyaml @($matches[2])
    }
}
$koByName = @{}   # the fan translation also names each key (Str.Strings.Key member)
foreach ($ln in (RepoLines 'translation\ui_strings.tsv')) {
    if ($ln -match '^(\d+)\t([^\t]*)\t(.+)$') {
        if ($matches[2]) { $koByName[$matches[2]] = $matches[3] }
        if ($uiStr.ContainsKey([int]$matches[1])) { $uiStr[[int]$matches[1]].ko = $matches[3] }
    }
}
# the UI strings used below, by key name: the number the game uses today + a short hash of the Japanese text
# (which the Korean patch leaves alone). A game update can renumber the strings by adding new ones in the
# middle; then each is found again by its hash.
$uiNeed = [ordered]@{
    Act1Name = 504, '6702f8cd'; Act2Name = 505, '9e3df5f0'; Act2_5Name = 506, '2df7912f'; Act3Name = 507, '8b59c933'; Act4Name = 508, 'a11e7ca8'
    TimeOfDay_AfterMidnight = 179, '4dc69c9e'; TimeOfDay_Sunrise = 180, '02beeadc'; TimeOfDay_Morning = 181, '695aad81'
    TimeOfDay_Noon = 182, '56c5ea57'; TimeOfDay_Afternoon = 183, '3ad626b4'; TimeOfDay_Evening = 184, '8198153f'
    TimeOfDay_Night = 185, '2d8f0e9d'; TimeOfDay_LateNight = 186, '0e458fad'; TimeOfDay_Midnight = 187, '6bb9a1f7'
    Story_RmiCoverage = 791, 'adcae984'; Story_IntroVideo_Scattered = 792, 'feb9d480'; Story_IntroVideo_Stable = 891, 'd0d2a34c'
    Story_IntroVideo_Thin = 892, '6de8c146'; Story_IntroVideo_Dense = 893, '7ac9775a'; Story_IntroVideo_Islands = 894, '97c62913'
    Story_IntroVideo_Shifting = 895, 'e5fbc0f5'; Story_IntroVideo_LowVisibility = 896, '939c9fff'; Story_IntroVideo_Splitting = 897, 'ca77d415'
    Story_IntroVideo_Needling = 898, '880e590e'
}
$sha1 = [Security.Cryptography.SHA1]::Create()
function JpHash([string]$s) { -join ($sha1.ComputeHash($utf8.GetBytes($s))[0..3] | ForEach-Object { $_.ToString('x2') }) }
$byHash = @{}; foreach ($k in $uiStr.Keys) { if ($uiStr[$k].jp) { $byHash[(JpHash $uiStr[$k].jp)] = $k } }
$uiKey = @{}; $moved = 0; $lost = @()
foreach ($nm in $uiNeed.Keys) {
    $k0 = $uiNeed[$nm][0]; $h = $uiNeed[$nm][1]
    if ($uiStr.ContainsKey($k0) -and (JpHash $uiStr[$k0].jp) -eq $h) { $uiKey[$nm] = $k0 }
    elseif ($byHash.ContainsKey($h)) { $uiKey[$nm] = $byHash[$h]; $moved++ }
    else { $uiKey[$nm] = $k0; $lost += $nm }   # wording changed: keep today's number
    if ($koByName.ContainsKey($nm)) {   # Korean by name, even when the game's strings could not be read
        if (-not $uiStr.ContainsKey($uiKey[$nm])) { $uiStr[$uiKey[$nm]] = @{ en = ''; jp = ''; tc = ''; sc = ''; ko = '' } }
        $uiStr[$uiKey[$nm]].ko = $koByName[$nm]
    }
}
if ($moved) { Write-Host "게임 업데이트로 UI 문구 번호가 바뀌어 $moved 개를 다시 찾았습니다." }
# (when the game's strings could not be read at all, that was already reported)
if ($lost.Count -and $byHash.Count) { Write-Host "UI 문구 $($lost.Count)개의 일본어가 바뀌어 원래 번호로 읽습니다 (장 이름·시간대·RMI 표시를 확인해 주세요): $($lost -join ', ')" }
# a patched game has Korean in its English fields: those are not English, so leave them out
function NotKo([string]$s) { if ($patchedKo -and $s -match '[가-힣]') { '' } else { $s } }
function Ui([int]$key, [string]$lang) { $v = $uiStr[$key]; if (-not $v) { return '' }; if ($v[$lang]) { if ($lang -eq 'en') { NotKo $v.en } else { $v[$lang] } } else { NotKo $v.en } }

# chapter = act number + its name (StringsMapping Act1Name..Act4Name); the numbering format is the viewer's own
$actKey = [ordered]@{ 'Y1-1' = @('1', 'Act1Name'); 'Y1-2' = @('2', 'Act2Name'); 'Y1-2_5' = @('2.5', 'Act2_5Name'); 'Y1-3' = @('3', 'Act3Name'); 'Y1-4' = @('4', 'Act4Name') }
$chapters = [ordered]@{}; $chaptersJP = @{}; $chaptersEN = @{}; $chaptersTC = @{}; $chaptersSC = @{}
foreach ($ck in $actKey.Keys) {
    $no = $actKey[$ck][0]; $sk = $uiKey[$actKey[$ck][1]]
    $chapters[$ck]   = "${no}장 「$(Ui $sk 'ko')」"
    $chaptersJP[$ck] = "第${no}章「$(Ui $sk 'jp')」"
    $chaptersEN[$ck] = $(if (Ui $sk 'en') { "Arc ${no}「$(Ui $sk 'en')」" } else { "Arc ${no}" })
    $chaptersTC[$ck] = "第${no}章「$(Ui $sk 'tc')」"
    $chaptersSC[$ck] = "第${no}章「$(Ui $sk 'sc')」"
}
$yearBase = 10276   # in-story year: ID year 1 = 10277
# slot letters A..I = TimeOfDay_AfterMidnight .. TimeOfDay_Midnight
$slotKo = @{}; $i = 0
$slotNames = 'AfterMidnight', 'Sunrise', 'Morning', 'Noon', 'Afternoon', 'Evening', 'Night', 'LateNight', 'Midnight'
foreach ($sl in 'A','B','C','D','E','F','G','H','I') { $slotKo[$sl] = Ui $uiKey["TimeOfDay_$($slotNames[$i])"] $(if ($hasKo) { 'ko' } else { 'en' }); $i++ }
# RMI coverage label + the nine intro-video states, in IntroVideoKey order
$rmiLang = { param($key) "{`"ko`":$(J (Ui $key 'ko')),`"jp`":$(J (Ui $key 'jp')),`"en`":$(J (Ui $key 'en')),`"tc`":$(J (Ui $key 'tc')),`"sc`":$(J (Ui $key 'sc'))}" }

# --- 3. Korean + Japanese text ----------------------------------------------
$koText = @{}
foreach ($f in $(if ($hasKo) { Get-ChildItem (Join-Path $Repo 'translation\ko') -Filter *.txt } else { @() })) {
    foreach ($ln in [IO.File]::ReadAllLines($f.FullName, $utf8)) {
        if ($ln -match '^(\d{3}-\d+)\t(.*)$') { $koText[$matches[1]] = $matches[2].Replace([string][char]0x23CE, "`n") }
    }
}
$tlText = @{ Japanese = @{}; ChineseTC = @{}; ChineseSC = @{} }
$tl = [IO.File]::ReadAllLines((Join-Path $release 'StoryTranslationDetails.asset'), $utf8)
$cur = $null
for ($i = 0; $i -lt $tl.Count; $i++) {
    if ($tl[$i] -match '^  - Id: (\S+)') { $cur = $matches[1]; continue }
    if ($cur -and $tl[$i] -match '^    (Japanese|ChineseTC|ChineseSC): ?(.*)$') {
        $field = $matches[1]; $parts = @($matches[2])
        while ($i + 1 -lt $tl.Count -and $tl[$i+1] -match '^      ') { $i++; $parts += $tl[$i] }
        if ($parts[0] -ne '') { $tlText[$field][$cur] = Unyaml $parts }
    }
}
$jpText = $tlText.Japanese

# Chinese speaker names: DynamicStringMapping.rawStoryNameTypeMapping (IdStr[i] <-> IdValues[i])
$zh = @{}      # English name -> @(TC, SC, JP)
$dl = [IO.File]::ReadAllLines((Join-Path $release 'DynamicStringMapping.asset'), $utf8)
$i = [array]::IndexOf($dl, '  rawStoryNameTypeMapping:')
while ($dl[$i] -ne '    IdStr:') { $i++ }
$keys = New-Object System.Collections.ArrayList
for ($i++; $dl[$i] -match '^    - ?(.*)$'; $i++) { [void]$keys.Add((Unyaml @($matches[1]))) }
while ($dl[$i] -ne '    IdValues:') { $i++ }
$n = -1; $en = $null
for ($i++; $i -lt $dl.Count -and $dl[$i] -match '^    [- ] '; $i++) {
    if ($dl[$i] -match '^    - English: ?(.*)$') { $n++; $en = Unyaml @($matches[1]); $zh[$keys[$n]] = @('', '', ''); if ($en) { $zh[$en] = $zh[$keys[$n]] } }
    elseif ($dl[$i] -match '^      Japanese: ?(.*)$') { $zh[$keys[$n]][2] = Unyaml @($matches[1]) }
    elseif ($dl[$i] -match '^      TraditionalChinese: ?(.*)$') { $zh[$keys[$n]][0] = Unyaml @($matches[1]) }
    elseif ($dl[$i] -match '^      SimplifiedChinese: ?(.*)$') { $zh[$keys[$n]][1] = Unyaml @($matches[1]) }
}
function ZhName([string]$en, [int]$k) {
    $base = $en.TrimStart('*')
    if ($zh.ContainsKey($base) -and $zh[$base][$k]) { return $zh[$base][$k] }
    # script aliases use letters where the table uses numbers ("Voice A" vs "Voice 1")
    if ($base -match '^(.*) ([A-E])$') {
        $alt = "$($matches[1]) $([int][char]$matches[2] - 64)"
        if ($zh.ContainsKey($alt) -and $zh[$alt][$k]) { return $zh[$alt][$k] }
    }
    return $base
}
function PovLabel([string]$key, [int]$lang) {   # lang: 0=KO 1=TC 2=SC
    if ($povSpecial.ContainsKey($key)) { return $povSpecial[$key][$lang] }
    if ($lang -eq 0) { return KoName $key }
    return ZhName $key ($lang - 1)
}

# --- 4. story order (chronological) + unlock graph ---------------------------
$sd = [IO.File]::ReadAllLines((Join-Path $release 'StoryDetails.asset'), $utf8)
$sec = @{}
for ($i = 0; $i -lt $sd.Count; $i++) { if ($sd[$i] -match '^  (\w+):\s*$') { $sec[$matches[1]] = $i } }
function SectionRange($name) {
    $start = $sec[$name]; $ends = $sec.Values | Where-Object { $_ -gt $start } | Sort-Object
    $end = if ($ends) { @($ends)[0] } else { $sd.Count }
    return $start..($end - 1)
}
function Decode([int64]$v) {
    $slot = [char](65 + (($v -shr 15) -band 15))
    [pscustomobject]@{
        Id = $v; Year = ($v -shr 28); Month = (($v -shr 24) -band 15); Day = (($v -shr 19) -band 31)
        Slot = $slot; Num = (($v -shr 11) -band 15); Pov = $povCode[[int](($v -shr 3) -band 31)]; Other = (($v -band 7) -eq 4)
    }
}
$files = @{}
foreach ($f in Get-ChildItem (Join-Path $work 'scenario_wip') -Recurse -Filter *.sps) {
    if ($f.BaseName -match '^Y(\d)-(\d+)-(\d+)([A-Z])-(\d+)(-O)?_(\w+)$') {
        $files["$($matches[1])-$($matches[2])-$($matches[3])$($matches[4])-$($matches[5])_$($matches[7])"] = $f
    }
}
$stories = New-Object System.Collections.ArrayList
$byId = @{}
foreach ($i in (SectionRange 'orderedStoryEntries')) {
    if ($sd[$i] -notmatch 'underlyingValue: (\d+)') { continue }
    $d = Decode ([int64]$matches[1])
    $f = $files["$($d.Year)-$($d.Month)-$($d.Day)$($d.Slot)-$($d.Num)_$($d.Pov)"]
    $d | Add-Member Chrono ($stories.Count + 1)
    $d | Add-Member File $f
    $pk = $povEn[$d.Pov]
    $d | Add-Member PovName (PovLabel $pk 0)
    $d | Add-Member PovTC (PovLabel $pk 1)
    $d | Add-Member PovSC (PovLabel $pk 2)
    $d | Add-Member PovKey $pk
    $d | Add-Member Chapter $f.Directory.Name.Replace('scenario_', '')
    $d | Add-Member Requires (New-Object System.Collections.ArrayList)
    $d | Add-Member Video ($(if ($sd[$i+1] -match 'IntroVideoKey: (\d+)') { [int]$matches[1] } else { 0 }))
    $d | Add-Member Clock ($sd[$i+2] -match 'CanShowClock: 1')
    $d | Add-Member Song ''
    $d | Add-Member Encounter ''
    [void]$stories.Add($d); $byId[$d.Id] = $d
}
$rng = @(SectionRange 'orderedStoryEntryUnlockRequirements'); $tgt = $null
foreach ($i in $rng) {
    if ($sd[$i] -match 'TargetStory:') { $tgt = $null }
    if ($sd[$i] -match 'underlyingValue: (\d+)') {
        $v = [int64]$matches[1]
        if ($sd[$i-1] -match 'TargetStory:') { $tgt = $byId[$v] }
        elseif ($tgt -and $sd[$i-1] -match 'RequiredRead:') { [void]$tgt.Requires.Add($v) }
    }
}
foreach ($i in (SectionRange 'orderedStoryEntrySongPlayRequirements')) {
    if ($sd[$i] -match 'underlyingValue: (\d+)') { $tgt = $byId[[int64]$matches[1]] }
    if ($sd[$i] -match 'SongId: (\S+)' -and $tgt) { $tgt.Song = $matches[1] }
}
foreach ($i in (SectionRange 'orderedStoryEntryEncounterRequirements')) {
    if ($sd[$i] -match 'underlyingValue: (\d+)') { $tgt = $byId[[int64]$matches[1]] }
    if ($sd[$i] -match '^\s+Value: (\d+)' -and $tgt) { $tgt.Encounter = $matches[1] }
}
# play order: topological sort, ties broken by chronology
$done = @{}; $play = New-Object System.Collections.ArrayList
while ($play.Count -lt $stories.Count) {
    $next = $stories | Where-Object { -not $done[$_.Id] -and (@($_.Requires | Where-Object { $byId.ContainsKey($_) -and -not $done[$_] }).Count -eq 0) } | Select-Object -First 1
    if (-not $next) { $next = $stories | Where-Object { -not $done[$_.Id] } | Select-Object -First 1 }  # cycle guard
    $done[$next.Id] = $true; [void]$play.Add($next); $next | Add-Member Play $play.Count
}

# --- 5. parse scripts ---------------------------------------------------------
# placement of story pictures as the script writes it: x y anchorX anchorY scaleX scaleY (y counts from the bottom),
# often through aliases from common.spp ($cgCenter, $arcNo ...)
$placeAlias = @{}
$commonSpp = Join-Path $work 'assets\scripts\common.spp'
if (Test-Path $commonSpp) { foreach ($ln in [IO.File]::ReadAllLines($commonSpp)) { if ($ln -match '^alias (\$\w+)((?:\s+-?[\d.]+)+)') { $placeAlias[$matches[1]] = @($matches[2].Trim() -split '\s+' | ForEach-Object { [double]$_ }) } } }
function Place([string]$rest) {
    $nums = @(); foreach ($tok in ($rest.Trim() -split '\s+')) { if ($placeAlias.ContainsKey($tok)) { $nums += $placeAlias[$tok] } elseif ($tok -match '^-?[\d.]+$') { $nums += [double]$tok } }
    if ($nums.Count -ge 6) { return ,@($nums[0..5]) } else { return $null }
}
$rows = New-Object System.Collections.ArrayList
foreach ($s in $stories) {
    $L = [IO.File]::ReadAllLines($s.File.FullName, $utf8)
    $s | Add-Member Lines (New-Object System.Collections.ArrayList)
    $s | Add-Member Bgs (New-Object System.Collections.ArrayList)
    $s | Add-Member TextShows (New-Object System.Collections.ArrayList)   # baked-text images: @{pos; name; obj; revealPos}
    $s | Add-Member -NotePropertyName CreditsPos -NotePropertyValue ([int]-1)
    $s | Add-Member CgEvents (New-Object System.Collections.ArrayList)   # first appearance of each CG: @{pos; name}
    $cgObjs = @{}   # object name -> @{name; pos; state = pending | hidden | visible}
    $addCg = { param($name, $pos, $place) if (-not ($s.CgEvents | Where-Object { $_.name -eq $name })) { [void]$s.CgEvents.Add(@{ pos = $pos; name = $name; place = $place }) } }
    $sid = $null; $lid = $null; $choice = $null
    for ($i = 0; $i -lt $L.Count; $i++) {
        $t = $L[$i].Trim()
        if ($t -match '^bg_(?:init|change|show)\s+\$(\w+)') { if (-not $s.Bgs.Contains($matches[1])) { [void]$s.Bgs.Add($matches[1]) } }
        if ($t -match '^show\s+"([^"]+)"\s+"text/([^"]+)\.png"\s*(.*)$') {
            # position = number of dialogue lines already passed, so the image sits before the next one
            $obj = $matches[1]; $rest = $matches[3]; $base = $matches[2] -replace '_(en|jp|hant|hans)\d*$', ''; $place = Place $rest
            if (-not ($s.TextShows | Where-Object { $_.name -eq $base })) { [void]$s.TextShows.Add(@{ pos = $s.Lines.Count; name = $base; obj = $obj; revealPos = -1; hidden = $false; place = $place }) }
        }
        # CGs: a show that is made invisible before the next line only counts once it turns visible
        # (a CG can also come up as the scene background: bg_init / bg_change)
        if ($t -match '^(?:show|bg_init|bg_change|bg_show)\s+"([^"]+)"\s+"cg/([^"]+)\.png"\s*(.*)$') { $o = $matches[1]; $cn = $matches[2]; $cgObjs[$o] = @{ name = $cn; pos = $s.Lines.Count; state = 'pending'; place = (Place $matches[3]) } }
        # an image loaded invisible and faded in later is really shown where it becomes visible
        # (fades are written either as $visible / $invisible or as an RGBA colour: alpha > 0 means it shows)
        $o = $null
        if ($t -match '^color\s+"([^"]+)"\s+\$(invisible|visible)') { $o = $matches[1]; $vis = $matches[2] -eq 'visible' }
        elseif ($t -match '^color\s+"([^"]+)"\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+([\d.]+)') { $o = $matches[1]; $vis = [double]$matches[2] -gt 0 }
        if ($o) {
            foreach ($ts in $s.TextShows) {
                if ($ts.obj -ne $o) { continue }
                if (-not $vis) { $ts.hidden = $true } elseif ($ts.hidden -and $ts.revealPos -lt 0) { $ts.revealPos = $s.Lines.Count }
            }
            if ($cgObjs.ContainsKey($o)) {
                $co = $cgObjs[$o]
                # hidden again after the script waited: it was on screen (e.g. an opening shot before the first line)
                if (-not $vis -and $co.state -eq 'pending' -and $co.waited) { & $addCg $co.name $co.pos $co.place; $co.state = 'visible' }
                elseif (-not $vis -and $co.state -eq 'pending') { $co.state = 'hidden' }
                elseif ($vis -and $co.state -eq 'hidden') { & $addCg $co.name $s.Lines.Count $co.place; $co.state = 'visible' }
            }
        }
        if ($t -match '^(wait|delay)\b') { foreach ($co in $cgObjs.Values) { if ($co.state -eq 'pending') { $co.waited = $true } } }
        if ($t -match '^id \d{3}-\d+$') {
            foreach ($co in $cgObjs.Values) { if ($co.state -eq 'pending') { & $addCg $co.name $co.pos $co.place; $co.state = 'visible' } }
        }
        if ($t -eq '"bgm_credits"') { $s.CreditsPos = $s.Lines.Count }
        # choice "group" "option" { ... }: lines inside belong to that option
        if ($t -match '^choice\s+"(\w+)"\s+"(\w+)"') { $choice = "$($matches[1]):$($matches[2])"; continue }
        if ($choice -and $t -eq '}') { $choice = $null; continue }
        if ($t -match '^id (\d{3})-(\d+)$') { $lid = "$($matches[1])-$($matches[2])"; $sid = $matches[1]; continue }
        if (-not $lid) { continue }
        if ($t -match '^(s|phone message (left|right)|log)\s+(\$\w+\s+)?`') {
            $kind = $matches[1]; $a = if ($matches[3]) { $matches[3].Trim() } else { '' }
            # backtick string may span lines
            $txt = $L[$i].Substring($L[$i].IndexOf('`') + 1)
            while ($txt -notmatch '`\s*$' -and $i + 1 -lt $L.Count) { $i++; $txt += "`n" + $L[$i] }
            $txt = $txt -replace '`\s*$', ''
            if ($a) {
                $en = $alias[$a]; if (-not $en) { $en = $a }
                $spk = KoName $en; $spkTC = ZhName $en 0; $spkSC = ZhName $en 1; $narr = $false
            } else {
                $en = ''; $spk = "$($s.PovName) (서술)".TrimStart(); $spkTC = "$($s.PovTC)（敘述）"; $spkSC = "$($s.PovSC)（叙述）"; $narr = $true
            }
            if ($kind -like 'phone*') { $spk += ' [메신저]'; $spkTC += ' [訊息]'; $spkSC += ' [消息]' }
            elseif ($kind -eq 'log') { $spk = '[로그]'; $spkTC = '[記錄]'; $spkSC = '[记录]' }
            $row = [pscustomobject]@{
                Chrono = $s.Chrono; Play = $s.Play; Chapter = $s.Chapter; Story = $sid; LineId = $lid
                Date = "$($s.Year + $yearBase)-$($s.Month)-$($s.Day)"; Slot = $s.Slot; Pov = $s.Pov
                Kind = $kind; Choice = $choice; Alias = $a; SpeakerEn = $en; Speaker = $spk; SpeakerTC = $spkTC; SpeakerSC = $spkSC; Narration = $narr
                EN = $txt; JP = $jpText[$lid]; KO = $koText[$lid]; TC = $tlText.ChineseTC[$lid]; SC = $tlText.ChineseSC[$lid]
            }
            [void]$rows.Add($row); [void]$s.Lines.Add($row)
            $lid = $null
        }
    }
    foreach ($co in $cgObjs.Values) { if ($co.state -eq 'pending') { & $addCg $co.name $co.pos $co.place } }
    $s | Add-Member Story ($(if ($s.Lines.Count) { $s.Lines[0].Story } else { '—' }))
}

# --- 6. write outputs ----------------------------------------------------------
foreach ($d in 'script', 'script_zh_tc', 'script_zh_sc') { New-Item -ItemType Directory -Force (Join-Path $Out $d) | Out-Null }
function W($path, $text) { [IO.File]::WriteAllText((Join-Path $Out $path), $text, $utf8) }
function Cell($x) { if ($null -eq $x) { '' } else { ($x -replace "`t", ' ') -replace "`r?`n", '\n' } }

# all_lines.tsv
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("chrono`tplay`tchapter`tstory`tline_id`tdate`tslot`tpov`talias`tspeaker_en`tspeaker_ko`tspeaker_tc`tspeaker_sc`tnarration`tEN`tJP`tKO`tZH_TC`tZH_SC")
foreach ($r in $rows) {
    [void]$sb.AppendLine((@($r.Chrono, $r.Play, $r.Chapter, $r.Story, $r.LineId, $r.Date, $r.Slot, $r.Pov, $r.Alias, $r.SpeakerEn, $r.Speaker, $r.SpeakerTC, $r.SpeakerSC, [int]$r.Narration, (Cell $r.EN), (Cell $r.JP), (Cell $r.KO), (Cell $r.TC), (Cell $r.SC)) -join "`t"))
}
W 'all_lines.tsv' $sb.ToString()

# per-chapter scripts (chronological): Korean, Traditional Chinese, Simplified Chinese
$langs = @(
    @{ Dir = 'script';       Text = 'KO'; Spk = 'Speaker';   Pov = 'PovName'; Titles = $chapters }
    @{ Dir = 'script_zh_tc'; Text = 'TC'; Spk = 'SpeakerTC'; Pov = 'PovTC';   Titles = $chaptersTC }
    @{ Dir = 'script_zh_sc'; Text = 'SC'; Spk = 'SpeakerSC'; Pov = 'PovSC';   Titles = $chaptersSC }
)
foreach ($lg in $langs) {
  foreach ($ch in $chapters.Keys) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# $($lg.Titles[$ch])`n")
    foreach ($s in ($stories | Where-Object Chapter -eq $ch)) {
        $o = ''
        [void]$sb.AppendLine("## [$('{0:D3}' -f $s.Chrono)] $($s.Year + $yearBase)년 $($s.Month)/$($s.Day) $($s.Slot)·$($slotKo[[string]$s.Slot]) — 시점: $($s.($lg.Pov))$o")
        [void]$sb.AppendLine("ID $($s.Story) · ``$($s.File.BaseName)`` · 플레이 순서 $($s.Play) · 배경: $(($s.Bgs) -join ', ')`n")
        foreach ($r in $s.Lines) {
            $k = if ($r.($lg.Text)) { $r.($lg.Text) } else { "(번역 없음) $($r.EN)" }
            [void]$sb.AppendLine("- ``$($r.LineId)`` **$($r.($lg.Spk))**: $($k -replace "`r?`n", ' / ')")
        }
        [void]$sb.AppendLine()
    }
    W "$($lg.Dir)\$ch.md" $sb.ToString()
  }
}

# timeline.md
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("# In Falsus 스토리 타임라인`n")
[void]$sb.AppendLine("- 순서 기준: ``StoryDetails.orderedStoryEntries`` (식별자 비트 = 연·월·일·시간대·번호·시점). 플레이 순서는 ``RequiredRead`` 해금 조건으로 위상 정렬.")
[void]$sb.AppendLine("- 시간대 A~I (인게임 표기): A 자정 이후 · B 새벽 · C 아침 · D 정오 · E 오후 · F 저녁 · G 밤 · H 심야 · I 자정`n")
foreach ($ch in $chapters.Keys) {
    $cs = @($stories | Where-Object Chapter -eq $ch)
    $first = $cs[0]; $last = $cs[-1]
    [void]$sb.AppendLine("## $($chapters[$ch])")
    [void]$sb.AppendLine("기간 $($first.Year + $yearBase)년 $($first.Month)/$($first.Day) ~ $($last.Year + $yearBase)년 $($last.Month)/$($last.Day) · 에피소드 $($cs.Count)개 · 대사 $(($cs | ForEach-Object { $_.Lines.Count } | Measure-Object -Sum).Sum)줄`n")
    [void]$sb.AppendLine("| # | 날짜 | 시간대 | 시점 | ID | 플레이 | 줄 | 주요 화자 | 해금 |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|---|---|---|")
    foreach ($s in $cs) {
        $top = ($s.Lines | Where-Object { -not $_.Narration -and $_.Speaker -notlike '`[*' } | Group-Object Speaker | Sort-Object Count -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
        $unl = @(); if ($s.Song) { $unl += "곡 $($s.Song)" }; if ($s.Encounter) { $unl += "조우 #$($s.Encounter)" }
        $o = ''
        [void]$sb.AppendLine("| $($s.Chrono) | $($s.Year + $yearBase)년 $($s.Month)/$($s.Day) | $($s.Slot) $($slotKo[[string]$s.Slot]) | $($s.PovName)$o | $($s.Story) | $($s.Play) | $($s.Lines.Count) | $top | $($unl -join ', ') |")
    }
    [void]$sb.AppendLine()
}
W 'timeline.md' $sb.ToString()

# speakers.md
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("# 화자 분석`n")
[void]$sb.AppendLine("## 시점(POV) 캐릭터별 에피소드 수`n")
[void]$sb.AppendLine("| 시점 | " + (($chapters.Values | ForEach-Object { $_ }) -join ' | ') + " | 합계 |")
[void]$sb.AppendLine("|---|" + ('---|' * ($chapters.Count + 1)))
foreach ($p in ($stories | Group-Object PovName | Sort-Object { $_.Group[0].Pov -eq 'Xt' }, { - $_.Count } | ForEach-Object Name)) {
    $cells = foreach ($ch in $chapters.Keys) { @($stories | Where-Object { $_.Chapter -eq $ch -and $_.PovName -eq $p }).Count }
    [void]$sb.AppendLine("| $(if ($p) { $p } else { '특수 (시점 미표기)' }) | $($cells -join ' | ') | $(@($stories | Where-Object PovName -eq $p).Count) |")
}
[void]$sb.AppendLine("`n## 발화 화자별 대사 수 (서술 제외)`n")
[void]$sb.AppendLine("| 화자 | 원문 이름 | 번체 | 간체 | " + (($chapters.Keys | ForEach-Object { $_ }) -join ' | ') + " | 합계 | 첫 등장 |")
[void]$sb.AppendLine("|---|---|---|---|" + ('---|' * ($chapters.Count + 2)))
$spoken = $rows | Where-Object { -not $_.Narration -and $_.Speaker -ne '[로그]' }
foreach ($g in ($spoken | Group-Object { $_.Speaker -replace ' \[메신저\]$', '' } | Sort-Object Count -Descending)) {
    $cells = foreach ($ch in $chapters.Keys) { @($g.Group | Where-Object Chapter -eq $ch).Count }
    $f = $g.Group | Sort-Object Chrono | Select-Object -First 1
    $ens = ($g.Group | Select-Object -ExpandProperty SpeakerEn -Unique) -join ' / '
    $tcs = ($g.Group | ForEach-Object { $_.SpeakerTC -replace ' \[訊息\]$', '' } | Select-Object -Unique) -join ' / '
    $scs = ($g.Group | ForEach-Object { $_.SpeakerSC -replace ' \[消息\]$', '' } | Select-Object -Unique) -join ' / '
    [void]$sb.AppendLine("| $($g.Name) | $ens | $tcs | $scs | $($cells -join ' | ') | $($g.Count) | $($f.Date) ($($f.LineId)) |")
}
[void]$sb.AppendLine("`n## 서술(독백) 줄 수 — 시점별`n")
foreach ($g in ($rows | Where-Object Narration | Group-Object Speaker | Sort-Object Count -Descending)) { [void]$sb.AppendLine("- $($g.Name): $($g.Count)") }
W 'speakers.md' $sb.ToString()

# scenario viewer data: site\data.js (window.IF_DATA)
function J($x) {
    if ($null -eq $x) { return 'null' }
    if ($x -is [bool]) { return $(if ($x) { 'true' } else { 'false' }) }
    if ($x -is [int] -or $x -is [int64]) { return [string]$x }
    $s = [string]$x
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n').Replace("`t", '\t').Replace('</', '<\/')
    return '"' + $s + '"'
}
function JNames($ko, $jp, $en, $tc, $sc) { "{`"ko`":$(J $ko),`"jp`":$(J $jp),`"en`":$(J $en),`"tc`":$(J $tc),`"sc`":$(J $sc)}" }
# pictures: from the data source when it has them (AssetRipper export), otherwise with -Images decoded from the game into out\_img
$imgDir = Join-Path $Out '_img'
function Src([string]$primary, [string]$sub, [string]$file) { if (Test-Path $primary) { $primary } else { Join-Path (Join-Path $imgDir $sub) $file } }
if ($Images) {
    if (-not $bundleDir) {
        $g = if ($Game) { $Game } else { FindGame }
        if ($g) {
            Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'unityread.cs')))
            $bundleDir = Join-Path $g 'infalsus_Data\StreamingAssets\aa\StandaloneWindows64'
        } else { Write-Host '게임 폴더를 찾지 못해 이미지는 데이터에 있는 것만 씁니다.' }
    }
    $req = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $tdir = Join-Path $release 'sp-story\assets\text'; $cdir = Join-Path $release 'sp-story\assets\cg'
    $want = @()
    foreach ($b in ($stories | Where-Object Song | ForEach-Object Song | Sort-Object -Unique)) { $want += ,@($b, (Join-Path $assets "Texture2D\$b.png"), 'Texture2D') }
    $textNames = @($stories | ForEach-Object { $_.TextShows } | ForEach-Object { $_.name }) + @('RMI_mainline', 'RMI_time_A', 'RMI_nine', 'RMI_time_B')
    foreach ($n in ($textNames | Sort-Object -Unique)) { $want += ,@($n, (Join-Path $tdir "$n.png"), 'text'); foreach ($suf in '_en', '_jp', '_hant', '_hans') { $want += ,@("$n$suf", (Join-Path $tdir "$n$suf.png"), 'text') } }
    $want += ,@('RMI_visual', (Join-Path $tdir 'RMI_visual.png'), 'text')
    foreach ($n in ($stories | ForEach-Object { $_.CgEvents } | ForEach-Object { $_.name } | Sort-Object -Unique)) { $want += ,@($n, (Join-Path $cdir "$n.png"), 'cg') }
    foreach ($w in $want) { if (-not (Test-Path $w[1])) { $req[$w[0]] = Join-Path (Join-Path $imgDir $w[2]) "$($w[0]).png" } }
    if ($bundleDir -and $req.Count) {
        Write-Host "게임에서 이미지를 가져오는 중입니다 (곡 자켓, 연출 이미지, CG: $($req.Count)개 찾는 중)..."
        $got = [UnityRead]::ExportTextures($bundleDir, $req)
        Write-Host "이미지 $got 개"
    }
}
# songs used as unlock conditions: title/artist + jacket (Texture2D\<BaseName>.png -> site\jackets\<BaseName>.jpg)
$songNum = @{}   # alamode -> 2
$sdl = [IO.File]::ReadAllLines((Join-Path $release 'SongData.asset'), $utf8)
for ($i = 0; $i -lt $sdl.Count - 2; $i++) {
    if ($sdl[$i] -eq '  - Id:' -and $sdl[$i+1] -match '^      Value: (\d+)' -and $sdl[$i+2] -match '^    BaseName: (\S+)') { $songNum[$matches[1]] = 0 + ($sdl[$i+1] -replace '\D', '') }
}
function ReadIdTable([string]$section) {
    $t = @{}; $i = [array]::IndexOf($dl, "  ${section}:")
    while ($dl[$i] -ne '    Ids:') { $i++ }
    $ids = New-Object System.Collections.ArrayList
    for ($i++; $dl[$i] -match '^    - Value: (\d+)'; $i++) { [void]$ids.Add([int]$matches[1]) }
    while ($dl[$i] -ne '    IdValues:') { $i++ }
    $n = -1
    for ($i++; $i -lt $dl.Count -and $dl[$i] -match '^    [- ] '; $i++) {
        if ($dl[$i] -match '^    - English: ?(.*)$') { $n++; $t[$ids[$n]] = @{ en = (NotKo (Unyaml @($matches[1]))) } }
        elseif ($dl[$i] -match '^      (Japanese|Korean|TraditionalChinese|SimplifiedChinese): ?(.*)$') {
            $k = @{ Japanese = 'jp'; Korean = 'ko'; TraditionalChinese = 'tc'; SimplifiedChinese = 'sc' }[$matches[1]]
            $t[$ids[$n]][$k] = Unyaml @($matches[2])
        }
    }
    return $t
}
$songTitle = ReadIdTable 'songIdTitleTypeMapping'
$songArtist = ReadIdTable 'songIdArtistTypeMapping'
function JSong($h) { if (-not $h) { $h = @{} }; JNames $h.ko $h.jp $h.en $h.tc $h.sc }
$jdir = Join-Path $PSScriptRoot 'site\jackets'
New-Item -ItemType Directory -Force $jdir | Out-Null
Add-Type -AssemblyName System.Drawing
$jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 88L
$songJson = New-Object System.Collections.ArrayList
foreach ($base in ($stories | Where-Object Song | ForEach-Object Song | Sort-Object -Unique)) {
    $src = Src (Join-Path $assets "Texture2D\$base.png") 'Texture2D' "$base.png"; $dst = Join-Path $jdir "$base.jpg"
    $hasJacket = Test-Path $src
    if ($hasJacket -and -not (Test-Path $dst)) {
        $img = [System.Drawing.Image]::FromFile($src)
        $bmp = New-Object System.Drawing.Bitmap 512, 512
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, 0, 0, 512, 512)
        $bmp.Save($dst, $jpg, $ep)
        $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    }
    $num = $songNum[$base]
    [void]$songJson.Add("$(J $base):{`"title`":$(JSong $songTitle[$num]),`"artist`":$(JSong $songArtist[$num]),`"jacket`":$(if ($hasJacket) { J "jackets/$base.jpg" } else { 'null' })}")
}

# encounters used as unlock conditions: title + opponent (Korean from the fan translation's TSVs)
$encName = ReadIdTable 'encounterIdTypeMapping'
$encOpp = ReadIdTable 'encounterOpponentNameTypeMapping'
foreach ($pair in @(@('encounter_names.tsv', $encName), @('encounter_opponent_names.tsv', $encOpp))) {
    foreach ($ln in (RepoLines "translation\$($pair[0])")) {
        if ($ln -match '^(\d+)\t[^\t]*\t(.+)$' -and $pair[1].ContainsKey([int]$matches[1])) { $pair[1][[int]$matches[1]].ko = $matches[2] }
    }
}
$encJson = foreach ($id in ($stories | Where-Object Encounter | ForEach-Object { [int]$_.Encounter } | Sort-Object -Unique)) {
    "$(J ([string]$id)):{`"name`":$(JSong $encName[$id]),`"opponent`":$(JSong $encOpp[$id])}"
}

# ---- story pictures (optional viewer feature) -----------------------------------------
# Pictures with drawn text (sp-story/assets/text) and CGs (sp-story/assets/cg) are kept as they are:
# only stretched back to their original shape (the game stores them squeezed into a square texture,
# see textureOriginalResolutionLookup) and scaled down. Nothing is cropped, recoloured or merged;
# pictures with transparent parts stay PNG. The viewer puts a dark backdrop behind them and stacks
# same-sized layers on screen.
#   site\textimg\<lang|all>\<name>.png|jpg, site\cg\<name>.png|jpg
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.IO; using System.Drawing; using System.Drawing.Drawing2D; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class PicOut {
    // returns "path|origW|origH|hasAlpha(0/1)"
    public static string Save(string input, string outNoExt, int ow, int oh, int maxSide) {
        using (var img = Image.FromFile(input)) {
            int w0 = ow > 0 ? ow : img.Width, h0 = oh > 0 ? oh : img.Height;
            double k = Math.Min(1.0, (double)maxSide / Math.Max(w0, h0));
            int w = Math.Max(1, (int)Math.Round(w0 * k)), h = Math.Max(1, (int)Math.Round(h0 * k));
            using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                using (var g = Graphics.FromImage(bmp)) using (var ia = new ImageAttributes()) {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    ia.SetWrapMode(WrapMode.TileFlipXY);   // no see-through seams at the edges
                    g.DrawImage(img, new Rectangle(0, 0, w, h), 0, 0, img.Width, img.Height, GraphicsUnit.Pixel, ia);
                }
                var d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var px = new int[w * h]; Marshal.Copy(d.Scan0, px, 0, px.Length); bmp.UnlockBits(d);
                bool alpha = false; foreach (var v in px) if (((v >> 24) & 0xFF) < 250) { alpha = true; break; }
                string path = outNoExt + (alpha ? ".png" : ".jpg");
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                if (alpha) bmp.Save(path, ImageFormat.Png);
                else {
                    ImageCodecInfo jpg = null; foreach (var c in ImageCodecInfo.GetImageEncoders()) if (c.MimeType == "image/jpeg") jpg = c;
                    var ep = new EncoderParameters(1); ep.Param[0] = new EncoderParameter(Encoder.Quality, 88L);
                    bmp.Save(path, jpg, ep);
                }
                return path + "|" + w0 + "|" + h0 + "|" + (alpha ? 1 : 0);
            }
        }
    }
}
'@
$textDir = Join-Path $release 'sp-story\assets\text'
# original picture sizes (StoryDetails.textureOriginalResolutionLookup)
$origRes = @{}
for ($i = 0; $i -lt $sd.Count; $i++) {
    if ($sd[$i] -match '^\s*- AssetKey: (\S+)') {
        $key = $matches[1]; $blk = $sd[($i + 1)..([Math]::Min($i + 3, $sd.Count - 1))] -join ' '
        if ($blk -match 'x: (\d+)\D+y: (\d+)') { $origRes[$key] = @([int]$matches[1], [int]$matches[2]) }
    }
}
$koTexDir = if ($hasKo) { Join-Path $Repo 'translation\textures' } else { Join-Path $Out '_none' }   # Korean redraws ship under the *_en names
$imgLangs = [ordered]@{ ko = '_en'; jp = '_jp'; en = '_en'; tc = '_hant'; sc = '_hans' }
$chOfTitle = @{ '1' = 'Y1-1'; '2' = 'Y1-2'; '2_5' = 'Y1-2_5'; '3' = 'Y1-3'; '4' = 'Y1-4' }
function Rel([string]$path) { $path.Substring((Join-Path $PSScriptRoot 'site').Length + 1).Replace('\', '/') }
# one text layer -> @{ w; h; a; src = lang -> path } (language-neutral layers have one file for all languages)
$textLayers = @{}
function TextLayer([string]$n) {
    if ($textLayers.ContainsKey($n)) { return [bool]$textLayers[$n].src.Count }
    $L = @{ w = 0; h = 0; a = $false; src = [ordered]@{} }; $textLayers[$n] = $L
    $neutral = Src (Join-Path $textDir "$n.png") 'text' "$n.png"
    foreach ($lang in $imgLangs.Keys) {
        $suffix = $imgLangs[$lang]
        if (Test-Path $neutral) { $in = $neutral; $okey = "text/$n.png"; $sub = 'all' }
        else {
            $ko = Join-Path $koTexDir "$n$suffix.png"
            $in = if ($lang -eq 'ko' -and (Test-Path $ko)) { $ko } else { Src (Join-Path $textDir "$n$suffix.png") 'text' "$n$suffix.png" }
            $okey = "text/$n$suffix.png"; $sub = $lang
        }
        if (-not (Test-Path $in)) { continue }
        $prev = @($L.src.Values | Where-Object { $_ -like 'textimg/all/*' })
        if ($sub -eq 'all' -and $prev.Count) { $L.src[$lang] = $prev[0]; continue }
        $o = $origRes[$okey]; if (-not $o) { $o = @(0, 0) }
        $r = ([PicOut]::Save($in, (Join-Path $PSScriptRoot "site\textimg\$sub\$n"), $o[0], $o[1], 1600)) -split '\|'
        $L.src[$lang] = Rel $r[0]
        if (-not $L.w) { $L.w = [int]$r[1]; $L.h = [int]$r[2] }
        if ($r[3] -eq '1') { $L.a = $true }
    }
    return [bool]$L.src.Count
}
# where the script puts each picture: ,"place":{name:[x,y,anchorX,anchorY,scaleX,scaleY]}
function PlaceJ($pl) {
    if (-not $pl -or -not $pl.Count) { return '' }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    ',"place":{' + ((@($pl.Keys) | ForEach-Object { "$(J $_):[$((@($pl[$_]) | ForEach-Object { $_.ToString($inv) }) -join ',')]" }) -join ',') + '}'
}
foreach ($s in $stories) {
    $lineImgs = [ordered]@{}; $blocks = New-Object System.Collections.ArrayList
    foreach ($ts in $s.TextShows) {
        $n = $ts.name
        $bpos = if ($ts.revealPos -ge 0) { $ts.revealPos } else { $ts.pos }   # image-only scenes sit where they become visible
        if ($n -match '^(End|first_lie|memory|nightmare)[_-](\d+)$') {
            # pictures that repeat a dialogue line: the n-th picture belongs to the n-th line from here (End_* all split 001-001)
            $idx = if ($matches[1] -eq 'End') { $ts.pos } else { $ts.pos + [int]$matches[2] - 1 }
            if ($idx -lt $s.Lines.Count -and (TextLayer $n)) {
                $lid = $s.Lines[$idx].LineId
                if (-not $lineImgs.Contains($lid)) { $lineImgs[$lid] = New-Object System.Collections.ArrayList }
                [void]$lineImgs[$lid].Add($n)
            }
            continue
        }
        # picture-only scenes: pictures that come up together form one block, in the order the script shows them
        $kind = 'scene'; $cap = $null; $capJ = $null; $family = $null
        if ($n -match '^title_(\d(?:_5)?)$') { $ck = $chOfTitle[$matches[1]]; $kind = 'title'; $cap = $chapters[$ck]; $capJ = JNames $chapters[$ck] $chaptersJP[$ck] $chaptersEN[$ck] $chaptersTC[$ck] $chaptersSC[$ck] }
        elseif ($n -match '^arc_(\d(?:_5)?)$') {
            $ck = $chOfTitle[$matches[1]]; $kind = 'title'; $no = ($chapters[$ck] -split ' ')[0]; $cap = $no
            $capJ = JNames $no (($chaptersJP[$ck] -split '「')[0]) (($chaptersEN[$ck] -split '「')[0]) (($chaptersTC[$ck] -split '「')[0]) (($chaptersSC[$ck] -split '「')[0])
        }
        elseif ($n -match '^eoa_text_(\d(?:_5)?)$') {
            $ck = $chOfTitle[$matches[1]]; $kind = 'end'
            $eoa = "End of Arc $($matches[1] -replace '_', '.')"   # the card reads "End of Arc N" in every language
            $cap = $eoa; $capJ = JNames "$(($chapters[$ck] -split ' ')[0]) 끝" $eoa $eoa $eoa $eoa
        }
        elseif ($n -like 'RMI_*') { $family = 'RMI' }   # one block; no label (the pictures say it themselves)
        $blk = if ($family) { $blocks | Where-Object { $_.family -eq $family } | Select-Object -First 1 }
               else { $blocks | Where-Object { $_.pos -eq $bpos -and $_.kind -ne 'credits' -and -not $_.family } | Select-Object -First 1 }
        if (-not $blk) { $blk = @{ pos = $bpos; kind = $kind; layers = (New-Object System.Collections.ArrayList); caption = $cap; captionJson = $capJ; family = $family; place = @{} }; [void]$blocks.Add($blk) }
        elseif ($blk.kind -eq 'scene' -and $kind -ne 'scene') { $blk.kind = $kind; $blk.caption = $cap; $blk.captionJson = $capJ }
        elseif (-not $blk.caption -and $cap) { $blk.caption = $cap; $blk.captionJson = $capJ }
        if ((TextLayer $n) -and -not $blk.layers.Contains($n)) { [void]$blk.layers.Add($n); if ($ts.place -and $blk.place) { $blk.place[$n] = $ts.place } }
    }
    # a block with neither pictures nor a caption has nothing to show (e.g. no images were made)
    $blocks = @($blocks | Where-Object { $_.layers.Count -or $_.caption })
    if ($s.CreditsPos -ge 0) { $blocks += @{ pos = $s.CreditsPos; kind = 'credits'; layers = @(); caption = '엔딩 크레딧' } }
    $lj = @($lineImgs.Keys | ForEach-Object { "$(J $_):[$((@($lineImgs[$_]) | ForEach-Object { J $_ }) -join ',')]" }) -join ','
    $bj = @($blocks | ForEach-Object { "{`"pos`":$($_.pos),`"kind`":$(J $_.kind),`"layers`":[$((@($_.layers) | ForEach-Object { J $_ }) -join ',')],`"caption`":$(if ($_.captionJson) { $_.captionJson } else { J $_.caption })$(PlaceJ $_.place)}" }) -join ','
    $s | Add-Member ImgJson $(if ($lj -or $bj) { "{`"lines`":{$lj},`"blocks`":[$bj]}" } else { 'null' })
}
$textImgJson = @($textLayers.Keys | Where-Object { $textLayers[$_].src.Count } | Sort-Object | ForEach-Object {
    $L = $textLayers[$_]
    "$(J $_):{`"w`":$($L.w),`"h`":$($L.h),`"a`":$(J $L.a),`"src`":{$((@($L.src.Keys) | ForEach-Object { "$(J $_):$(J $L.src[$_])" }) -join ',')}}"
}) -join ','

# CGs: same treatment; pictures with transparent parts (pieces meant to sit on another picture) stay PNG
$cgSrc = Join-Path $release 'sp-story\assets\cg'
$cgDst = Join-Path $PSScriptRoot 'site\cg'
$cgInfo = @{}
foreach ($name in ($stories | ForEach-Object { $_.CgEvents } | ForEach-Object { $_.name } | Sort-Object -Unique)) {
    $src = Src (Join-Path $cgSrc "$name.png") 'cg' "$name.png"
    if (-not (Test-Path $src)) { continue }
    $o = $origRes["cg/$name.png"]; if (-not $o) { $o = @(0, 0) }   # back to the original shape
    $r = ([PicOut]::Save($src, (Join-Path $cgDst $name), $o[0], $o[1], 2048)) -split '\|'
    $cgInfo[$name] = @{ src = Rel $r[0]; w = [int]$r[1]; h = [int]$r[2]; a = ($r[3] -eq '1') }
}
foreach ($s in $stories) {
    # CGs appearing before the same line are one group, in the order the script shows them
    $groups = $s.CgEvents | Where-Object { $cgInfo.ContainsKey($_.name) } | Group-Object { $_.pos } | Sort-Object { [int]$_.Name }
    $cj = @($groups | ForEach-Object {
        $pl = @{}; foreach ($e in $_.Group) { if ($e.place) { $pl[$e.name] = $e.place } }
        "{`"pos`":$($_.Name),`"imgs`":[$((@($_.Group) | ForEach-Object { J $_.name }) -join ',')]$(PlaceJ $pl)}" }) -join ','
    $s | Add-Member CgJson $(if ($cj) { "[$cj]" } else { 'null' })
}
$cgsJson = @($cgInfo.Keys | Sort-Object | ForEach-Object { $c = $cgInfo[$_]; "$(J $_):{`"src`":$(J $c.src),`"w`":$($c.w),`"h`":$($c.h),`"a`":$(J $c.a)}" }) -join ','
# ---- end of story pictures --------------------------------------------------------------

$spkSeen = @{}
$sb = New-Object Text.StringBuilder
[void]$sb.Append('window.IF_DATA={"chapters":[')
$sb.Append((($chapters.Keys | ForEach-Object { "{`"key`":$(J $_),`"title`":$(JNames $chapters[$_] $chaptersJP[$_] $chaptersEN[$_] $chaptersTC[$_] $chaptersSC[$_])}" }) -join ',')) | Out-Null
[void]$sb.Append('],"slots":{' + (($slotKo.Keys | Sort-Object | ForEach-Object { "$(J $_):$(J $slotKo[$_])" }) -join ',') + '}')
# Story_RmiCoverage + Story_IntroVideo_{Stable,Thin,Dense,Islands,Shifting,LowVisibility,Splitting,Scattered,Needling}
[void]$sb.Append(",`"rmi`":{`"label`":$(& $rmiLang $uiKey.Story_RmiCoverage),`"states`":[$((@('Stable', 'Thin', 'Dense', 'Islands', 'Shifting', 'LowVisibility', 'Splitting', 'Scattered', 'Needling') | ForEach-Object { & $rmiLang $uiKey["Story_IntroVideo_$_"] }) -join ',')]}")
[void]$sb.Append(',"episodes":[')
$first = $true
foreach ($s in $stories) {
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    $povJp = if ($povSpecial.ContainsKey($s.PovKey)) { $povSpecial[$s.PovKey][3] } else { ZhName $s.PovKey 2 }
    [void]$sb.Append("{`"c`":$($s.Chrono),`"p`":$($s.Play),`"ch`":$(J $s.Chapter),`"y`":$($s.Year),`"m`":$($s.Month),`"d`":$($s.Day),`"slot`":$(J ([string]$s.Slot)),`"num`":$($s.Num)")
    [void]$sb.Append(",`"lane`":$(J $s.Pov),`"pov`":$(JNames $s.PovName $povJp $(if ($povSpecial.ContainsKey($s.PovKey)) { '' } else { $s.PovKey }) $s.PovTC $s.PovSC),`"story`":$(J $s.Story),`"file`":$(J $s.File.BaseName),`"o`":$(J ([bool]$s.Other)),`"song`":$(J $s.Song),`"enc`":$(J $s.Encounter)")
    $reqC = @($s.Requires | Where-Object { $byId.ContainsKey($_) } | ForEach-Object { $byId[$_].Chrono }) -join ','
    $bgsJ = @($s.Bgs | ForEach-Object { J $_ }) -join ','
    [void]$sb.Append(",`"id`":$($s.Id),`"video`":$($s.Video),`"clock`":$(J ([bool]$s.Clock)),`"req`":[$reqC],`"bgs`":[$bgsJ],`"img`":$($s.ImgJson),`"cg`":$($s.CgJson),`"lines`":[")
    $lf = $true
    foreach ($r in $s.Lines) {
        if (-not $lf) { [void]$sb.Append(',') }; $lf = $false
        $type = switch -Wildcard ($r.Kind) { 'phone message left' { 'ml' } 'phone message right' { 'mr' } 'log' { 'l' } default { if ($r.Narration) { 'n' } else { 's' } } }
        if ($r.SpeakerEn) { $spkSeen[$r.SpeakerEn] = $true }
        [void]$sb.Append("[$(J $r.LineId),$(J $r.SpeakerEn),$(J $type),$(J $r.EN),$(J $r.JP),$(J $r.KO),$(J $r.TC),$(J $r.SC),$(J $r.Alias),$(J $r.Choice)]")
    }
    [void]$sb.Append(']}')
}
[void]$sb.Append('],"speakers":{')
[void]$sb.Append((($spkSeen.Keys | Sort-Object | ForEach-Object { "$(J $_):$(JNames (KoName $_) (ZhName $_ 2) $_.TrimStart('*') (ZhName $_ 0) (ZhName $_ 1))" }) -join ','))
[void]$sb.Append('},"songs":{' + ($songJson -join ',') + '},"encounters":{' + (@($encJson) -join ',') + '},"textimg":{' + $textImgJson + '},"cgs":{' + $cgsJson + '}};')
$siteDir = Join-Path $PSScriptRoot 'site'
New-Item -ItemType Directory -Force $siteDir | Out-Null
[IO.File]::WriteAllText((Join-Path $siteDir 'data.js'), $sb.ToString(), $utf8)
# the full-size decoded pictures are only an intermediate step (the viewer uses site\jackets, textimg, cg)
if (Test-Path $imgDir) { Remove-Item -Recurse -Force $imgDir }

$missKo =@($rows | Where-Object { -not $_.KO }).Count
Write-Host "stories: $($stories.Count)  lines: $($rows.Count)  KO missing: $missKo  JP missing: $(@($rows | Where-Object { -not $_.JP }).Count)  TC missing: $(@($rows | Where-Object { -not $_.TC }).Count)  SC missing: $(@($rows | Where-Object { -not $_.SC }).Count)"
# a later fan translation may lay its files out differently: say so instead of quietly leaving the Korean out
if ($hasKo -and $rows.Count -and $missKo -gt $rows.Count / 10) { Write-Host "주의: 한국어 대사 $missKo 줄이 비어 있습니다. 한국어 패치의 파일 형식이 바뀌었을 수 있습니다 ($Repo)" }
if ($hasKo -and -not $ko.Count) { Write-Host "주의: 한국어 이름표(names.tsv)를 읽지 못했습니다. 한국어 패치의 파일 형식이 바뀌었을 수 있습니다" }
Write-Host "speakers without Chinese name: $((@($rows | Where-Object { $_.Alias -and $_.SpeakerTC -eq $_.SpeakerEn.TrimStart('*') }) | Select-Object -ExpandProperty SpeakerEn -Unique) -join ', ')"
Write-Host "chrono != play order: $(@($stories | Where-Object { $_.Chrono -ne $_.Play }).Count) stories"
