#!/bin/zsh
# find-game.sh <bottle folder>: where Age of Empires II: DE (Steam app 813780) is installed in a CrossOver bottle.
# Prints three lines and exits 0, or prints nothing and exits 1:
#   unix=<macOS path of AoE2DE_s.exe>
#   win=<the same file as a Windows path, forward slashes, e.g. C:/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe>
#   from=override|library|default
# Order:
#   1. AOE2_GAME_DIR (a macOS folder that holds AoE2DE_s.exe; Settings > Game > Game folder);
#   2. every Steam library in the bottle's libraryfolders.vdf that lists app 813780 (the folder name comes from its
#      appmanifest_813780.acf "installdir", default AoE2DE), in the file's order, mapped through the bottle's drive letters
#      (dosdevices/<x>: links, e.g. z: -> / or e: -> /Volumes/External);
#   3. the default C:\Program Files (x86)\Steam\steamapps\common\AoE2DE (also when that is a link to elsewhere).
# Read-only: nothing in the bottle is changed.
emulate -L zsh
setopt extendedglob
B=${1:?bottle folder}; B=${B:a}
D=$B/dosdevices
steam="$B/drive_c/Program Files (x86)/Steam"

# Windows path ("X:\a\b" or "X:/a/b") -> macOS path, through dosdevices/x:
unix_of() {
  local w=${1//\\//} l t
  [[ $w == [A-Za-z]:(/*|) ]] || return 1
  l=${(L)w[1]}; [[ -L $D/$l: || -d $D/$l: ]] || return 1
  t=$(readlink "$D/$l:") || t=$D/$l:
  [[ $t == /* ]] || t=$D/$t
  t=${t:a}; t=${t%/}
  print -r -- "$t${w[3,-1]}"
}
# macOS path -> Windows path: the drive letter whose target is the longest prefix of the path (the path itself is not
# resolved, so a link under drive_c keeps its C: path)
win_of() {
  local p=${1:a} d t best= bt= bl=-1 rest
  for d in $D/[a-z]:(N); do
    t=$(readlink "$d") || t=$d
    [[ $t == /* ]] || t=$D/$t
    t=${t:a}; t=${t%/}
    if [[ $p == $t/* || $p == $t ]] && (( ${#t} > bl )); then best=${d:t}; bt=$t; bl=${#t}; fi
  done
  [[ -n $best ]] || return 1
  rest=${p#$bt}; [[ $rest == /* || -z $rest ]] || rest=/$rest
  print -r -- "${(U)best[1]}:${rest:-/}"
}
emit() {   # emit <unix exe> <win exe> <from>
  print -r -- "unix=$1"; print -r -- "win=$2"; print -r -- "from=$3"; exit 0
}

# 1. Override
if [[ -n ${AOE2_GAME_DIR:-} ]]; then
  g=${AOE2_GAME_DIR%/}
  if [[ -f $g/AoE2DE_s.exe ]] && w=$(win_of "$g/AoE2DE_s.exe"); then emit "$g/AoE2DE_s.exe" "$w" override; fi
fi

# 2. Steam libraries that list the game
for vdf in "$steam/steamapps/libraryfolders.vdf" "$steam/config/libraryfolders.vdf"; do
  [[ -f $vdf ]] || continue
  libs=("${(@f)$(awk -F'"' '
    $2 == "path"   { path = $4; gsub(/\\\\/, "\\", path) }
    $2 == "apps"   { inapps = 1; next }
    inapps && $2 == "813780" { print path }
    inapps && /^[ \t]*}/ { inapps = 0 }' "$vdf")}")
  for lib in $libs; do
    [[ -n $lib ]] || continue
    lu=$(unix_of "$lib") || continue
    dir=AoE2DE
    acf="$lu/steamapps/appmanifest_813780.acf"
    if [[ -f $acf ]]; then d=$(awk -F'"' '$2 == "installdir" { print $4; exit }' "$acf"); [[ -n $d && $d != */* ]] && dir=$d; fi
    exe="$lu/steamapps/common/$dir/AoE2DE_s.exe"
    if [[ -f $exe ]]; then emit "$exe" "${${lib//\\//}%/}/steamapps/common/$dir/AoE2DE_s.exe" library; fi
  done
  break
done

# 3. Default
exe="$steam/steamapps/common/AoE2DE/AoE2DE_s.exe"
[[ -f $exe ]] && emit "$exe" "C:/Program Files (x86)/Steam/steamapps/common/AoE2DE/AoE2DE_s.exe" default
exit 1
