#!/bin/bash
#
# Compile script for QuicksilveR kernel
# Copyright (C) 2020-2021 Adithya R.

# Setup getopt.
long_opts="regen,clean,homedir:,tcdir:"
getopt_cmd=$(getopt -o rch:t: --long "$long_opts" \
            -n $(basename $0) -- "$@") || \
            { echo -e "\nError: Getopt failed. Extra args\n"; exit 1;}

eval set -- "$getopt_cmd"

while true; do
    case "$1" in
        -r|--regen|r|regen) FLAG_REGEN_DEFCONFIG=y;;
        -c|--clean|c|clean) FLAG_CLEAN_BUILD=y;;
        -h|--homedir|h|homedir) HOME_DIR="$2"; shift;;
        -t|--tcdir|t|tcdir) TC_DIR="$2"; shift;;
        --) shift; break;;
    esac
    shift
done

# Setup HOME dir
if [ $HOME_DIR ]; then
    HOME_DIR=$HOME_DIR
else
    HOME_DIR=$HOME
fi
echo -e "HOME directory is at $HOME_DIR\n"

# Setup Toolchain dir
if [ $TC_DIR ]; then
    TC_DIR="$HOME_DIR/$TC_DIR"
else
    TC_DIR="$HOME_DIR/tc"
fi
echo -e "Toolchain directory is at $TC_DIR\n"

SECONDS=0 # builtin bash timer
ZIPNAME="nethunter-spacewar-$(date '+%Y%m%d-%H%M').zip"
if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
        ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi
CLANG_DIR="$TC_DIR/linux-x86/clang-r498229b"
AK3_DIR="$HOME/AnyKernel3"
DEFCONFIG="spacewar_defconfig"

MAKE_PARAMS="O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=$TC_DIR/bin/llvm-"

export PATH="$CLANG_DIR/bin:$PATH"

# Regenerate defconfig, if requested so
if [ "$FLAG_REGEN_DEFCONFIG" = 'y' ]; then
	make $MAKE_PARAMS $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

# Prep for a clean build, if requested so
if [ "$FLAG_CLEAN_BUILD" = 'y' ]; then
	echo -e "\nCleaning output folder..."
	rm -rf out
fi

mkdir -p out
make $MAKE_PARAMS $DEFCONFIG

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $MAKE_PARAMS || exit $?
make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

kernel="out/arch/arm64/boot/Image"
dts_dir="out/arch/arm64/boot/dts/vendor/qcom"

if [ -f "$kernel" ] && [ -d "$dts_dir" ]; then
	echo -e "\nKernel compiled succesfully! Zipping up...\n"
	if [ -d "$AK3_DIR" ]; then
		cp -r $AK3_DIR AnyKernel3
		git checkout spacewar &> /dev/null
	elif ! git clone https://github.com/kimocoder/AnyKernel3 -b spacewar; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
	cp $kernel AnyKernel3
	cat $dts_dir/*.dtb > AnyKernel3/dtb
	python2 scripts/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dts_dir/*.dtbo
	mkdir AnyKernel3/modules/vendor/lib/modules/5.4.249-NetHunter/
	#cp $(find $OUT_DIR/modules/lib/modules/5.4* -name '*.ko') AnyKernel3/modules/vendor/lib/modules/
	cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules/5.4.249-NetHunter/
	cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/5.4.249-NetHunter/modules.load
	cp out/modules/lib/modules/5.4.*/modules.* AnyKernel3/modules/vendor/lib/modules/5.4.249-NetHunter/
	sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' AnyKernel3/modules/vendor/lib/modules/5.4.249-NetHunter/modules.dep
	#sed -i 's/.*\///g' AnyKernel3/modules/vendor/lib/modules/5.4.*/modules.load
	rm -rf out/arch/arm64/boot out/modules
	cd AnyKernel3
	zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $ZIPNAME"
	#curl -F "file=@${ZIPNAME}" https://oshi.at
else
	echo -e "\nCompilation failed!"
	exit 1
fi
