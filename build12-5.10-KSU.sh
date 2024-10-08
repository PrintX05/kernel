set +x

export KBUILD_BUILD_USER="秋乐"
export KBUILD_BUILD_HOST="PrintX"
export WORK_DIR="$(pwd)"

echo "Free space:"
df -h

add_ksu() {
    ROOT=$(pwd)
    if test -d "$ROOT/common/drivers"; then
        DRIVER_DIR="$ROOT/common/drivers"
    elif test -d "$ROOT/drivers"; then
        DRIVER_DIR="$ROOT/drivers"
    else
        exit 127
    fi
    test -d "KernelSU" || git clone https://github.com/tiann/KernelSU
    cd "KernelSU"
    git stash
    test "${1}" == 'gki' || git checkout v0.9.5
    cd "$DRIVER_DIR"
    if test -d "$ROOT/common/drivers"; then
        ln -sf "../../KernelSU/kernel" "kernelsu"
    elif test -d "$ROOT/drivers"; then
        ln -sf "../KernelSU/kernel" "kernelsu"
    fi
    cd "$ROOT"

    DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
    DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
    grep -q "kernelsu" "$DRIVER_MAKEFILE" || printf "obj-\$(CONFIG_KSU) += kernelsu/\n" >>"$DRIVER_MAKEFILE"
    grep -q "kernelsu" "$DRIVER_KCONFIG" || sed -i "/endmenu/i\\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_KCONFIG"
}

change() {
    ls
    ls -a
    test -d common/drivers && cp -rf $WORK_DIR/patch/printx common/drivers/
    test -d drivers && cp -rf $WORK_DIR/patch/printx drivers/
    test -f common/drivers/Makefile && sed -i '1i obj-y += rootit/' common/drivers/Makefile
    test -d common/drivers && cp -rf $WORK_DIR/patch/printx/rootit common/drivers/rootit
    cat common/drivers/rootit/rootit.c
    cat common/drivers/rootit/Makefile
    cat common/drivers/Makefile
    echo "FFFF"
    test -f common/drivers/Kconfig && sed -i "/endmenu/i\\source \"drivers/printx/Kconfig\"" common/drivers/Kconfig
    test -f drivers/Kconfig && sed -i "/endmenu/i\\source \"drivers/printx/Kconfig\"" drivers/Kconfig
    test -f common/scripts/setlocalversion && echo '' >common/scripts/setlocalversion
    test -f scripts/setlocalversion && echo '' >scripts/setlocalversion
    test -f common/Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-R-20240813/g" common/Makefile
    test -f Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-R-20240813/g" Makefile
    test -f build/_setup_env.sh && sed -i "s/function check_defconfig() {/function check_defconfig() {\n    return 0/g" build/_setup_env.sh
    
    
}

cd $WORK_DIR

sudo apt-get install repo -y

build() {
    kernel="$2"
    android="$1"
    cd $WORK_DIR
    mkdir $kernel && cd $kernel
    repo init --depth=1 --u https://android.googlesource.com/kernel/manifest -b common-android${android}-${kernel}-lts --repo-rev=v2.16
    repo --version
    repo --trace sync -c -j$(($(getconf _NPROCESSORS_ONLN) * 2)) --no-tags

    add_ksu gki    
    change

    if [ -e build/build.sh ]; then
        LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
    else
        tools/bazel run --disk_cache=/home/runner/.cache/bazel --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir=dist
    fi

    cd $WORK_DIR

    mkdir -p out/$kernel/config
    rm -rf ${kernel}/out/android${android}-${kernel}/common/.thinlto-cache
    rm -rf ${kernel}/out/android${android}-${kernel}/common/*vmlinux*
    rm -rf ${kernel}/out/android${android}-${kernel}/common/*tmp* 
    ls ${kernel}/out/
    echo "加载内核"
    mv -f ${kernel}/out/* out/        
    rm -rf ${kernel}

}

build 12 5.10
exit
