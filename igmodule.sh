#!/bin/bash

atexit() {
      [[ -n $tmpfile ]] && rm -f "$tmpfile"
}
tmpfile=`mktemp`
trap atexit EXIT
trap 'trap - EXIT; atexit; exit -1' SIGHUP SIGINT SIGTERM

# variables
igmodule_progname="$(basename $0)"
igmodule_proclist=()
igmodule_modulelist=()
igmodule_module=""
igmodule_args=()

igmodule_sed(){
  if which -s gsed; then
    gsed -E "$1i"
  else
    sed -E "$1"
  fi
}

contain(){ # 第一引数が，第二引数で与えられるリストに存在するかどうかを判定
  local elm="$1" 
  shift
  local array=($@)
  local i=0
  for elm_i in ${array[@]}; do
    if [ "$elm_i" = "$elm" ];then
      return 0
    fi
    let i++
  done
  return 1
}

# User Proceduresフォルダを探す
# ユーザーがUser Proceduresフォルダの位置を変更している場合は，
# 環境変数IGORPATHで指定する．
user_proc_dir(){
  if [ -n $"IGORPATH" ];then
    echo $IGORPATH
  else
    find "$HOME/Documents/WaveMetrics" -type d -name 'Igor Pro *User Files' \
      | tail -n 1
  fi
}

# プロシージャ名を受け取ってそのパスを返す．
# 第一引数にプロシージャ名，第二引数に呼び出し元のファイルパスを渡す．
find_procedure(){
  proc_name="$1"
  file_path="$2"

  # Igorの:区切りのパスを/区切りのパスに変換する関数をローカルに定義
  convert_igorpath(){
    echo "$1.ipf" | sed -e 's/^Macintosh HD://' -e 's/^[^\/]/\//' | tr ':' '/' 
  }

  if [[ "$proc_name" =~ ^: ]]; then # 絶対パス
    echo $(dirname "$file_path")$(convert_igorpath "$proc_name")
  elif [[ "$proc_name" =~ : ]]; then # 相対パス
    convert_igorpath "$proc_name"
  else # ファイル名のみ
    find "$(user_proc_dir)/User Procedures" -type f -name "$proc_name.ipf" \
      | head -n 1 
  fi
}

# 第一引数にファイルパス，第二引数に読み込み済みのプロシージャ名を受け取り，
# 加工済みのテキストを返す
pack_procedures(){
  local proc_path="$1"
  local proc_name=$(basename "$1" .ipf)
  igmodule_module="${igmodule_module:-$proc_name}"
  cat << EOS
//------------------------------------------------------------------------------
// This procedure file is packaged by $igmodule_progname
// $(LANG=en_US.UTF-8 date '+%a,%d %b %Y')
//------------------------------------------------------------------------------
#pragma ModuleName=$igmodule_module

EOS

  pack_procedures_recursive "$proc_path" > "$tmpfile"

  rewrite_modulecall < "$tmpfile" 
  
  
}

rewrite_modulecall(){
  local module="${igmodule_modulelist[1]}"
  igmodule_modulelist=("${igmodule_modulelist[@]:1}")
  if [ "${#igmodule_modulelist[@]}" -eq 0 ]; then
    cat -
  else
    cat - | igmodule_sed "s/$module/$igmodule_module/g" | rewrite_modulecall
  fi
}


# 再帰的に#includeをたどる機構．
# 各ファイルの読み出しそのものはpack_procedureで行う．
# 同名のファイルを二度呼び出さないために，グローバルな配列を使用．
pack_procedures_recursive(){
  local proc_path="$1"
  local proc_name=$(basename "$1" .ipf)
  if contain "$proc_name" "${igmodule_proclist[@]}";then
    return 1
  fi

  pack_procedure "$proc_path"
  igmodule_proclist+=("$proc_name")
  igmodule_modulelist+=( $(egrep '^#pragma +ModuleName' "$proc_path" \
    | igmodule_sed 's/^[^=]*= *([^ ]+).*$/\1/' | head -n 1) )
  while read pragma; do
    local included_proc="$(echo $pragma \
      | sed -E 's/^#include +\"([^\"]+)\".*$/\1/')"
    local included_path=$(find_procedure "$included_proc" "$proc_path")
    if [ -n "$included_path" ]; then
        pack_procedures_recursive "$included_path"
    else
      echo "Not Found: $included_proc" 1>&2
    fi
  done < <(egrep '^#include +"[^"]+"' "$proc_path")
}

# プロシージャをまとめられる形式に変更
# - #includeプラグマをコメントアウト
# - モジュール・独立モジュール宣言のコメントアウト
# TODO menus=1
pack_procedure(){
  local proc_path="$1"
  local proc_name=$(basename "$1" .ipf)
  cat <<EOS
//------------------------------------------------------------------------------
// original file: $proc_name.ipf 
//------------------------------------------------------------------------------
#if !ItemsInList(WinList("$2.ipf",";",""))

EOS

  cat "$proc_path" \
    | igmodule_sed '/^#include +"/ s/^/\/\//' \
    | igmodule_sed '/^#pragma ModuleName/ s/^/\/\//' \
    | igmodule_sed 's/^constant /override constant /' \
    | igmodule_sed 's/^strconstant /override strconstant /' \
    | igmodule_sed 's/^Function /override Function /' \

cat <<EOS

#endif

EOS
}


# ヘルプを示して終了
usage_exit(){
  echo "Usage: $(basename $0) [--as module] [-h]" 1>&2
  exit 1
}

# オプション解析
while (( $# > 0 )); do
  case $1 in
    --help)
      usage_exit
      ;;
    --as)
      echo "DONE" 1>&2
      igmodule_module="$2"
      shift 2
      ;;
    --include)
      echo "DONE" 1>&2
      igmodule_args=("$(find_procedure $2 '')")
      shift 2
      ;;
    *)
      igmodule_args+=("$@")
      break
      ;;
  esac
done

echo "ARGS:${igmodule_args[@]}" 1>&2
argc="${#igmodule_args[@]}"
if [ "$argc" -lt 1 ]; then
  echo "$igmodule_progname: too few arguments" 1>&2
elif [ "$argc" -gt 1 ]; then
  echo "$igmodule_progname: too many arguments" 1>&2
else
  pack_procedures "${igmodule_args[0]}"
fi


