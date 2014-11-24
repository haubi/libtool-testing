#! /usr/bin/env bash

export CONFIG_SHELL=${BASH}
export PATH=${PATH}:/usr/vacpp/bin:/usr/vac/bin

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

combos=()
   #"( 'combo:LDFLAGSprefix' 'CC:BITSprefix' 'CXX:BITSprefix' )"

type -P gcc && type -P g++ && combos=("${combos[@]}"
    "( 'gcc-g++:-Wl,'        'gcc:-maix'     'g++:-maix'      )"
)
type -P xlc && type -P g++ && combos=("${combos[@]}"
    "( 'xlc-g++:-Wl,'        'xlc:-q'        'g++:-maix'      )"
)
type -P xlc && type -P xlC && combos=("${combos[@]}"
    "( 'xlc-xlC:'            'xlc:-q'        'xlC:-q'         )"
)

bitsnames=()
   #'bitsname:bits-to-set'

bitsnames=("${bitsnames[@]}"
    '32bit:' \
)
bitsnames=("${bitsnames[@]}"
    '64bit:64' \
)

rtlnames=()
   #'rtlname:ldflags-to-set'

rtlnames=("${rtlnames[@]}"
    'rtlaix:'
)
rtlnames=("${rtlnames[@]}"
    'rtlyes:-brtl'
)

sonames=()
   #'soname:configure-flag'
sonames=("${sonames[@]}"
    'trad:'
)
grep -q aix-soname "${srcdir}/configure" &&
sonames=("${sonames[@]}"
    'both:--with-aix-soname=both'
)
grep -q aix-soname "${srcdir}/configure" &&
sonames=("${sonames[@]}"
    'svr4:--with-aix-soname=svr4'
)

gmake "${makeopts[@]}" -r -f - <<EOM
SHELL = ${CONFIG_SHELL:-/bin/sh}
all: variants
VARIANTS=
$(
for combo in "${combos[@]}"; do
    for bitsname in "${bitsnames[@]}"; do
        for rtlname in "${rtlnames[@]}"; do
            for soname in "${sonames[@]}"; do
                (
                    soconf=${soname#*:}
                    soname=${soname%%:*}
                    rtlflag=${rtlname#*:}
                    rtlname=${rtlname%%:*}
                    bits=${bitsname#*:}
                    bitsname=${bitsname%%:*}

                    eval combo=${combo}
                    ldfp=${combo[0]}
                    ldfp=${ldfp#*:}
                    cc=${combo[1]}
                    bitsp=${cc#*:}
                    cc=${cc%%:*}${bits:+ ${bitsp}${bits}}
                    cxx=${combo[2]}
                    bitsp=${cxx#*:}
                    cxx=${cxx%%:*}${bits:+ ${bitsp}${bits}}
                    combo=${combo[0]}
                    combo=${combo%%:*}
                    build=
                    build=${build:+${build}-}${combo}
                    build=${build:+${build}-}${bitsname}
                    build=${build:+${build}-}${rtlname}
                    build=${build:+${build}-}${soname}

                    case " ${*} " in
                    *" ${build} "*) echo "${build} skipped" >&2; exit 0 ;;
                    esac

		    echo "${build} scheduled" >&2

                    unset OBJECT_MODE CC CXX LDFLAGS

                    echo "VARIANTS += ${build}"
                    echo "${build}:"
                    echo "	@mkdir -p '${topdir}/${build}' && \\"
                    echo "	cd '${topdir}/${build}' && \\"
                    echo "	rm -rf ./build ./install ./image && \\"
                    echo "	mkdir ./build && \\"
                    echo "	cd ./build && \\"
                    cmds=
                    cmds="${cmds}${bits:+export OBJECT_MODE='${bits}' && }"
                    cmds="${cmds}$CONFIG_SHELL '${srcdir}/configure'"
                    cmds="${cmds} '--prefix=${topdir}/${build}/install'"
                    cmds="${cmds} ${soconf}"
                    cmds="${cmds} CC='${cc}'"
                    cmds="${cmds} CXX='${cxx}'"
                    cmds="${cmds}${rtlflag:+ LDFLAGS='${ldfp}${rtlflag}'}"
                    cmds="${cmds} > configure.out 2>&1"
                    cmds="${cmds} && gmake all > make.out 2>&1"
                    cmds="${cmds} && gmake install DESTDIR='${topdir}/${build}/image' > install.out 2>&1"
                    cmds="${cmds} && gmake check > check.out 2>&1"
                    echo "	${cmds} || true"
                )
            done
        done
    done
done
)
.PHONY: \$(VARIANTS)
variants: \$(VARIANTS)
EOM
