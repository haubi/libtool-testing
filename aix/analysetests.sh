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

combodefs=(
    " gcc/g++ :gcc-g++:gnu"
    " xlc/g++ :xlc-g++:mix"
    " xlc/xlC :xlc-xlC:xlc"
)

bitdefs=(
    ' 32 :32bit'
    ' 64 :64bit'
)

rtldefs=(
    ':rtlaix'
    '(rtl):rtlyes'
)

sodefs=(
    'trad'
    'both'
    'svr4'
)

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

echo
indent=$(printf "%3s  " '')
printf "%s%4s %7s" "${indent}" 'bits' 'compilers'
indent+=$(printf "%4s %7s" '' '')

for rtldef in "${rtldefs[@]}";  do
  rtltext=${rtldef%%:*}
  printf " %s" "${rtltext}"
  for testdir in "${testdirs[@]}"; do
    printf "| %-23s " "${testdir##*/test-}"
  done
done
indent+='  '

printf "\n%s" "${indent}"
for rtldef in "${rtldefs[@]}";  do
  rtltext=${rtldef%%:*}
  printf " %-*s" ${#rtltext} ''
  for testdir in "${testdirs[@]}"; do
    printf "|"
    for sodef in "${sodefs[@]}"; do
      soname=${sodef%%:*}
      printf " %-7s" "${soname}"
    done
    printf " "
  done
done

printf "\n"

for tdesc in "${testcases[@]}"; do
  tno=${tdesc%%;*};     tdesc=${tdesc#${tno};}
  tloc=${tdesc%%;*};    tdesc=${tdesc#${tloc};}
  tname=${tdesc%%;*};   tdesc=${tdesc#${tname};}
  tdomain=${tdesc%%;*}; tdesc=${tdesc#${tdomain};}

  headerLine="$(printf "%3s: %s" "${tno}" "${tname}")\n"
  indent=$(printf "%3s  " '')

  for bitsdef  in "${bitdefs[@]}"; do
    bitstext=${bitsdef%%:*}
    bitsdir=${bitsdef##*:}
    bitsvar=${bitsdir%bit}

    for combodef in "${combodefs[@]}";    do
      cctext=${combodef%%:*}
      ccdir=${combodef#*:}
      ccdir=${ccdir%:*}
      ccvar=${combodef##*:}
      hasDiff=false
      bodyLine="$(printf "%s%4s %9s" "${indent}" "${bitstext}" "${cctext}")"

      for rtldef in "${rtldefs[@]}";  do
	rtltext=${rtldef%%:*}
	rtldir=${rtldef##*:}
	rtlvar=${rtldir}
	unset firstResult
	bodyLine+="$(printf " %${#rtltext}s" '')"

	testdirno=0
	for testdir in "${testdirs[@]}"; do
	  (( ++testdirno ))

	  thisResult=""
	  bodyLine+="|"

	  for sodef in "${sodefs[@]}"; do
	    soname=${sodef%%:*}
	    sodir=${sodef##*:}
	    sovar=${sodir}

	    fdvar=${ccvar}${bitsvar}${rtlvar}${sovar}${testdirno}_fd

	    eval "fd=\${${fdvar}-unset}"

	    if [[ ${fd} == unset ]]; then
	      file=${testdir}/${ccdir}-${bitsdir}-${rtldir}-${sodir}/build/check.out
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
	    thisResult+="$(printf " %-7s" "${result}")"
	  done
	  thisResult+=" "
	  bodyLine+="${thisResult}"
	  if [[ "${firstResult-unset}" = unset ]]; then
	    firstResult=${thisResult}
	  elif [[ "${firstResult}" != "${thisResult}" ]]; then
	    hasDiff=true
	  fi
	done
      done
      bodyLine+="\n"
      if (( ${toShow} >= $AllHeaders )) || ${hasDiff}; then
	printf "${headerLine}"
	headerLine=
      fi
      if (( ${toShow} >= $AllResults )) || ${hasDiff}; then
	printf "${bodyLine}"
      fi
    done
  done
done
