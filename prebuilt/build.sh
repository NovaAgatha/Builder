#! /usr/bin/env bash

#
# Rissu Kernel Project
# A special build script for Rissu's kernel
#

# << If unset, you can override if u want
[ -z $IS_CI ] && IS_CI=false
[ -z $DO_CLEAN ] && DO_CLEAN=false
[ -z $LTO ] && LTO=none
[ -z $DEFAULT_KSU_REPO ] && DEFAULT_KSU_REPO="https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh"
[ -z $DEFAULT_KSU_BRANCH ] && DEFAULT_KSU_BRANCH="main"
[ -z $DEFAULT_AK3_REPO ] && DEFAULT_AK3_REPO="https://github.com/rsuntk/AnyKernel3.git"
[ -z $DEVICE ] && DEVICE="Unknown"
[ -z $IMAGE ] && IMAGE="$(pwd)/out/arch/arm64/boot/Image"

# special rissu's path. linked to his toolchains
if [ -d /rsuntk ]; then
	export CROSS_COMPILE=/rsuntk/toolchains/google/bin/aarch64-linux-android-
	export PATH=/rsuntk/toolchains/clang-12/bin:$PATH
fi
# color variable
N='\033[0m'
R='\033[1;31m'
G='\033[1;32m'

# start of default args
DEFAULT_ARGS="
CONFIG_SECTION_MISMATCH_WARN_ONLY=y
ARCH=arm64
"
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export PLATFORM_VERSION=13
export ANDROID_MAJOR_VERSION=t
# end of default args

