#! /usr/bin/env bash

mydir=$(cd "$(dirname "$0")" && pwd -P) || exit 1

export CONFIG_SHELL=${BASH}

make=$(type -P gmake)
[[ -n ${make} ]] || make=$(type -P make)
if [[ -z ${make} ]]
then
	echo "ERROR: No gmake or make program found." >&2
	exit 1
fi

topdir=
os_conf=
makeopts=()

while [[ $# -gt 0 ]]
do
	arg=$1
	shift
	case ${arg} in
	--topdir=*) topdir=${arg#--topdir=} ;;
	--os-conf=*) os_conf=${arg#--os-conf=} ;;
	-*) makeopts=("${makeopts[@]}" "${arg}") ;;
	*) srcdir=${arg}; break ;;
	esac
done

# support relative path in --os-conf
case ${os_conf} in
/* | "") ;;
*) os_conf=$(pwd)/${os_conf} ;;
esac

#
# changes to topdir if set, or srcdir/..
#
if [[ -z ${srcdir} || ! -r ${srcdir}/. ]] ||
   ! cd "${topdir:-"${srcdir}"/..}"
then
	cat <<-EOH
	${0} [-jN] [--topdir=/path/to/test-topdir] [--os-conf=/path/to/os-conf.sh] /path/to/libtool-srcdir...
	EOH
	exit 1
fi

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

srcdir=$(cd "${srcdir}" && pwd -P) || exit 1

mkdir -p "test-${srcdir##*/}" || exit 1

cd "test-${srcdir##*/}" || exit 1

topdir=$(pwd) || exit 1

echo "Querying OS configuration from \"${os_conf}\" ..."
conflines=$("${BASH}" "${os_conf}" --list=toolchain,environment,configure --setup)

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
	toolchain_configs+=( "tcname='${toolchain_name}';envfile='${environment_file}';confargs='${configure_arguments}'" )
done <<< "${conflines}"

exec "${make}" "${makeopts[@]}" -r -f - <<EOM
SHELL = ${CONFIG_SHELL:-/bin/sh}
all: variants
VARIANTS=
$(
for tc_conf in "${toolchain_configs[@]}"; do
	tcname=; envfile=; confargs=;
	eval ${tc_conf}
	[[ -n ${tcname} ]] || continue

	case " ${*} " in # (
	*" ${tcname} "*) echo "${tcname} skipped" >&2; exit 0 ;;
	esac

	echo "${tcname} scheduled" >&2

	echo "VARIANTS += ${tcname}"
	echo "${tcname}:"
	echo "	@mkdir -p './${tcname}' && \\"
	[[ -n ${envfile} ]] &&
	echo "	. '${envfile}' && \\"
	echo "	cd './${tcname}' && \\"
	echo "	rm -rf ./build ./install ./image && \\"
	echo "	mkdir ./build && \\"
	echo "	cd ./build && \\"
	cmds=
	cmds="${cmds}$CONFIG_SHELL '${srcdir}/configure'"
	cmds="${cmds} '--prefix=${topdir}/${tcname}/install'"
	cmds="${cmds} ${confargs}"
	cmds="${cmds} > configure.out 2>&1"
	cmds="${cmds} && make V=1 all > make.out 2>&1"
	cmds="${cmds} && make V=1 install DESTDIR='${topdir}/${tcname}/image' > install.out 2>&1"
	cmds="${cmds} && make V=1 check > check.out 2>&1"
	echo "	${cmds} || true"
done
)
.PHONY: \$(VARIANTS)
variants: \$(VARIANTS)
EOM
