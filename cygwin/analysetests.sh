#! /usr/bin/env bash

die() {
  test -n "$*" && echo "$@" >&2
  exit 1
}

DiffOnly=0
AllHeaders=1
AllResults=2

toShow=$DiffOnly

srcdir=()
testdirs=()
dirtarget=srcdir

while (( $# > 0 ))
do
  case $1 in
  --all) toShow=$AllResults ;;
  --headers) toShow=$AllHeaders ;;
  --diff) toShow=$DiffOnly ;;
  --help|--*) cat <<EOF

$0 [--all|--headers|--diff|--help] <srcdir> <testrundirs...>

Analyze and compare libtool test suite results from running on AIX in
<testrundirs....>, using test cases from libtool source found in <srcdir>.

Output is one line per test-case and compiler-combo, and one column per test
run configured with "LDFLAGS=-brtl" and "--with-aix-soname={aix,both,svr4}".

 --all
 --diff
     Show results from all test runs even if identical across all test runs.
     Default is to show results which change across test runs.

 --help
     This help.

EOF
    exit 0 ;;
  *)
    eval "$dirtarget+=( \$1 )"
    dirtarget=testdirs
    ;;
  esac
  shift
done

if [[ ${#srcdir} == 0 ]]; then
  die "missing <srcdir> (try $0 --help)"
fi

srcdir=$(cd "${srcdir[0]}" && pwd -P)
if [[ -z ${srcdir} ]]; then
  die "invalid <srcdir> (try $0 --help)"
fi

set -- "${testdirs[@]}"
testdirs=()

while (( $# > 0 ))
do
  testdirs=("${testdirs[@]}" "$(cd "${1}" && pwd -P)" )
  shift
done

if [[ ${#testdirs} == 0 ]]; then
  die "missing <testrundirs...> (try $0 --help)"
fi

x86-cygwin() { false; }
x64-cygwin() { false; }
x86-mingw() { false; }
x64-mingw() { false; }
x86-winnt() { false; }
x64-winnt() { false; }

combos=()

SxSVS7reg=/proc/registry32/HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/VisualStudio/SxS/VS7

WindowsSDK=$(cygpath -u "$(tr -d $"\0" <"/proc/registry32/HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/Microsoft SDKs/Windows/CurrentInstallFolder")")
WindowsSDK=${WindowsSDK%%/}

[[ -n "${WindowsSDK}" ]] &&
for msver in 15.0 14.0 13.0 12.0 11.0 10.0 9.0 8.0
do
    [[ -r ${SxSVS7reg}/${msver} ]] || continue
    vsroot=$(cygpath -u "$(tr -d $"\0" < ${SxSVS7reg}/${msver})")
    vsroot=${vsroot%%/}
    vscom=${vsroot}/Common7/Tools
    vsver=${msver//.}
    if [[ -r ${vsroot}/VC/bin/vcvars32.bat ]]; then
	true || {
	    echo "export PATH='${vsroot}/Common7/IDE:${vsroot}/VC/bin:${vsroot}/Common7/Tools:${WindowsSDK}/bin:'\${PATH}"
	    echo "export INCLUDE='$(cygpath -mp "${vsroot}/VC/include:${WindowsSDK}/include")'"
	    echo "export LIB='$(cygpath -mp "${vsroot}/VC/lib:${WindowsSDK}/lib")'"
	    echo "export LIBPATH='$(cygpath -mp "${vsroot}/VC/lib")'"
	} > "${topdir}/msvc${vsver}env32.sh"
	combos+=( "( x86-msvc$vsver '${topdir}/msvc${vsver}env32.sh' 'CC=cl CXX=\"cl /TP\" GCJ=no GOC=no F77=no FC=no NM=no CFLAGS= CXXFLAGS=' )" )
    fi
done

type -P     i686-pc-cygwin-gcc && type -P     i686-pc-cygwin-g++ && x86-cygwin() { printf "${1+%s}" "$@" ; }
type -P   x86_64-pc-cygwin-gcc && type -P   x86_64-pc-cygwin-g++ && x64-cygwin() { printf "${1+%s}" "$@" ; }
type -P   i686-w64-mingw32-gcc && type -P   i686-w64-mingw32-g++ && x86-mingw()  { printf "${1+%s}" "$@" ; }
type -P x86_64-w64-mingw32-gcc && type -P x86_64-w64-mingw32-g++ && x64-mingw()  { printf "${1+%s}" "$@" ; }
type -P      i586-pc-winnt-gcc && type -P      i586-pc-winnt-g++ && x86-winnt()  { printf "${1+%s}" "$@" ; }
type -P    x86_64-pc-winnt-gcc && type -P    x86_64-pc-winnt-g++ && x64-winnt()  { printf "${1+%s}" "$@" ; }

combos=("${combos[@]}"
    "$(x86-cygwin  "( x86-cygwin '' '--host=i686-pc-cygwin' )")"
    "$(x64-cygwin  "( x64-cygwin '' '--host=x86_64-pc-cygwin' )")"
    "$(x86-mingw   "( x86-mingw  '' '--host=i686-w64-mingw32' )")"
    "$(x64-mingw   "( x64-mingw  '' '--host=x86_64-w64-mingw32' )")"
    "$(x86-winnt   "( x86-winnt  '' '--host=i586-pc-winnt' )")"
    "$(x64-winnt   "( x64-winnt  '' '--host=x86_64-pc-winnt' )")"
)

col_names=()
row_names=()
cell_names=()

for combo in "${combos[@]}"
do
    [[ -n ${combo} ]] || continue
    eval "combodef=${combo}"
    cellname=${combodef[0]}

    cell_names+=("${cellname}")

    rowname=${cellname%%-*} # x86, x64
    colname=${cellname#*-} # cygwin, msvcXX, ...

    case " ${row_names[*]} " in
    *" ${rowname} "*) ;;
    *) row_names+=("${rowname}") ;;
    esac

    case " ${col_names[*]} " in
    *" ${colname} "*) ;;
    *) col_names+=("${colname}") ;;
    esac
done

close_file() {
  local var=$1
  (( ${!var:--1} >= 0 )) || return 1
  eval "exec ${!var}<&-"
  eval "${var}=-1"
}

open_file() {
  local var=$1 redir=$2 file=$3
  if [[ $(( (BASH_VERSINFO[0] << 8) + BASH_VERSINFO[1] )) -ge $(( (4 << 8) + 1 )) ]] ; then
    # Newer bash provides this functionality.
    eval "exec {${var}}${redir}'${file}'"
  else
    # Need to provide the functionality ourselves.
    local fd=10
    while :; do
      # Make sure the fd isn't open. Any open fd can be opened
      # for input, even if it originally was opened for output.
      if ! ( : <&${fd} ) 2>/dev/null ; then
	eval "exec ${fd}${redir}'${file}'" && break
      fi
      [[ ${fd} -gt 1024 ]] && die 'could not locate a free temp fd !?'
      : $(( ++fd ))
    done
    : $(( ${var} = fd ))
  fi
}

eval testcases=(
  $(sed -n -e "/^at_help_all=\"/,/^\"/{
      s/^.*\"//;
      s/^/\"/;
      s/\$/\"/;
      s/^\"\"$//;
      p;
    }" < ${srcdir}/tests/testsuite
  )
)

printf "\n"

testwidth=0
for colname in "${col_names[@]}"; do
  (( testwidth += ${#colname} + 3 ))
done

printf '%3s %3s  ' "" ""

for (( testdirno = 1; testdirno <= ${#testdirs[@]}; ++testdirno )); do
  printf "|"
  for colname in "${col_names[@]}"; do
    printf ' %-6s |' "${colname}"
  done
done

printf "\n"

for (( testdirno = 1; testdirno <= ${#testdirs[@]}; ++testdirno )); do
  case " ${cell_names[*]} " in
  *" ${cellname} "*)
    eval 'cellvalue=$'"{result_${cellname//-/_}_${testdirno}}"
    ;;
  esac
done

for tdesc in "${testcases[@]}"; do
  tno=${tdesc%%;*};     tdesc=${tdesc#${tno};}
  tloc=${tdesc%%;*};    tdesc=${tdesc#${tloc};}
  tname=${tdesc%%;*};   tdesc=${tdesc#${tname};}
  tdomain=${tdesc%%;*}; tdesc=${tdesc#${tdomain};}

  for combo in "${combos[@]}";    do
    [[ -n ${combo} ]] || continue
    eval "combodef=${combo}"
    build=${combodef[0]}

    testdirno=0
    for testdir in "${testdirs[@]}"; do
      (( ++testdirno ))

      resultvar=result_${build//-/_}_${testdirno}

      fdvar=fd_${build//-/_}_${testdirno}

      eval "fd=\${${fdvar}-unset}"

      if [[ ${fd} == unset ]]; then
	file=${testdir}/${build}/build/check.out
	if [[ -r ${file} ]]; then
	  open_file "${fdvar}" '<' "${file}"
	else
	  eval "${fdvar}=-1"
	fi
	fd=${!fdvar}
      fi

      result=""
      while (( fd >= 0))
      do
	if ! read -u ${fd}; then
	  close_file ${fdvar}
	  fd=-1
	  break
	fi
	if [[ ${REPLY} =~ ^[' '0-9]*:.* ]]; then
	  # got a line with a test result
	  if [[ ${REPLY} =~ ^' '*"${tno}: ${tname} "*(.*)$ ]]; then
	    result=${BASH_REMATCH[1]}
	    result=${result%%' ('*}
	    [[ ${result} == 'expected failure' ]] && result='xfail'
	    [[ ${result} == 'skipped' ]] && result='skip'
	  else
	    result=err
	  fi
	  break
	fi
      done
      eval $resultvar='$result'
    done
  done

  testcaseHeader="$(printf "%3d: %s" "${tno}" "${tname}")"

  for rowname in "${row_names[@]}"; do
    hasDiff=false
    rowContent=
    prevResult=
    for (( testdirno = 1; testdirno <= ${#testdirs[@]}; ++testdirno )); do
      thisResult="|"
      for colname in "${col_names[@]}"; do
	cellname="${rowname}-${colname}"
	case " ${cell_names[*]} " in
	*" ${cellname} "*)
	  eval 'cellvalue=$'"{result_${cellname//-/_}_${testdirno}}"
	  ;;
	*) cellvalue="" ;;
	esac
        thisResult+=$(printf " %-6s |" "${cellvalue}")
      done
      rowContent+=${thisResult}
      if [[ -z ${prevResult} ]]; then
      	prevResult=${thisResult}
      elif [[ ${thisResult} != "${prevResult}" ]]; then
      	hasDiff=true
      fi
    done
    if ${hasDiff} || [[ ${toShow} -ge ${AllHeaders} ]]; then
      [[ -n ${testcaseHeader} ]] && printf "%s\n" "${testcaseHeader}"
      testcaseHeader=""
    fi
    if ${hasDiff} || [[ ${toShow} -ge ${AllResults} ]]; then
      printf "     %3s %s\n" "${rowname}" "${rowContent}"
    fi
  done
done
