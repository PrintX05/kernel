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
    
    echo "[+] Export all symbol from abi_gki_aarch64.xml"
          COMMON_ROOT=$GITHUB_WORKSPACE/android-kernel/common
          KSU_ROOT=$GITHUB_WORKSPACE/KernelSU
          ABI_XML=$COMMON_ROOT/android/abi_gki_aarch64.xml
          SYMBOL_LIST=$COMMON_ROOT/android/abi_gki_aarch64
          # python3 $KSU_ROOT/scripts/abi_gki_all.py $ABI_XML > $SYMBOL_LIST
          echo "[+] Add KernelSU symbols"
          cat $KSU_ROOT/kernel/export_symbol.txt | awk '{sub("[ \t]+","");print "  "$0}' >> $SYMBOL_LIST
pip install ast-grep-cli
          sudo apt-get install llvm-15 -y
          ast-grep -U -p '$$$ check_exports($$$) {$$$}' -r '' common/scripts/mod/modpost.c
          ast-grep -U -p 'check_exports($$$);' -r '' common/scripts/mod/modpost.c
          sed -i '/config KSU/,/help/{s/default y/default m/}' common/drivers/kernelsu/Kconfig
          echo "drivers/kernelsu/kernelsu.ko" >> common/android/gki_aarch64_modules

          # bazel build, android14-5.15, android14-6.1 use bazel
          if [ ! -e build/build.sh ]; then
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' build/kernel/*.sh || echo "No unknown symbol scripts found"
            if [ -e common/modules.bzl ]; then
              sed -i 's/_COMMON_GKI_MODULES_LIST = \[/_COMMON_GKI_MODULES_LIST = \[ "drivers\/kernelsu\/kernelsu.ko",/g' common/modules.bzl
            fi
          else
            TARGET_FILE="build/kernel/build.sh"
            if [ ! -e "$TARGET_FILE" ]; then
              TARGET_FILE="build/build.sh"
            fi
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' $TARGET_FILE || echo "No unknown symbol in $TARGET_FILE"
            sed -i 's/if ! diff -u "\${KERNEL_DIR}\/\${MODULES_ORDER}" "\${OUT_DIR}\/modules\.order"; then/if false; then/g' $TARGET_FILE
            sed -i 's@${ROOT_DIR}/build/abi/compare_to_symbol_list@echo@g' $TARGET_FILE
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' build/kernel/*.sh || echo "No unknown symbol scripts found"
          fi
          rm common/android/abi_gki_protected_exports_* || echo "No protected exports!"
          git config --global user.email "3042627767@qq.com"
          git config --global user.name "linshao666"
          cd common/ && git add -A && git commit -a -m "Add KernelSU"
          repo status
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
    test -f common/Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-MOD-20240627/g" common/Makefile
    test -f Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-MOD-20240627/g" Makefile
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
        tools/bazel run --disk_cache=/home/runner/.cache/bazel --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir=dist --verbose_failures
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

build 14 6.1
exitset +x

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
    
    echo "[+] Export all symbol from abi_gki_aarch64.xml"
          COMMON_ROOT=$GITHUB_WORKSPACE/android-kernel/common
          KSU_ROOT=$GITHUB_WORKSPACE/KernelSU
          ABI_XML=$COMMON_ROOT/android/abi_gki_aarch64.xml
          SYMBOL_LIST=$COMMON_ROOT/android/abi_gki_aarch64
          # python3 $KSU_ROOT/scripts/abi_gki_all.py $ABI_XML > $SYMBOL_LIST
          echo "[+] Add KernelSU symbols"
          cat $KSU_ROOT/kernel/export_symbol.txt | awk '{sub("[ \t]+","");print "  "$0}' >> $SYMBOL_LIST
pip install ast-grep-cli
          sudo apt-get install llvm-15 -y
          ast-grep -U -p '$$$ check_exports($$$) {$$$}' -r '' common/scripts/mod/modpost.c
          ast-grep -U -p 'check_exports($$$);' -r '' common/scripts/mod/modpost.c
          sed -i '/config KSU/,/help/{s/default y/default m/}' common/drivers/kernelsu/Kconfig
          echo "drivers/kernelsu/kernelsu.ko" >> common/android/gki_aarch64_modules

          # bazel build, android14-5.15, android14-6.1 use bazel
          if [ ! -e build/build.sh ]; then
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' build/kernel/*.sh || echo "No unknown symbol scripts found"
            if [ -e common/modules.bzl ]; then
              sed -i 's/_COMMON_GKI_MODULES_LIST = \[/_COMMON_GKI_MODULES_LIST = \[ "drivers\/kernelsu\/kernelsu.ko",/g' common/modules.bzl
            fi
          else
            TARGET_FILE="build/kernel/build.sh"
            if [ ! -e "$TARGET_FILE" ]; then
              TARGET_FILE="build/build.sh"
            fi
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' $TARGET_FILE || echo "No unknown symbol in $TARGET_FILE"
            sed -i 's/if ! diff -u "\${KERNEL_DIR}\/\${MODULES_ORDER}" "\${OUT_DIR}\/modules\.order"; then/if false; then/g' $TARGET_FILE
            sed -i 's@${ROOT_DIR}/build/abi/compare_to_symbol_list@echo@g' $TARGET_FILE
            sed -i 's/needs unknown symbol/Dont abort when unknown symbol/g' build/kernel/*.sh || echo "No unknown symbol scripts found"
          fi
          rm common/android/abi_gki_protected_exports_* || echo "No protected exports!"
          git config --global user.email "3042627767@qq.com"
          git config --global user.name "linshao666"
          cd common/ && git add -A && git commit -a -m "Add KernelSU"
          repo status
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
    test -f common/Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-MOD-20240627/g" common/Makefile
    test -f Makefile && sed -i "s/EXTRAVERSION =/EXTRAVERSION = -PrintX-MOD-20240627/g" Makefile
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
        tools/bazel run --disk_cache=/home/runner/.cache/bazel --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --dist_dir=dist --verbose_failures
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

build 14 6.1
exit