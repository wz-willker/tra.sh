#!/bin/sh
# Copyright © 2025 hiruocha

# This program is free software: you can redistribute it and/or modify it under the 
# terms of the GNU General Public License as published by the Free Software 
# Foundation, either version 3 of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT ANY 
# WARRANTY; without even the implied warranty of MERCHANTABILITY or 
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for 
# more details.

# You should have received a copy of the GNU General Public License along with this 
# program. If not, see <https://www.gnu.org/licenses/>. 

set -e

uid=$(id -ru)
home_trash=${XDG_DATA_HOME:-$HOME/.local/share}/Trash
home_topdir=$(df -P "$home_trash" | awk 'NR==2 {print $NF}')

cmd="${1:-help}"
[ -n "$1" ] && shift 1

# https://github.com/ko1nksm/url
urlencode() {
  LC_ALL=C awk -v space="$SHURL_SPACE" -v eol="$SHURL_EOL" \
    -v multiline="$SHURL_MULTILINE" '
    function encode(map, str,   i, len, ret) {
      len = length(str); ret = ""
      for (i = 1; i <= len; i++) ret = ret map[substr(str, i, 1)]
      return ret
    }

    function fix_eol(eol,   i) {
      for (i = 1; i < ARGC; i++) gsub(/\r\n/, "\n", ARGV[i])
      for (i = 1; i < ARGC; i++) gsub(/\n/, eol, ARGV[i])
    }

    BEGIN {
      for(i = 0; i < 256; i++) {
        k = sprintf("%c", i); v = sprintf("%%%02X", i)
        url[k] = (k ~ /[A-Za-z0-9_.~\/-]/) ? k : v
      }
      if (length(space) > 0) uri[" "] = url[" "] = space
      if (length(eol) > 0) fix_eol(eol)
    }

    BEGIN {
      for (i = 1; i < ARGC; i++) print encode(url, ARGV[i])
      if (ARGC > 1) exit
      if (multiline) {
        while (getline) printf "%s", encode(url, $0 "\n")
        print ""
      }
    }

    {
      print encode(url, $0)
    }
  ' "$@"
}

# https://github.com/ko1nksm/url
urldecode() {
  LC_ALL=C awk -v space="$SHURL_SPACE" -v eol="$SHURL_EOL" '
    function decode(map, str,   ret) {
      while (match(str, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
        ret = ret substr(str, 1, RSTART - 1) url[substr(str, RSTART + 1, 2)]
        str = substr(str, RSTART + RLENGTH)
      }
      return ret str
    }

    BEGIN {
      for (i = 0; i < 256; i++) url[sprintf("%02x", i)] = sprintf("%c", i)

      # Increase to 4 patterns to improve performance
      for (k in url) {
        m = substr(k, 1, 1); M = toupper(m)
        l = substr(k, 2, 1); L = toupper(l)
        url[m L] = url[M l] = url[M L] = url[k]
      }
    }

    BEGIN {
      for (i = 1; i < ARGC; i++) {
        if (length(space) > 0) gsub(space, " ", ARGV[i])
        print decode(url, ARGV[i])
      }
      if (ARGC > 1) exit
    }

    {
      if (length(space) > 0) gsub(/\+/, " ", $0)
      print decode(url, $0)
    }
  ' "$@"
}

get_trash() {
  if [ "$1" = "$home_topdir" ]; then
    trash="$home_trash"
  elif
    [ -d "$1/.Trash" ] &&
    [ ! -L "$1/.Trash" ] &&
    [ -n "$(find "$1/.Trash" -prune -type d -perm -1000)" ]
  then
    trash="$1"/.Trash/"$uid"
  else
    trash="$1"/.Trash-"$uid"
  fi
}

get_realpath() {
  basename=$(basename "$1")
  path=$(
    cd "$(dirname "$1")" &&
    if [ "$(pwd -P)" = "/" ]; then
      printf '/%s' "$basename"
    else
      printf '%s/%s' "$(pwd -P)" "$basename"
    fi
  )
}

cmd_put() {
  [ -n "$1" ] || usage_put
  [ -e "$1" ] || {
    printf 'error: %s: No such file or directory\n' "$1" >&2
    exit 1
  }
  get_realpath "$1"
  topdir=$(df -P "$path" | awk 'NR==2 {print $NF}')
  get_trash "$topdir"
  mkdir -p "$trash"/info
  mkdir -p "$trash"/files
  filename=$(basename "$path")
  set -C
  if [ ! -e "$trash"/info/"$filename".trashinfo ]; then
    : > "$trash"/info/"$filename".trashinfo
  else
    count=1
    while [ -e "$trash/info/${filename}_$count.trashinfo" ]; do
      count=$((count + 1))
    done
    filename="$filename"_"$count"
    : > "$trash"/info/"$filename".trashinfo
  fi
  set +C
  printf '[Trash Info]\n' >> "$trash"/info/"$filename".trashinfo
  if [ "$trash" = "$home_trash" ]; then
    encoded_path=$(urlencode "$path")
  else
    encoded_path=$(urlencode "${path##"$topdir"/}")
  fi
  printf 'Path=%s\n' "$encoded_path" >> "$trash"/info/"$filename".trashinfo
  printf 'DeletionDate=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" >> "$trash"/info/"$filename".trashinfo
  mv "$path" "$trash"/files/"$filename" 2>/dev/null || {
    rm "$trash"/info/"$filename".trashinfo
    printf 'error: Failed to move %s to trash\n' "$path" >&2
    exit 1
  }
}

cmd_ls() {
  df -P | tail -n +2 | while read -r fs; do
    case "$fs" in
      /dev/*)
        ;;
      *)
        continue
        ;;
    esac
    topdir=$(printf '%s' "$fs" | awk '{print $NF}')
    get_trash "$topdir"
    [ -d "$trash" ] || continue
    for trashinfo in "$trash"/info/*.trashinfo
    do
      [ -e "$trashinfo" ] || continue
      raw_path=$(urldecode "$(awk -F '=' '/^Path=/ {print $2; exit}' "$trashinfo")")
      case $raw_path in
        /*)
          path=$raw_path
          ;;
        *)
          path="$topdir"/"$raw_path"
          ;;
      esac
      printf '%s' "$path"
      filename=${trashinfo##*/}
      filename=${filename%.trashinfo}
      if [ ! -e "$trash"/files/"$filename" ]; then
        printf ' [MISSING]\n'
      elif [ -d "$trash"/files/"$filename" ]; then
        printf ' (dir)\n'
      else
        printf '\n'
      fi
    done
  done
}

case "$cmd" in
  help)
    usage
    ;;
  ls)
    cmd_ls | sort
    ;;
  put)
    cmd_put "$@"
    ;;
esac
