#! /usr/bin/env bash

export CONFIG_SHELL=${BASH}
# export PATH=/usr/bin:/bin

makeopts=()
while true
do
  case $1 in
  (-*) makeopts=("${makeopts[@]}" "$1"); shift ;;
  (*) break ;;
  esac
done

srcdir=$(cd "${1:-./libtool}" && pwd -P)
shift
topdir=${srcdir%/*}/test-${srcdir##*/}
mkdir -p "$topdir" 
topdir=$(cd "${topdir}" && pwd -P)

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
	{
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

make "${makeopts[@]}" -r -f - <<EOM
SHELL = ${CONFIG_SHELL:-/bin/sh}
all: variants
VARIANTS=
$(
for combo in "${combos[@]}"; do
    [[ -n ${combo} ]] || continue
    (
	eval "combodef=${combo}"
	build=${combodef[0]}
	envfile=${combodef[1]}
	confargs=${combodef[2]}

	case " ${*} " in # (
	*" ${build} "*) echo "${build} skipped" >&2; exit 0 ;;
	esac

	echo "${build} scheduled" >&2

	echo "VARIANTS += ${build}"
	echo "${build}:"
	echo "	@mkdir -p '${topdir}/${build}' && \\"
	echo "	cd '${topdir}/${build}' && \\"
	echo "	rm -rf ./build ./install ./image && \\"
	echo "	mkdir ./build && \\"
	echo "	cd ./build && \\"
	[[ -n ${envfile} ]] &&
	echo "	. '${envfile}' && \\"
	cmds=
	cmds="${cmds}$CONFIG_SHELL '${srcdir}/configure'"
	cmds="${cmds} '--prefix=${topdir}/${build}/install'"
	cmds="${cmds} ${confargs}"
	cmds="${cmds} > configure.out 2>&1"
	cmds="${cmds} && make V=1 all > make.out 2>&1"
	cmds="${cmds} && make V=1 install DESTDIR='${topdir}/${build}/image' > install.out 2>&1"
	cmds="${cmds} && make V=1 check > check.out 2>&1"
	echo "	${cmds} || true"
    )
done
)
.PHONY: \$(VARIANTS)
variants: \$(VARIANTS)
EOM
