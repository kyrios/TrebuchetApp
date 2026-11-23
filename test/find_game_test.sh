#!/bin/zsh
# Unit test for scripts/find-game.sh: fake CrossOver bottles in a temporary folder, no CrossOver or game needed.
#   zsh test/find_game_test.sh   -> "find_game_test: N passed" and exit 0, or the failing cases and exit 1
emulate -L zsh
here=${0:A:h}; F=$here/../scripts/find-game.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/find-game-test.XXXXXX"); T=${T:A}
pass=0; fail=0
check() {   # check <name> <bottle> <expected from> <expected unix> <expected win> [env...]
  local name=$1 b=$2 ef=$3 eu=$4 ew=$5; shift 5
  local out; out=$(env "$@" zsh "$F" "$b"); local rc=$?
  local got_u=${${(M)${(f)out}:#unix=*}#unix=} got_w=${${(M)${(f)out}:#win=*}#win=} got_f=${${(M)${(f)out}:#from=*}#from=}
  if [[ $ef == none ]]; then
    (( rc == 1 )) && [[ -z $out ]] && { pass=$((pass+1)); return; }
  elif (( rc == 0 )) && [[ $got_f == $ef && $got_u == $eu && $got_w == $ew ]]; then pass=$((pass+1)); return; fi
  fail=$((fail+1)); print "FAIL $name (rc $rc)\n  want from=$ef unix=$eu win=$ew\n  got  $out"
}
mkbottle() {   # mkbottle <dir>: drive_c + c: and z: links, Steam folder with an empty steamapps
  mkdir -p "$1/dosdevices" "$1/drive_c/Program Files (x86)/Steam/steamapps"
  ln -s ../drive_c "$1/dosdevices/c:"; ln -s / "$1/dosdevices/z:"
}
game() { mkdir -p "$1"; print MZ > "$1/AoE2DE_s.exe"; }
vdf() {   # vdf <bottle> <lib0 path> <lib0 apps> <lib1 path> <lib1 apps>   (Windows paths as Steam writes them: \\ escaped)
  cat > "$1/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf" <<EOF
"libraryfolders"
{
	"0"
	{
		"path"		"$2"
		"label"		""
		"apps"
		{
$3
		}
	}
	"1"
	{
		"path"		"$4"
		"label"		""
		"apps"
		{
$5
		}
	}
}
EOF
}
S='Program Files (x86)/Steam/steamapps/common'

# 1. Two libraries, the game in the second one on an external disk reached through Z: (z: -> /)
B=$T/b1; mkbottle $B; X="$T/Volumes/Macbook Ext/Steam (Crossover)"; game "$X/steamapps/common/AoE2DE"
xw=${X//\//\\\\}   # Z:\\private\\var\\...\\Steam (Crossover) as written in the file
vdf $B 'C:\\Program Files (x86)\\Steam' '			"228980"		"1"' "Z:$xw" '			"813780"		"2"'
check "second library via Z:" $B library "$X/steamapps/common/AoE2DE/AoE2DE_s.exe" "Z:$X/steamapps/common/AoE2DE/AoE2DE_s.exe"

# 2. Same, through its own drive letter (e: -> the disk) and a custom installdir from the app manifest
B=$T/b2; mkbottle $B; E="$T/Volumes/Games"; ln -s $E $B/dosdevices/e:
game "$E/SteamLibrary/steamapps/common/AoE2 DE"; print '"AppState"\n{\n\t"appid"\t\t"813780"\n\t"installdir"\t\t"AoE2 DE"\n}' > "$E/SteamLibrary/steamapps/appmanifest_813780.acf"
vdf $B 'C:\\Program Files (x86)\\Steam' '' 'E:\\SteamLibrary' '			"813780"		"2"'
check "E: drive + installdir" $B library "$E/SteamLibrary/steamapps/common/AoE2 DE/AoE2DE_s.exe" "E:/SteamLibrary/steamapps/common/AoE2 DE/AoE2DE_s.exe"

# 3. The default install still wins when the file lists it there (no regression for most players)
B=$T/b3; mkbottle $B; game "$B/drive_c/$S/AoE2DE"
vdf $B 'C:\\Program Files (x86)\\Steam' '			"813780"		"2"' 'Z:\\nowhere' ''
check "default library listed" $B library "$B/drive_c/$S/AoE2DE/AoE2DE_s.exe" "C:/$S/AoE2DE/AoE2DE_s.exe"

# 4. Listed in a library whose disk is not connected -> falls back to the default folder
B=$T/b4; mkbottle $B; game "$B/drive_c/$S/AoE2DE"
vdf $B 'C:\\Program Files (x86)\\Steam' '' 'Z:\\Volumes\\Unplugged' '			"813780"		"2"'
check "library missing -> default" $B default "$B/drive_c/$S/AoE2DE/AoE2DE_s.exe" "C:/$S/AoE2DE/AoE2DE_s.exe"

# 5. No libraryfolders.vdf, the reporter's workaround: default folder is a link to the external disk -> keeps its C: path
B=$T/b5; mkbottle $B; L="$T/Volumes/Ext2/AoE2DE"; game $L; mkdir -p "$B/drive_c/$S"; ln -s $L "$B/drive_c/$S/AoE2DE"
check "symlinked default" $B default "$B/drive_c/$S/AoE2DE/AoE2DE_s.exe" "C:/$S/AoE2DE/AoE2DE_s.exe"

# 6. Override (Settings: game folder) wins over everything, mapped back to a Windows path
B=$T/b6; mkbottle $B; game "$B/drive_c/$S/AoE2DE"; O="$T/Volumes/Mine/AoE2DE"; game $O
check "override" $B override "$O/AoE2DE_s.exe" "Z:$O/AoE2DE_s.exe" AOE2_GAME_DIR=$O/
check "override without the game -> default" $B default "$B/drive_c/$S/AoE2DE/AoE2DE_s.exe" "C:/$S/AoE2DE/AoE2DE_s.exe" AOE2_GAME_DIR=$T/empty

# 7. No game anywhere -> exit 1, no output
B=$T/b7; mkbottle $B; vdf $B 'C:\\Program Files (x86)\\Steam' '' 'Z:\\x' ''
check "no game" $B none "" ""

(( fail )) && { print "find_game_test: $fail failed, $pass passed"; exit 1; }
print "find_game_test: $pass passed"
