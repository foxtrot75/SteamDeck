#!/bin/bash

set -e

SCRIPT_FULL="$(readlink -f ${BASH_SOURCE[0]})"
SCRIPT_PATH="$(dirname $SCRIPT_FULL)"
SCRIPT_NAME="$(basename $SCRIPT_FULL)"

NAME="SteamDeck Cache Cleaner"
VERSION="1.0.2"

IDDB="$SCRIPT_PATH/iddb"
STEAM="$HOME/.steam/steam"
SHORTCUTS="$STEAM/userdata/??*/config/shortcuts.vdf"
CLEAN=("compatdata shadercache")
MEDIA=("/run/media")

function find_paths()
{
    PATHS+=($(readlink -f "$STEAM/steamapps"))

    for media in $MEDIA; do
        for dir in $media/*; do
            local steamapps="$dir/steamapps"
            if [[ -d $steamapps ]]; then
                PATHS+=($(readlink -f $steamapps))
            fi
        done
    done

    echo "PATHS=("${PATHS[@]}")"
}

# https://developer.valvesoftware.com/wiki/Add_Non-Steam_Game
function map_shortcuts()
{
    echo "Map shortcuts:"
    local id_offset=6
    local name_offset=19

    local positions=$(strings -t d $SHORTCUTS \
        | grep appid \
        | grep -oE '[0-9]+')

    for p in $positions; do
        local id=$(od -A n -l -j $(($p+$id_offset)) -N 4 $SHORTCUTS \
            | sed -e 's/^ *//g')
        local name=$(strings -t d $SHORTCUTS \
            | grep -w $(($p+$name_offset)) \
            | sed -e 's/^[ 0-9]* //g')
        sed -i "/$id/d" $IDDB
        echo -e "$name\t$id" | tee -a $IDDB
    done
}

function map_manifests()
{
    echo "Map manifests:"
    for path in $PATHS; do
        for file in $path/appmanifest_*.acf; do
            awk \
            '{
                if($1 == "\"appid\"") {
                    $1="";
                    id=gensub(/ *" */, "", "g", $0);
                }

                if($1 == "\"name\"") {
                    $1="";
                    name=gensub(/ *" */, "", "g", $0);
                }
            }

            END {
                print name"\t"id;
            }' $file | tee -a $IDDB
        done
    done
}

function map_ids()
{
    map_shortcuts
    map_manifests
    sort -u $IDDB -o $IDDB
}

function prepare_info()
{
    reg_exp="^[0-9]+$"

    for path in $PATHS; do
        for clean in $CLEAN; do
            for file in $path/$clean/*; do
                id=$(basename $file)
                if [[ $id =~ $reg_exp ]]; then
                    name=$(grep $'\t'$id$ $IDDB | cut -f 1)
                    size=$(du -h -d 0 $file | cut -f 1)
                    type=${clean::6}

                    if [[ -z $name ]]; then
                        name="Unknown"
                    fi

                    INFO+=("1\t$name\t$id\t$size\t$type\t$file\n")
                fi
            done
        done
    done

    IFS=$'\n'
    INFO=($(sort <<< "${INFO[*]}"))
    INFO=($(echo -e ${INFO[@]}))
    unset IFS

    echo "INFO=(${INFO[@]})"
}

function show_info()
{
    IFS=$'[\t]'
    REMOVE=($(zenity \
        --title "$NAME $VERSION" \
        --width=1000     \
        --height=720     \
        --list           \
        --checklist      \
        --column="*"     \
        --column="Name"  \
        --column="Id"    \
        --column="Size"  \
        --column="Type"  \
        --column="Path"  \
        --separator=" "  \
        --print-column=6 \
        ${INFO[@]}))

    res=$?

    unset IFS

    return $res
}

function show_confirm()
{
    list=${REMOVE[@]//" "/"\n"}

    zenity \
        --title "$NAME $VERSION" \
        --width=550  \
        --height=400 \
        --question   \
        --text="Remove this folders?\n\n$list"

    res=$?

    return $res
}

declare -a PATHS=()
find_paths
map_ids

INFO=()
prepare_info

REMOVE=()
show_info
if [[ $? == 0 && ${#REMOVE[@]} != 0 ]]; then
    show_confirm
    if [[ $? == 0 ]]; then
        for path in $REMOVE; do
            rm -r $path
        done
    fi
fi
