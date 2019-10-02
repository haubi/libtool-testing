#! /usr/bin/env bash

mydir=$(cd "$(dirname "$0")" && pwd -P) || exit 1

DiffOnly=0
AllHeaders=1
AllResults=2

toShow=$DiffOnly

os_conf=
srcdir=()
testdirs=()
dirtarget=srcdir

die() {
  test -n "$*" && echo "$@" >&2
  exit 1
}

while (( $# > 0 ))
do
  case $1 in
  --debug) PS4='($LINENO)+ '; set -x ;;
  --os-conf=*) os_conf=${arg#--os-conf=} ;;
  --all) toShow=$AllResults ;;
  --headers) toShow=$AllHeaders ;;
  --diff) toShow=$DiffOnly ;;
  --help|--*) cat <<EOF

$0 [--all|--headers|--diff|--help] [--os-conf=/path/to/os-conf.sh] <srcdir> <testrundirs...>

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

if [[ ${#testdirs[@]} == 0 ]]; then
  die "missing <testrundirs...> (try $0 --help)"
fi

# support relative path in --os-conf
case ${os_conf} in
/* | "") ;;
*) os_conf=$(pwd)/${os_conf} ;;
esac

if [[ -z ${os_conf} ]]
then
  case $(uname) in
  AIX*) os_conf="${mydir}/aix-conf.sh" ;;
  CYGWIN*) os_conf="${mydir}/cygwin-conf.sh" ;;
  esac
fi

if [[ -z ${os_conf} ]]
then
  echo "ERROR: Unknown OS $(uname), please specify \"--os-conf=/path/to/os-conf.sh\"." >&2
  exit 1
fi

if [[ ! -r ${os_conf} ]]
then
  echo "ERROR: Cannot read (--os-conf) \"${os_conf}\"." >&2
  exit 1
fi

echo "Querying OS configuration from \"${os_conf}\" ..."
conflines=$("${BASH}" "${os_conf}" --list=toolchain)

if [[ $? -ne 0 ]]
then
  echo "ERROR: Querying OS configuration from \"${os_conf}\" failed." >&2
  exit 1
fi

toolchain_configs=()

while read confline
do
  toolchain_name=
  environment_file=
  configure_arguments=
  eval $(
    eval "${confline}"
    echo "toolchain_name='${toolchain_name}';"
    echo "environment_file='${environment_file}';"
    echo "configure_arguments='${configure_arguments}';"
  )
  [[ -n ${toolchain_name} ]] || continue
  toolchain_configs+=( "tcname='${toolchain_name}'" )
done <<< "${conflines}"

col_names=()
row_names=()
cell_names=()

for tc_conf in "${toolchain_configs[@]}"
do
  eval ${tc_conf}

  cell_names+=("${tcname}")

  rowname=${tcname%%-*} # x86, x64
  colname=${tcname#*-} # cygwin, msvcXX, ...

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

if [[ $(( (BASH_VERSINFO[0] << 8) + BASH_VERSINFO[1] )) -ge $(( (4 << 8) + 1 )) ]] ; then
  # Newer bash provides this functionality.
  open_file() {
    local var=$1 redir=$2 file=$3
    eval "exec {${var}}${redir}'${file}'"
  }
else
  # Need to provide the functionality ourselves.
  open_file() {
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
  }
fi

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

testwidth=0
for colname in "${col_names[@]}"; do
  (( testwidth += ${#colname} + 3 ))
done

rownamewidth=0
for rowname in "${row_names[@]}"; do
  (( rownamewidth >= ${#rowname} )) || rownamewidth=${#rowname}
done

testcolwidth=-3
for colname in "${col_names[@]}"; do
  colwidth=${#colname}
  # min width to hold one of "ok", "skip", "xfail", "FAILED"
  (( colwidth >= 6 )) || colwidth=6
  (( testcolwidth += colwidth + 3 ))
done

show_headers() {
  printf "\n"

  printf "%3s %${rownamewidth}s  " "" ""
  for (( testdirno = 0; testdirno < ${#testdirs[@]}; ++testdirno )); do
    printf "| %-${testcolwidth}s |" "${testdirs[${testdirno}]##*-libtool-}"
  done
  printf "\n"

  printf "%3s %${rownamewidth}s  " "" ""
  for (( testdirno = 1; testdirno <= ${#testdirs[@]}; ++testdirno )); do
    printf "|"
    for colname in "${col_names[@]}"; do
      printf ' %-6s |' "${colname}"
    done
  done
  printf "\n"

  printf "\n"
}

show_headers

testcasesshown=0

for tdesc in "${testcases[@]}"; do
  tno=${tdesc%%;*};     tdesc=${tdesc#${tno};}
  tloc=${tdesc%%;*};    tdesc=${tdesc#${tloc};}
  tname=${tdesc%%;*};   tdesc=${tdesc#${tname};}
  tdomain=${tdesc%%;*}; tdesc=${tdesc#${tdomain};}

  for tc_conf in "${toolchain_configs[@]}";    do
    eval "${tc_conf}"

    testdirno=0
    for testdir in "${testdirs[@]}"; do
      (( ++testdirno ))

      resultvar=result_${tcname//[^a-zA-Z0-9]/_}_${testdirno}

      fdvar=fd_${tcname//[^a-zA-Z0-9]/_}_${testdirno}

      eval "fd=\${${fdvar}-unset}"

      if [[ ${fd} == unset ]]; then
	file=${testdir}/${tcname}/build/check.out
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
	  eval 'cellvalue=$'"{result_${cellname//[^a-zA-Z0-9]/_}_${testdirno}}"
	  ;;
	*) cellvalue="" ;;
	esac
	colwidth=${#colname}
        # min width to hold one of "ok", "skip", "xfail", "FAILED"
	(( colwidth >= 6 )) || colwidth=6
        thisResult+=$(printf " %-*s |" "${colwidth}" "${cellvalue}")
      done
      rowContent+=${thisResult}
      if [[ -z ${prevResult} ]]; then
      	prevResult=${thisResult}
      elif [[ ${thisResult} != "${prevResult}" ]]; then
      	hasDiff=true
      fi
    done
    if ${hasDiff} || [[ ${toShow} -ge ${AllHeaders} ]]; then
      if [[ -n ${testcaseHeader} ]]
      then
        (( testcasesshown % 10 == 0 )) && (( testcasesshown > 0 )) && show_headers
        (( ++testcasesshown ))
        printf "%s\n" "${testcaseHeader}"
      fi
      testcaseHeader=""
    fi
    if ${hasDiff} || [[ ${toShow} -ge ${AllResults} ]]; then
      printf "     %${rownamewidth}s %s\n" "${rowname}" "${rowContent}"
    fi
  done
done