pr_invalid() {
	echo -e "[-] Invalid args: $@"
	exit
}
pr_err() {
	echo -e "[-] $@"
	exit
}
pr_info() {
	echo -e "[+] $@"
}
pr_step() {
	echo "[$1 / $2] $3"
 	sleep 2
}
strip() { # fmt: strip <module>
	llvm-strip $@ --strip-unneeded
}
setconfig() { # fmt: setconfig enable/disable <NAME>
	[ -e $(pwd)/.config ] && config_file="$(pwd)/.config" || config_file="$(pwd)/out/.config"
	if [ -d $(pwd)/scripts ]; then
		[ "$1" = "enable" ] && pr_info "Enabling CONFIG_`echo $2` .." || pr_info "Disabling CONFIG_`echo $2`"
		chmod +x ./scripts/config && ./scripts/config --file `echo $config_file` --`echo $1` CONFIG_`echo $2`
	else
		echo "! Folder scripts not found!"
		exit
	fi
}
clone_ak3() {
	[ ! -d $(pwd)/AnyKernel3 ] && git clone $DEFAULT_AK3_REPO --depth=1
	rm -rf AnyKernel3/.git
}
gen_getutsrelease() {
# generate simple c file
if [ ! -e utsrelease.c ]; then
echo "/* Generated file by `basename $0` */
#include <stdio.h>
#ifdef __OUT__
#include \"out/include/generated/utsrelease.h\"
#else
#include \"include/generated/utsrelease.h\"
#endif

char utsrelease[] = UTS_RELEASE;

int main() {
	printf(\"%s\n\", utsrelease);
	return 0;
}" > utsrelease.c
fi
}
usage() {
	echo -e "Usage: bash `basename $0` <build_target> <-j | --jobs> <(job_count)> <defconfig>"
	printf "\tbuild_target: dirty, kernel, defconfig, clean\n"
	printf "\t-j or --jobs: <int>\n"
	echo ""
	printf "NOTE: Run: \texport CROSS_COMPILE=\"<PATH_TO_ANDROID_CC>\"\n"
	printf "\t\texport PATH=\"<PATH_TO_LLVM>\"\n"
	printf "before running this script!\n"
	printf "\n"
	printf "Misc:\n"
	printf "\tPOST_BUILD_CLEAN: Clean post build: (opt:boolean)\n"
	printf "\tLTO: Use Link-time Optimization; options: (opt: none, thin, full)\n"
	printf "\tLLVM: Use all llvm toolchains to build: (opt: 1)\n"
	printf "\tLLVM_IAS: Use llvm integrated assembler: (opt: 1)\n"
	exit;
}

pr_post_build() {
	echo ""
	[ "$@" = "failed" ] && echo -e "${R}#### Failed to build some targets ($1) ####${N}" ||	echo -e "${G}#### Build completed at `date` ####${N}"
	echo ""
	echo "======================================================="
	[ -e $IMAGE ] && strings $IMAGE | grep "Linux version" || exit
	echo "======================================================="
}

# if first arg starts with "clean"
if [[ "$1" = "clean" ]]; then
	[ $# -gt 1 ] && pr_err "Excess argument, only need one argument."
	pr_info "Cleaning dirs"
	if [ -d $(pwd)/out ]; then
		rm -rf out
	elif [ -f $(pwd)/.config ]; then
		make clean
		make mrproper
	else
		pr_err "No need clean."
	fi
	pr_err "All clean."
elif [[ "$1" = "dirty" ]]; then
	if [ $# -gt 3 ]; then
		pr_err "Excess argument, only need three argument."
	fi	
	pr_info "Starting dirty build"
	FIRST_JOB="$2"
	JOB_COUNT="$3"
	if [ "$FIRST_JOB" = "-j" ] || [ "$FIRST_JOB" = "--jobs" ]; then
		if [ ! -z $JOB_COUNT ]; then
			ALLOC_JOB=$JOB_COUNT
		else
			pr_invalid $3
		fi
	else
		pr_invalid $2
	fi
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS`
	[ ! -e $IMAGE ] && pr_post_build "failed" || pr_post_build "completed"
elif [[ "$1" = "ak3" ]]; then
	if [ $# -gt 1 ]; then
		pr_err "Excess argument, only need one argument."
	fi
	clone_ak3;
else
	[ $# != 4 ] && usage;
fi

[ "$KERNELSU" = "true" ] && curl -LSs $DEFAULT_KSU_REPO | bash -s `echo $DEFAULT_KSU_BRANCH` || pr_info "KernelSU is disabled. Add 'KERNELSU=true' or 'export KERNELSU=true' to enable"

BUILD_TARGET="$1"
FIRST_JOB="$2"
JOB_COUNT="$3"
DEFCONFIG="$4"

if [ "$BUILD_TARGET" = "kernel" ]; then
	BUILD="kernel"
elif [ "$BUILD_TARGET" = "defconfig" ]; then
	BUILD="defconfig"
else
	pr_invalid $1
fi

if [ "$FIRST_JOB" = "-j" ] || [ "$FIRST_JOB" = "--jobs" ]; then
	if [ ! -z $JOB_COUNT ]; then
		ALLOC_JOB=$JOB_COUNT
	else
		pr_invalid $3
	fi
else
	pr_invalid $2
fi

if [ ! -z "$DEFCONFIG" ]; then
	BUILD_DEFCONFIG="$DEFCONFIG"
else
	pr_invalid $4
fi

if [ "$LLVM" = "1" ]; then
	LLVM_="true"
	DEFAULT_ARGS+=" LLVM=1"
	export LLVM=1
	if [ "$LLVM_IAS" = "1" ]; then
		LLVM_IAS_="true"
		DEFAULT_ARGS+=" LLVM_IAS=1"
		export LLVM_IAS=1
	fi
else
	LLVM_="false"
	if [ "$LLVM_IAS" != "1" ]; then
		LLVM_IAS_="false"
	fi
fi

pr_sum() {
	[ -z $KBUILD_BUILD_USER ] && KBUILD_BUILD_USER="`whoami`"
	[ -z $KBUILD_BUILD_HOST ] && KBUILD_BUILD_HOST="`uname -n`"
 	pr_step "1" "3" "Starting build with Rissu's build script ..."
	echo ""
	echo "======================================================="
	echo -e "Host Arch: `uname -m`"
	echo -e "Host Kernel: `uname -r`"
	echo -e "Host GNUMake: `make -v | grep -e "GNU Make"`"
	echo -e "Kernel builder user: $KBUILD_BUILD_USER"
	echo -e "Kernel builder host: $KBUILD_BUILD_HOST"
	printf "\n"
	echo -e "Linux version: `make kernelversion`"
	echo -e "Build date: `date`"
	echo -e "Build target: `echo $BUILD`"
	echo -e "Build arch: $ARCH"
	echo -e "Target Defconfig: $BUILD_DEFCONFIG"
	echo -e "Allocated core(s): $ALLOC_JOB"
	printf "\n"
	echo -e "LTO: $LTO"
	echo "======================================================="
}

post_build_clean() {
	if [ -e $AK3 ]; then
		rm -rf $AK3/Image
		rm -rf $AK3/modules/vendor/lib/modules/*.ko
		#sed -i "s/do\.modules=.*/do.modules=0/" "$(pwd)/AnyKernel3/anykernel.sh"
		echo "stub" > $AK3/modules/vendor/lib/modules/stub
	fi
	rm getutsrel
	rm utsrelease.c
	# clean out folder
	rm -rf out
	make clean
	make mrproper
}

post_build() {
	if [ -d $(pwd)/.git ]; then
		GITSHA=$(git rev-parse --short HEAD)
	else
		GITSHA="localbuild"
	fi
	
	AK3="$(pwd)/AnyKernel3"
	DATE=$(date +'%Y%m%d%H%M%S')
	ZIP_FMT="AnyKernel3-`echo $DEVICE`_$GITSHA-$DATE"
	
	clone_ak3;
	if [ -d $AK3 ]; then
		echo "- Creating AnyKernel3"
		gen_getutsrelease;
		[ -d $(pwd)/out ] && gcc -D__OUT__ -CC utsrelease.c -o getutsrel || gcc -CC utsrelease.c -o getutsrel
		UTSRELEASE=$(./getutsrel)
		sed -i "s/kernel\.string=.*/kernel.string=$UTSRELEASE/" "$AK3/anykernel.sh"
		sed -i "s/BLOCK=.*/BLOCK=\/dev\/block\/platform\/12100000.dwmmc0\/by-name\/boot;/" "$AK3/anykernel.sh"
		cp $IMAGE $AK3
		cd $AK3
		zip -r9 ../`echo $ZIP_FMT`.zip *
		# CI will clean itself post-build, so we don't need to clean
		# Also avoiding small AnyKernel3 zip issue!
		if [ "$IS_CI" != "true" ] && [ "$DO_CLEAN" = "true" ]; then
			pr_info "Host is not Automated CI, cleaning dirs"
			post_build_clean;
		fi
		cd ..
		pr_step "3" "3" "Build script ended."
	fi
}

handle_lto() {
	if [[ "$LTO" = "thin" ]]; then
		pr_info "LTO: Thin"
		setconfig disable LTO_NONE
		setconfig enable LTO
		setconfig enable THINLTO
		setconfig enable LTO_CLANG
		setconfig enable ARCH_SUPPORTS_LTO_CLANG
		setconfig enable ARCH_SUPPORTS_THINLTO
	elif [[ "$LTO" = "full" ]]; then
		pr_info "LTO: Full"
		setconfig disable LTO_NONE
		setconfig enable LTO
		setconfig disable THINLTO
		setconfig enable LTO_CLANG
		setconfig enable ARCH_SUPPORTS_LTO_CLANG
		setconfig enable ARCH_SUPPORTS_THINLTO
	fi
}
# call summary
pr_sum
if [ "$BUILD" = "kernel" ]; then
	pr_step "2" "3" "Building targets ($BUILD) with lto=$LTO"
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS` `echo $BUILD_DEFCONFIG`
	[ "$KERNELSU" = "true" ] && setconfig enable KSU
	[ "$LTO" != "none" ] && handle_lto || pr_info "LTO not set";
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS`
	if [ -e $IMAGE ]; then
		pr_post_build "completed"
		post_build
	else
		pr_post_build "failed"
	fi
elif [ "$BUILD" = "defconfig" ]; then
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS` `echo $BUILD_DEFCONFIG`
fi

