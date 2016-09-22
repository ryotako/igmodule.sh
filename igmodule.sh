#!/bin/bash

# ヘルプを示して終了
usage_exit(){
  echo "Usage: $(basename $0) " 1>&2
  exit 1
}

# User Proceduresフォルダを探す
# ユーザーがUser Proceduresフォルダの位置を変更している場合は，環境変数
# IGORPATHで指定する．
user_proc_dir(){
  if [ -n $"IGORPATH" ];then
    echo $IGORPATH
  else
    find "$HOME/Documents/WaveMetrics" -type d -name 'Igor Pro *User Files' \
      | tail -n 1
  fi
}

# Igorの:区切りのパスを/区切りのパスに変換する
convert_igor_path(){
  echo "$1.ipf" | sed -e 's/^Macintosh HD://' -e 's/^[^\/]/\//' | tr ':' '/' 
}

# プロシージャ名を受け取ってそのパスを返す．
# 第一引数にプロシージャ名，第二引数に呼び出し元のファイルパスを渡す．
find_procedure(){
  proc_name="$1"
  file_path="$2"
  if [[ "$proc_name" =~ ^: ]]; then # 絶対パス
    echo $(dirname "$file_path")$(convert_igor_path "$proc_name")
  elif [[ "$proc_name" =~ : ]]; then # 相対パス
    convert_igor_path "$proc_name"
  else # ファイル名のみ
    find "$(user_proc_dir)/User Procedures" -type f -name "$proc_name.ipf"
  fi
}


# プラグマ文をファイルパスに変換する
# 第一引数にプラグマ文，第二引数に相対パス読み込みのためのファイルパスを指定
pragma_to_procname(){
  echo "$1" |egrep '^#include +"[^"]+"' |sed -E 's/^#include +"([^"]+)".*$/\1/'
}

# 第一引数にファイルパス，第二引数に読み込み済みのプロシージャ名を受け取り，
# 加工済みのテキストを返す
make_packed_module(){
  local proc_path="$1"
  local proc_name=$(basename "$1" .ipf)
  shift
  local proc_names=($@)

  if [ -f "$proc_path" ];then
    if contain "$proc_name" "${proc_names[@]}" ;then      
      :
      # echo "ALREADY INCLUDED: $proc_name" 1>&2
    else
      proc_names+=("$proc_name")
      echo ">$proc_path" 1>&2
      cat "$proc_path"
      while read pragma; do
        local included_proc=$(pragma_to_procname "$pragma")
        local included_path=$(find_procedure "$included_proc" "$proc_path")
        make_packed_module "$included_path" "${proc_names[@]}"
      done < <(egrep '^#include +"[^"]+"' "$proc_path")
    fi
  fi
}

contain(){
  elm="$1" 
  shift
  array=($@)
  i=0
  for elm_i in ${array[@]}; do
    if [ "$elm_i" = "$elm" ];then
      return 0
    fi
    let i++
  done
  return 1
}

make_packed_module "$(find_procedure $1)" 

# Execution

# while getopts m:h OPT
# do
#   case $OPT in
#     m) echo "Module Name: $OPTARG"
#       ;;
#     h) usage_exit
  #       ;;
  #   esac
  # done
  # shift $((OPTIND - 1))

  # if [ $# -ne 1 ]; then
  #   usage_exit
  # fi

