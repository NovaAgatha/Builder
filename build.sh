#
# build script for X01BD/X00TD
#
# this script doesn't handle required dependencies, so
# install it first before using this script.
#

SECONDS=0
ZIPNAME="rsuntk_Ratibor-$(date '+%Y%m%d-%H%M').zip"

# Handle: cp $(pwd)/rsuntk-X01BD_defconfig arch/arm64/configs
[ $USE_PERSONAL_DEFCONFIG = "true" ] && DEFCONFIG="rsuntk-X01BD_defconfig" || DEFCONFIG="asus/X01BD_defconfig"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

if ! [ -d "$HOME/zyc-clang" ]; then
echo "- Toolchains not found! Fetching..."
aria2c https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/0998f421320ae02fddabec8a78b91bf7620159f6/clang-r563880.tar.gz
mkdir ~/clang
tar -xf *.tar.gz -C ~/clang
[ ! -d "$HOME/androidcc-4.9" ] && curl -LSs "https://raw.githubusercontent.com/rsuntk/toolchains/refs/heads/README/clone.sh" | bash -s androidcc-4.9
[ ! -d "$HOME/arm-gnu" ] && curl -LSs "https://raw.githubusercontent.com/rsuntk/toolchains/refs/heads/README/clone.sh" | bash -s arm-gnu
mv androidcc-4.9 ~/androidcc-4.9 && mv arm-gnu ~/arm-gnu
rm -rf *.tar.gz
fi

USER="rsuntk"
HOSTNAME="nobody"

export PATH="$HOME/clang/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/clang/lib"
export BUILD_USERNAME=$USER
export BUILD_HOSTNAME=$HOSTNAME
export KBUILD_BUILD_USER=$USER
export KBUILD_BUILD_HOST=$HOSTNAME
export CROSS_COMPILE="$HOME/androidcc-4.9/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32="$HOME/arm-gnu/bin/arm-linux-gnueabi-"
export CROSS_COMPILE_COMPAT=$CROSS_COMPILE_ARM32
export LLVM=1
export LLVM_IAS=1

BUILD_FLAGS="
O=out
ARCH=arm64
CC=clang
LD=ld.lld
AR=llvm-ar
AS=llvm-as
NM=llvm-nm
OBJCOPY=llvm-objcopy
OBJDUMP=llvm-objdump
STRIP=llvm-strip
CLANG_TRIPLE=aarch64-linux-gnu-
"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
mkdir out
make $(echo $BUILD_FLAGS) $DEFCONFIG
cp out/.config arch/arm64/configs/$DEFCONFIG
rm -rf out
echo -e "\nRegened defconfig succesfully!"
exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
echo -e "\nClean build!"
rm -rf out
fi

mkdir -p out
make $(echo $BUILD_FLAGS) $DEFCONFIG -j$(nproc --all)

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $(echo $BUILD_FLAGS) Image.gz-dtb

if [ -f "out/arch/arm64/boot/Image.gz-dtb" ]; then
echo -e "\nKernel compiled succesfully! Zipping up...\n"
git clone -q https://github.com/rsuntk/AnyKernel3 --single-branch
cp out/arch/arm64/boot/Image.gz-dtb AnyKernel3
cd AnyKernel3
# TODO: Add X00TD support
sed -i "s/BLOCK=.*/BLOCK=\/dev\/block\/bootdevice\/by-name\/boot;/" "anykernel.sh"
zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder
cd ..
if [ "$DO_CLEAN" = "true" ]; then 
rm -rf AnyKernel3 out/arch/arm64/boot
fi
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
exit 0
else
echo -e "\nCompilation failed!"
exit 1
fi
