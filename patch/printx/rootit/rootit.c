#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/syscalls.h>
#include <linux/namei.h>
#include <linux/kallsyms.h>
#include <linux/slab.h>
#include <linux/file.h>

#define TARGET_CMD "ls"
#define TARGET_ARG "xxx"
#define OUTPUT_PATH "/data/xx"
#define OUTPUT_CONTENT "666\n"

// 保存原始的 sys_execve
static asmlinkage long (*original_execve)(const char __user *filename,
                                          const char __user *const __user *argv,
                                          const char __user *const __user *envp);

static asmlinkage long hooked_execve(const char __user *filename,
                                     const char __user *const __user *argv,
                                     const char __user *const __user *envp)
{
    char fname[256];
    char arg[256];
    struct file *file;
    mm_segment_t old_fs;

    // Get the filename
    if (strncpy_from_user(fname, filename, sizeof(fname)) < 0) {
        return -EFAULT;
    }

    // Check if the command is "ls"
    if (strcmp(fname, "/bin/" TARGET_CMD) == 0 || strcmp(fname, "/system/bin/" TARGET_CMD) == 0) {
        // Get the first argument
        if (argv && argv[1] && strncpy_from_user(arg, argv[1], sizeof(arg)) > 0) {
            // Check if the argument is "xxx"
            if (strcmp(arg, TARGET_ARG) == 0) {
                // Write "666" to /data/xx
                file = filp_open(OUTPUT_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0644);
                if (!IS_ERR(file)) {
                    old_fs = get_fs();
                    set_fs(KERNEL_DS);
                    kernel_write(file, OUTPUT_CONTENT, strlen(OUTPUT_CONTENT), &file->f_pos);
                    set_fs(old_fs);
                    filp_close(file, NULL);
                }
            }
        }
    }

    // Call the original execve
    return original_execve(filename, argv, envp);
}

// 禁用写保护
static void disable_wp(unsigned long *addr)
{
    unsigned long value;
    asm volatile("mrs %0, sctlr_el1" : "=r"(value));
    value &= ~0x1;  // 清除写保护位
    asm volatile("msr sctlr_el1, %0" : : "r"(value));
    *addr = (unsigned long)hooked_execve;
}

// 启用写保护
static void enable_wp(unsigned long *addr)
{
    unsigned long value;
    asm volatile("mrs %0, sctlr_el1" : "=r"(value));
    value |= 0x1;  // 设置写保护位
    asm volatile("msr sctlr_el1, %0" : : "r"(value));
    *addr = (unsigned long)original_execve;
}

static int __init lkm_init(void)
{
    unsigned long *sys_call_table = (unsigned long *)kallsyms_lookup_name("sys_call_table");
    if (!sys_call_table) {
        printk(KERN_ERR "Cannot find sys_call_table\n");
        return -1;
    }

    // Save the original execve
    original_execve = (void *)sys_call_table[__NR_execve];

    // Disable write protection on the page
    disable_wp(&sys_call_table[__NR_execve]);

    // Hook execve
    sys_call_table[__NR_execve] = (unsigned long)hooked_execve;

    // Enable write protection on the page
    enable_wp(&sys_call_table[__NR_execve]);

    printk(KERN_INFO "LKM loaded\n");
    return 0;
}

static void __exit lkm_exit(void)
{
    unsigned long *sys_call_table = (unsigned long *)kallsyms_lookup_name("sys_call_table");
    if (!sys_call_table) {
        printk(KERN_ERR "Cannot find sys_call_table\n");
        return;
    }

    // Disable write protection on the page
    disable_wp(&sys_call_table[__NR_execve]);

    // Restore the original execve
    sys_call_table[__NR_execve] = (unsigned long)original_execve;

    // Enable write protection on the page
    enable_wp(&sys_call_table[__NR_execve]);

    printk(KERN_INFO "LKM unloaded\n");
}

module_init(lkm_init);
module_exit(lkm_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("PrintX");
MODULE_DESCRIPTION("PrintX LKM");