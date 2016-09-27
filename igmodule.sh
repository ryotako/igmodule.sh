#!/bin/bash
PROGNAME=$(basename "$0")

# Create and kill a temporary file
function atexit() {
  if [ -f "$TMPFILE" ]; then
    rm -f "$TMPFILE"
  fi
}
trap atexit EXIT
trap 'trap - EXIT; atexit; EXIT 1' HUP INT TERM
TMPFILE="$(mktemp)"

# Print an error message
function error(){
  echo "$@" 1>&2
}

# Show usage and exit
function usage_exit(){
  cat << EOS 
Usage: $PROGNAME [options] [file path]

Options:
  -h, --help     show this help message and exit
  --path         show the path of your 'User Procedures' directory

  -a, --as       module name of packaged file
  -i, --include  a target file as #include style

Environment variables:
  IGORPATH       'Igor Pro User Files' directory
EOS
  exit 0
}

# Find ''User Procedures' directory
# If it is not found, print error message and exit
function user_procedures(){
  local wm_dir="$HOME/Documents/WaveMetrics"
  local usrdir_igor7="$wm_dir/Igor Pro 7 User Files/User Procedures"
  local usrdir_igor6="$wm_dir/Igor Pro 6 User Files/User Procedures"
  local usrdir_igor="$wm_dir/Igor Pro User Files/User Procedures"
  if [ -n $"IGORPATH" ];then
    if [ -d "$IGORPATH/User Procedures" ];then
      local usrdir="$IGORPATH/User Procedures"
    else
      error "$PROGNAME: illegal environment variable IGORPATH"
      error "IGORPATH=$IGORPATH"
      exit 1
    fi
  elif [ -d "$usrdir_igor7" ]; then
    local usrdir="$usrdir_igor7"
  elif [ -d "$usrdir_igor6" ]; then
    local usrdir="$usrdir_igor6"
  elif [ -d "$usrdir_igor" ]; then
    local usrdir="$usrdir_igor"
  else
    error "$PROGNAME: your 'User Procedures' directory is not found"
    error "Set environment variable IGORPATH"
    exit 1
  fi
  echo "$usrdir"
}

# Find .ipf file from procedure name and return its file path
# #include "procname" <- procedure name is this
function find_procedure(){
  local proc_name="$1"
  local root_file="$2"

  function convert_igorpath(){
    sed <<< "$1.ipf" -E \
      -e 's/^Macintosh HD:/\//' \
      -e 's/::/:\.\.:/g' \
      -e 's/:/\//g'
  }
  if [[ "$proc_name" =~ ^: ]]; then # Relative path
    echo $(dirname "$root_file")$(convert_igorpath "$proc_name") 
  elif [[ "$proc_name" =~ : ]]; then # Absolute path
    echo $(convert_igorpath "$proc_name")
  else # Procedure name only
    find "$(user_procedures)" -type f -name "$proc_name.ipf" | head -n 1
  fi
}

# Parse options
while (( $# > 0 ))
do
  case "$1" in
    -h | --help )
      usage_exit
      ;;
    -a | --as )
      OPT_AS="$2"
      shift
      ;;
    -i | --include )
      OPT_INCLUDE=1
      ARGS+=$(find_procedure "$2")
      shift
      ;;
    --path )
      user_procedures
      exit 0
      ;;
    -* | --* )
      error "$PROGNAME: illegal option $1"
      exit 1
      ;;
    * )
      ARGS+=("$1")
      ;;
  esac
  shift
done

