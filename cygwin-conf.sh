#! /usr/bin/env bash

doSetup=false
needList=
topdir=

while [[ $# -gt 0 ]]
do
  arg=$1
  shift
  case ${arg} in
  --list) needList=toolchain,environment,configure ;;
  --list=*) needList=${arg#--list=} ;;
  --setup) doSetup=: ;;
  --topdir=*) topdir=${arg#--topdir=} ;;
  esac
done

if [[ -z ${needList} ]] && ! $doSetup
then
  cat <<EOH
$0 [--list[=[toolchain],[environment],[configure]] [--setup] [--topdir=.]
EOH
  exit 1
fi

setups=()

cd "${topdir:=.}" || exit 1

vsvers=
if [[ -n ${SYSTEMROOT} ]]
then
  systemroot=$(cygpath -u "${SYSTEMROOT}")
  comspec=$(cygpath -u "${COMSPEC}")
  eval "cmd() { PATH=\"${systemroot}:${comspec%/*}:${comspec%/*}/WBEM\" \"${comspec}\" \"\$@\"; }"
  vsvers="15.0 14.0 12.0 11.0 10.0 9.0 8.0"
fi

# query original PATH values used without MSVC
# to identify the MSVC specific PATH values only
eval $(cmd /c set PATH '&&' set INCLUDE '&&' set LIB 2>/dev/null |
  sed -nE "s/\\r\$//; s,\\\\,/,g; /^(PATH|INCLUDE|LIB|LIBPATH)=/s/^([^=]*)=(.*)\$/novc\1=$'\2'/p"
)

for vsver in ${vsvers}
do
  for regroot in \
	  /proc/registry32/HKEY_LOCAL_MACHINE \
	  /proc/registry32/HKEY_CURRENT_USER \
	  /proc/registry64/HKEY_LOCAL_MACHINE \
	  /proc/registry64/HKEY_CURRENT_USER \
  ; do
    [[ -r ${regroot}/SOFTWARE/Microsoft/VisualStudio/SxS/VS7/${vsver} ]] && break
  done
  [[ -r ${regroot}/SOFTWARE/Microsoft/VisualStudio/SxS/VS7/${vsver} ]] || continue

  vsroot=$(cygpath -u "$(tr -d $"\0" < "${regroot}/SOFTWARE/Microsoft/VisualStudio/SxS/VS7/${vsver}")")
  vsroot=${vsroot%%/}

  vcvarsall=${vsroot}/VC/Auxiliary/Build/vcvarsall.bat
  [[ -r ${vcvarsall} ]] ||
  vcvarsall=${vsroot}/VC/vcvarsall.bat

  if [[ -r ${vcvarsall} ]]
  then
    vcPATH= vcINCLUDE= vcLIB= vcLIBPATH=
    INCLUDE= LIB= LIBPATH= \
    eval $(cmd /c "$(cygpath -w "${vcvarsall}")" x86 '&&' set PATH '&&' set INCLUDE '&&' set LIB 2>/dev/null |
      sed -nE "s/\\r\$//; s,\\\\,/,g; /^(PATH|INCLUDE|LIB|LIBPATH)=/s/^([^=]*)=(.*)\$/vc\1=$'\2'/p"
    )
    vcPATH=${vcPATH%${novcPATH}};          vcPATH=${vcPATH%%;}
    vcINCLUDE=${vcINCLUDE%${novcINCLUDE}}; vcINCLUDE=${vcINCLUDE%%;}
    vcLIB=${vcLIB%${novcLIB}};             vcLIB=${vcLIB%%;}
    vcLIBPATH=${vcLIBPATH%${novcLIBPATH}}; vcLIBPATH=${vcLIBPATH%%;}
    if [[ "::${vcPATH}::${vcINCLUDE}::${vcLIB}::${vcLIBPATH}::" != *::::* ]]
    then
      if ${doSetup}
      then
	{
	  echo "PATH=\"$(cygpath -up "${vcPATH}"):\${PATH}\" export PATH;"
	  echo "INCLUDE=\"${vcINCLUDE}\${INCLUDE:+;}\${INCLUDE}\" export INCLUDE;"
	  echo "LIB=\"${vcLIB}\${LIB:+;}\${LIB}\" export LIB;"
	  echo "LIBPATH=\"${vcLIBPATH}\${LIBPATH:+;}\${LIBPATH}\" export LIBPATH;"
	} > "${topdir}/x86-msvc${vsver}.sh"
      fi
      setups+=( "( x86-msvc${vsver} '${topdir}/x86-msvc${vsver}.sh' 'CC=cl CXX=cl GCJ=no GOC=no F77=no FC=no NM=no CFLAGS= CXXFLAGS=' )" )
    fi

    vcPATH= vcINCLUDE= vcLIB= vcLIBPATH=
    PATH=${junkpath}:${PATH} INCLUDE= LIB= LIBPATH= \
    eval $(cmd /c "$(cygpath -w "${vcvarsall}")" x64 '&&' set PATH '&&' set INCLUDE '&&' set LIB 2>/dev/null |
	    sed -nE "s/\\r\$//; s,\\\\,/,g; /^(PATH|INCLUDE|LIB|LIBPATH)=/s/^([^=]*)=(.*)\$/vc\1=$'\2'/p"
    )
    vcPATH=${vcPATH%${novcPATH}};          vcPATH=${vcPATH%%;}
    vcINCLUDE=${vcINCLUDE%${novcINCLUDE}}; vcINCLUDE=${vcINCLUDE%%;}
    vcLIB=${vcLIB%${novcLIB}};             vcLIB=${vcLIB%%;}
    vcLIBPATH=${vcLIBPATH%${novcLIBPATH}}; vcLIBPATH=${vcLIBPATH%%;}
    if [[ "::${vcPATH}::${vcINCLUDE}::${vcLIB}::${vcLIBPATH}::" != *::::* ]]
    then
      if ${doSetup}
      then
	{
	  echo "PATH=\"$(cygpath -up "${vcPATH}"):\${PATH}\" export PATH;"
	  echo "INCLUDE=\"${vcINCLUDE}\${INCLUDE:+;}\${INCLUDE}\" export INCLUDE;"
	  echo "LIB=\"${vcLIB}\${LIB:+;}\${LIB}\" export LIB;"
	  echo "LIBPATH=\"${vcLIBPATH}\${LIBPATH:+;}\${LIBPATH}\" export LIBPATH;"
	} > "${topdir}/x64-msvc${vsver}.sh"
      fi
      setups+=( "( x64-msvc${vsver} '${topdir}/x64-msvc${vsver}.sh' 'CC=cl CXX=cl GCJ=no GOC=no F77=no FC=no NM=no CFLAGS= CXXFLAGS=' )" )
    fi
  fi
done

x86-cygwin() { false; }
x64-cygwin() { false; }
x86-mingw() { false; }
x64-mingw() { false; }
x86-winnt() { false; }
x64-winnt() { false; }

type -P     i686-pc-cygwin-gcc >/dev/null && type -P     i686-pc-cygwin-g++ >/dev/null && x86-cygwin() { printf "${1+%s}" "$@" ; }
type -P   x86_64-pc-cygwin-gcc >/dev/null && type -P   x86_64-pc-cygwin-g++ >/dev/null && x64-cygwin() { printf "${1+%s}" "$@" ; }
type -P   i686-w64-mingw32-gcc >/dev/null && type -P   i686-w64-mingw32-g++ >/dev/null && x86-mingw()  { printf "${1+%s}" "$@" ; }
type -P x86_64-w64-mingw32-gcc >/dev/null && type -P x86_64-w64-mingw32-g++ >/dev/null && x64-mingw()  { printf "${1+%s}" "$@" ; }
type -P      i586-pc-winnt-gcc >/dev/null && type -P      i586-pc-winnt-g++ >/dev/null && x86-winnt()  { printf "${1+%s}" "$@" ; }
type -P    x86_64-pc-winnt-gcc >/dev/null && type -P    x86_64-pc-winnt-g++ >/dev/null && x64-winnt()  { printf "${1+%s}" "$@" ; }

setups=("${setups[@]}"
  "$(x86-cygwin  "( x86-cygwin '' '--host=i686-pc-cygwin' )")"
  "$(x64-cygwin  "( x64-cygwin '' '--host=x86_64-pc-cygwin' )")"
  "$(x86-mingw   "( x86-mingw  '' '--host=i686-w64-mingw32' )")"
  "$(x64-mingw   "( x64-mingw  '' '--host=x86_64-w64-mingw32' )")"
  "$(x86-winnt   "( x86-winnt  '' '--host=i586-pc-winnt' )")"

  "$(x64-mingw   "( x64-mingw  '' '--host=x86_64-w64-mingw32' )")"
  "$(x86-winnt   "( x86-winnt  '' '--host=i586-pc-winnt' )")"
  "$(x64-winnt   "( x64-winnt  '' '--host=x86_64-pc-winnt' )")"
)

if [[ -n ${needList} ]]
then
  for setup in "${setups[@]}"
  do
    eval setup="${setup}"
    [[ -n ${setup[0]} ]] || continue
    [[ ,${needList}, == *,toolchain,* ]] && echo -n "toolchain_name='${setup[0]}';"
    [[ ,${needList}, == *,environment,* ]] && echo -n "environment_file='${setup[1]}';"
    [[ ,${needList}, == *,configure,* ]] && echo -n "configure_arguments='${setup[2]}';"
    echo
  done
fi
