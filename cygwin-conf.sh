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
  --debug) PS4='($LINENO)+ '; set -x; ;;
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

# <for functions copied from parity-setup>
get-chost() { echo "$@"; }
verbose() { :; }
traceon() { :; }
traceoff() { :; }
noquiet() { :; }
is-supported-chost() { :; }
# </for functions copied from parity-setup>
# <functions copied from parity-setup>

[[ -r "/proc/registry/HKEY_LOCAL_MACHINE/SOFTWARE/." ]] || exit 0

windir=$(cygpath -W)
sysdir=$(cygpath -S)

eval "cmd() {
  ( set -x
	tmpfile=\`mktemp\`
	trap \"rm -f '\${tmpfile}' '\${tmpfile}.bat'\" 0
	mv -f \"\${tmpfile}\" \"\${tmpfile}.bat\"
	for x in \"\$@\"; do echo \"\$x\"; done > \"\${tmpfile}.bat\"
	chmod +x \"\${tmpfile}.bat\"
	PATH=\"${windir}:${sysdir}:${sysdir}/WBEM\" \"\${tmpfile}.bat\"
  )
}"

get-vscrt() {
	local vscrt=${1}
	case ${vscrt} in
	libcmtd*|*-libcmtd*|staticdebug) echo "libcmtd" ;;
	libcmt*|*-libcmt*|static) echo "libcmt" ;;
	msvcd*|*-msvcd*|dynamicdebug) echo "msvcd" ;;
	*) echo "msvc" ;;
	esac
	return 0
}

get-vsver() {
	local vscrt=$(get-vscrt "$1")
	local vsver=${1##*${vscrt}}
	vsver=${vsver%%-*}
	case ${vsver} in
	            1[5-9].*        ) echo "${vsver%.*}" ;;
	            1[5-9]          ) echo "${vsver}" ;;
	[7-9]      |1[0-4]          ) echo "${vsver}.0" ;;
	[7-9].[0-9]|[1-9][0-9].[0-9]) echo "${vsver}" ;;
	esac
	return 0
}

get-vsarch() {
	local vsarch=${1%%-*}
	case ${vsarch} in
	x64|amd64|x86_64) echo "x64" ;;
	x86|i?86)         echo "x86" ;;
	esac
	return 0
}

regquery() {
	regquery_result=
	if [[ -r /proc/registry/${1}/${2:-.}/. ]]
	then
		return 0
	fi
	if [[ -r /proc/registry/${1}/${2} ]]
	then
		regquery_result=`tr -d \\\\0 < "/proc/registry/${1}/${2}"`
		return $?
	fi
	return 1
}

regquery_vsroot() {
	local vsver=$(get-vsver "${1}")
	if regquery HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/Microsoft/VisualStudio/SxS/VS7 "${vsver}" \
	|| regquery HKEY_CURRENT_USER/SOFTWARE/Wow6432Node/Microsoft/VisualStudio/SxS/VS7 "${vsver}" \
	|| regquery HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/VisualStudio/SxS/VS7 "${vsver}" \
	|| regquery HKEY_CURRENT_USER/SOFTWARE/Microsoft/VisualStudio/SxS/VS7 "${vsver}" \
	; then
		regquery_vsroot_result=${regquery_result}
		return 0
	fi
	return 1
}

locate_vswhere_exe() {
	# Since Visual Studio 2019 there is the standalone "Visual Studio Installer"
	# package providing vswhere.exe, which does register itself to the registry.
	local vswhere_exe
	if regquery HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/VisualStudio/Setup SharedInstallationPath \
	&& vswhere_exe=$(dirname "$(cygpath -u "${regquery_result}")")/Installer/vswhere.exe \
	&& [[ -x ${vswhere_exe} ]] \
	; then
		locate_vswhere_exe_result=${vswhere_exe}
		return 0
	fi
	#
	# https://devblogs.microsoft.com/setup/vswhere-is-now-installed-with-visual-studio-2017/
	#
	local folderIDs=(
		38 # ProgramFiles(x86)
		42 # ProgramFiles
	)
	local folderID
	for folderID in ${folderIDs[*]}
	do
		vswhere_exe="$(cygpath -F ${folderID})/Microsoft Visual Studio/Installer/vswhere.exe"
		[[ -x ${vswhere_exe} ]] || continue
		locate_vswhere_exe_result=${vswhere_exe}
		return 0
	done
	locate_vswhere_exe_result=
	return 1
}

vswhere() {
	# initial vswhere() does set up location of vswhere.exe
	if locate_vswhere_exe; then
		# redefine vswhere() to execute vswhere.exe
		eval "vswhere() {
			vswhere_result=
			vswhere_result=\$(\"${locate_vswhere_exe_result}\" \"\$@\" | dos2unix)
			return \$?
		}"
	else
		# missing vswhere.exe, redefine vswhere() as noop
		vswhere() {
			vswhere_result=
			return 1
		}
	fi
	# re-execute vswhere() to return results
	vswhere "$@"
	return $?
}

vswhere_installationPath() {
	local vsver=$(get-vsver "${1}")
	vswhere_installationPath_result=
	vswhere -nologo \
		-version "[${vsver},${vsver}.65535]" \
		-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
		-latest \
		-format text \
		-property installationPath \
		|| return 1
	[[ ${vswhere_result} == 'installationPath: '* ]] || return 1
	vswhere_installationPath_result=${vswhere_result#installationPath: }
	return 0
}

query-novcvars-once() {
	[[ -z ${novcPATH-}${novcINCLUDE-}${novcLIB-}${novcLIBPATH-} ]] || return 0

	novcPATH= novcINCLUDE= novcLIB= novcLIBPATH=

	verbose "Querying environment without MSVC ..."
	traceon
	eval $(cmd '@set PATH & set INCLUDE & set LIB' 2>/dev/null |
		sed -nE "s/\\r\$//; s,\\\\,/,g; /^(PATH|INCLUDE|LIB|LIBPATH)=/s/^([^=]*)=(.*)\$/novc\1=$'\2'/p"
	)
	traceoff $?

	if [[ -n ${novcPATH}${novcINCLUDE}${novcLIB}${novcLIBPATH} ]]
	then
		verbose "Querying environment without MSVC done."
		return 0
	fi
	noquiet "Querying environment without MSVC failed."
	return 1
}

query-vcvars() {
	local chost=$(get-chost "$1")
	is-supported-chost "${chost}" || return 1

	query-novcvars-once || die "Cannot get even initial environment."

	local vsver=$(get-vsver "${chost}")
	local vsarch=$(get-vsarch "${chost}")
	local vsroot=
	if vswhere_installationPath "${vsver}"; then
		vsroot=${vswhere_installationPath_result}
	elif regquery_vsroot "${vsver}"; then
		vsroot=${regquery_vsroot_result}
	else
		return 1
	fi

	noquiet "Querying environment for ${chost} ..."

	vcPATH= vcINCLUDE= vcLIB= vcLIBPATH=

	vsroot=$(cygpath -u "$vsroot")
	local vcvarsall
	vcvarsall=${vsroot}/VC/Auxiliary/Build/vcvarsall.bat
	[[ -r ${vcvarsall} ]] ||
	vcvarsall=${vsroot}/VC/vcvarsall.bat
	[[ -r ${vcvarsall} ]] || return 1

	# MSVC 10.0 and above query their VSxxCOMNTOOLS on their own
	local comntoolsvar=
	case ${vsver} in
	7.0) comntoolsvar=VS70COMNTOOLS ;;
	7.1) comntoolsvar=VS71COMNTOOLS ;;
	8.0) comntoolsvar=VS80COMNTOOLS ;;
	9.0) comntoolsvar=VS90COMNTOOLS ;;
	esac
	if [[ -n ${comntoolsvar} ]]
	then
		if regquery 'HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Control/Session Manager/Environment' "${comntoolsvar}"
		then
			eval "export ${comntoolsvar}=\${regquery_result}"
		else
			unset ${comntoolsvar}
		fi
	fi

	traceon
    INCLUDE= LIB= LIBPATH= \
    eval $(cmd "@\"$(cygpath -w "${vcvarsall}")\" ${vsarch} && ( set PATH & set INCLUDE & set LIB )" 2>/dev/null |
      sed -nE "s/\\r\$//; s,\\\\,/,g; /^(PATH|INCLUDE|LIB|LIBPATH)=/s/^([^=]*)=(.*)\$/vc\1=$'\2'/p"
    )
	traceoff $?
    vcPATH=${vcPATH%${novcPATH}};          vcPATH=${vcPATH%%;}
    vcINCLUDE=${vcINCLUDE%${novcINCLUDE}}; vcINCLUDE=${vcINCLUDE%%;}
    vcLIB=${vcLIB%${novcLIB}};             vcLIB=${vcLIB%%;}
    vcLIBPATH=${vcLIBPATH%${novcLIBPATH}}; vcLIBPATH=${vcLIBPATH%%;}

    if [[ "::${vcPATH}::${vcINCLUDE}::${vcLIB}::${vcLIBPATH}::" == *::::* ]]
	then
		verbose "Querying environment for ${chost} failed."
		return 1
	fi
	verbose "Querying environment for ${chost} done."
	return 0
}

# </functions copied from parity-setup>

cd "${topdir:=.}" || exit 1

setups=()

vschosts=(
	{i686,x86_64}-msvc{16,15,14.0,12.0,11.0,10.0,9.0,8.0}-winnt
)

for vschost in ${vschosts[*]}
do
  query-vcvars ${vschost} || continue

  vschostmingw32=${vschost%-winnt}-mingw32
  vsarch=$(get-vsarch ${vschost})
  vscrt=$(get-vscrt ${vschost})
  vsver=$(get-vsver ${vschost})

  if [[ "::${vcPATH}::${vcINCLUDE}::${vcLIB}::${vcLIBPATH}::" != *::::* ]]
  then
    if ${doSetup}
    then
  {
	vcPATH=$(cygpath -up "${vcPATH}")
	vcPATH=${vcPATH//:${windir}:/:}
	vcPATH=${vcPATH//:${sysdir}:/:}
    echo "PATH=\"${vcPATH}:\${PATH}:${windir}:${sysdir}\" export PATH;"
    echo "INCLUDE=\"${vcINCLUDE}\${INCLUDE:+;}\${INCLUDE}\" export INCLUDE;"
    echo "LIB=\"${vcLIB}\${LIB:+;}\${LIB}\" export LIB;"
    echo "LIBPATH=\"${vcLIBPATH}\${LIBPATH:+;}\${LIBPATH}\" export LIBPATH;"
  } > "${topdir}/${vschostmingw32}.sh"
    fi
    type -P ${vschost}-gcc >/dev/null && type -P ${vschost}-g++ >/dev/null &&
    setups+=( "( ${vschost}        ''                               '--build=${vschost} --host=${vschost}        GCJ=no GOC=no F77=no FC=no' )" )
    setups+=( "( ${vschostmingw32} '${topdir}/${vschostmingw32}.sh' '                   --host=${vschostmingw32} GCJ=no GOC=no F77=no FC=no CC=cl CXX=cl OBJDUMP=no NM=no CFLAGS= CXXFLAGS=' )" )
  fi
done

x86-cygwin() { false; }
x64-cygwin() { false; }
x86-mingw() { false; }
x64-mingw() { false; }

type -P     i686-pc-cygwin-gcc >/dev/null && type -P     i686-pc-cygwin-g++ >/dev/null && x86-cygwin() { printf "${1+%s}" "$@" ; }
type -P   x86_64-pc-cygwin-gcc >/dev/null && type -P   x86_64-pc-cygwin-g++ >/dev/null && x64-cygwin() { printf "${1+%s}" "$@" ; }
type -P   i686-w64-mingw32-gcc >/dev/null && type -P   i686-w64-mingw32-g++ >/dev/null && x86-mingw()  { printf "${1+%s}" "$@" ; }
type -P x86_64-w64-mingw32-gcc >/dev/null && type -P x86_64-w64-mingw32-g++ >/dev/null && x64-mingw()  { printf "${1+%s}" "$@" ; }

setups=(
  "$(x86-cygwin  "( x86-cygwin '' '--host=i686-pc-cygwin'     )")"
  "$(x64-cygwin  "( x64-cygwin '' '--host=x86_64-pc-cygwin'   )")"
  "$(x86-mingw   "( x86-mingw  '' '--host=i686-w64-mingw32'   )")"
  "$(x64-mingw   "( x64-mingw  '' '--host=x86_64-w64-mingw32' )")"
  "${setups[@]}"
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