# Check the number of arguments
if [ ${#ARGS[@]} -lt 1 ]; then
  error "$PROGNAME: too few arguments"
  error "Usage: $PROGNAME [options] [file path]"
  exit 1
elif [ ${#ARGS[@]} -gt 1 ]; then
  if [ -n "$OPT_INCLUDE" ]; then
    error "$PROGNAME: too many arguments"
    error "When you use --include option, you cannot select another file"
  else
    error "$PROGNAME: too many arguments"
    error "Usage: $PROGNAME [options] [file path]"
  fi
  exit 1
fi
ARG="${ARGS[0]}"

# Determines whether $1  may be found within an array
function contains(){
  local arg="$1" 
  shift
  local array=("$@")
  local item
  for item in "${array[@]}"
  do
    if [ "$item" = "$arg" ];then
      return 0
    fi
  done
  return 1
}

# convert: Case? -> [Ca][Aa][Ss][Ee]?
# BSD sed cannot ignore cases :(
function ignorecase_pattern(){
  local pattern="$1"
  if [ -n "$pattern" ]; then
    local char=$(cut -c 1 <<< "$pattern")
    local chars=$(cut -c 2- <<< "$pattern")
    if [[ $char =~ [a-z] ]];then
      local upper=$(sed <<< "$char" \
        'y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/')
      local head="[$char$upper]"
    elif [[ "$char" =~ [A-Z] ]];then
      local lower=$(sed <<< "$char" \
        'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/')
      local head="[$lower$char]"
    else
      local head="$char"
    fi
    local tail=$(ignorecase_pattern "$chars")
    echo "$head$tail"
  fi
}

REGEXP_INCLUDE=$(ignorecase_pattern '^#include +')
REGEXP_MUDULE_NAME=$(ignorecase_pattern '^#pragma ModuleName')
REGEXP_CONSTANT=$(ignorecase_pattern '^(constnat) ')
REGEXP_STRCONSTANT=$(ignorecase_pattern '^(strconstnat) ')
REGEXP_FUNCTION=$(ignorecase_pattern '^(Function) ')

# Rewrite procedure file
function rewrite_procedure(){
  local proc_path="$1"
  local module_name="$2"

  local proc_name=$(basename "$proc_path" .ipf)

  # header
  cat <<EOS
//------------------------------------------------------------------------------
// original file: $proc_name.ipf 
//------------------------------------------------------------------------------
#if !ItemsInList(WinList("$proc_name.ipf",";",""))

EOS
  # body
  cat "$proc_path" | sed -E \
    -e "/$REGEXP_INCLUDE/ s/^/\/\//" \
    -e "/$REGEXP_MUDULE_NAME/ s/^/\/\//" \
    -e "s/$REGEXP_CONSTANT/override \1 /" \
    -e "s/$REGEXP_STRCONSTANT /override \1 /" \
    -e "s/$REGEXP_FUNCTION/override \1 /" \

  # tail
cat <<EOS

#endif

EOS
}
# Rewrite module calls: ModuleName#Function 
function rewrite_modulecall(){
  local module_name="$1"
  shift
  local included_modules=("$@")

  if [ "${#included_modules[@]}" -lt 1 ]; then
    cat -
  else
    local pattern=$(ignorecase_pattern "${included_modules[0]}")
    included_modules=("${included_modules[@]:1}")
    cat - | sed -E "s/$pattern#/$module_name#/g" \
      | rewrite_modulecall "$module_name" "${included_modules[@]}"
  fi
}

# Search included file recursively
function pack_procedures_recursive(){
  local proc_path="$1"
  local module_name="$2"

  local proc_name=$(basename "$proc_path" .ipf)
  if contains "$proc_name" "${included_procs[@]}" ; then
    return 0
  fi
  rewrite_procedure "$proc_path" "$module_name"
  
  # record a leoaded procedure name
  included_procs+=("$proc_name")

  # record a loaded module name
  local included_module=$(egrep -i '^#pragma +ModuleName *=' "$proc_path" \
    | sed -E 's/^[^=]+= *([a-zA-Z_][a-zA-Z_0-9]*).*$/\1/' | head -n 1)
  if [ -n "$included_module" ];then
    included_modules+=("$included_module")
  fi

  local pragma=''
  while read pragma
  do
    local included_proc=$(sed <<< "$pragma" -E 's/^[^"]+"([^"]+)".*$/\1/')
    local included_path=$(find_procedure "$included_proc" "$proc_path")
    if [ -f "$included_path" ]; then
      pack_procedures_recursive "$included_path" "$module_name"
    else
      error "$PROGNAME: $pragma: not found"
    fi
  done < <(egrep -i '^#include +"[^"]+"' "$proc_path")
}

# First step of packaging
# Find file by path and add header
# if it is not found, exit.
function pack_procedures(){
  local proc_path="$1"
  local module_name="$2"
  if [ ! -f "$proc_path" ]; then
    error "$PROGNAME: $included_proc: no such file"
    exit 1
  fi

  local proc_name=$(basename "$1" .ipf)
  if [ -z "$module_name" ]; then
    module_name="$proc_name"
  fi
  cat << EOS
//------------------------------------------------------------------------------
// This procedure file is packaged by $PROGNAME
// $(LANG=en_US.UTF-8 date '+%a,%d %b %Y')
//------------------------------------------------------------------------------
#pragma ModuleName=$module_name

EOS

  local included_procs=()
  local included_modules=()
  pack_procedures_recursive "$proc_path" "$module_name" > "$TMPFILE"
  rewrite_modulecall "$module_name" "${included_modules[@]}" < "$TMPFILE"
}

# Execute
pack_procedures "$ARG" "$OPT_AS" 
