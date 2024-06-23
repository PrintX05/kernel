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
    test -d common/drivers && cp -rf $WORK_DIR/patch/lingcha common/drivers/
    test -d drivers && cp -rf $WORK_DIR/patch/lingcha drivers/
    test -f common/drivers/Kconfig && sed -i "/endmenu/i\\source \"drivers/lingcha/Kconfig\"" common/drivers/Kconfig
    test -f drivers/Kconfig && sed -i "/endmenu/i\\source \"drivers/lingcha/Kconfig\"" drivers/Kconfig
    test -f common/scripts/setlocalversion && echo '' >common/scripts/setlocalversion
    test -f scripts/setlocalversion && echo '' >scripts/setlocalversion
    test -f common/Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-20240623/g" common/Makefile
    test -f Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-20240623/g" Makefile
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

    test -f ${kernel}/out/.config && cp -rf ${kernel}/out/.config out/${kernel}/config/

    test -d ${kernel}/out/android${android}-${kernel}/dist && cp -rf ${kernel}/out/android${android}-${kernel}/dist/* out/${kernel}/
    test -d ${kernel}/dist && cp -rf ${kernel}/dist/* out/${kernel}/

    rm -rf ${kernel}
}

build 12 5.10
build 13 5.15

exit
