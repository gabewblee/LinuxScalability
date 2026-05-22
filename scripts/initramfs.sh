#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/platform.sh"

arch="$(get_target_arch)"
build="$(get_build_dir "$root")"
staging="$build/staging"
img="$(get_initrd_path "$root")"
bin="$build/OS_Eval"

if [ ! -x "$bin" ]; then
    echo "[initramfs] ERROR: OS_Eval binary not found at ${bin}"
    echo "[initramfs] Run 'make lebench' first."
    exit 1
fi

rm -rf "$staging"
mkdir -p "$staging"/{proc,sys,dev,tmp,bench/TEST_DIR}

cp "$bin" "$staging/OS_Eval"
chmod +x "$staging/OS_Eval"

cat > "$build/init.c" << 'INIT_EOF'
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <unistd.h>

static void write_to_file(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        (void)write(fd, text, strlen(text));
        close(fd);
    }
}

static int prefixed(const char *s, const char *prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

static int suffixed(const char *s, const char *suffix) {
    size_t slen = strlen(s); size_t suflen = strlen(suffix);
    return slen >= suflen && strcmp(s + slen - suflen, suffix) == 0;
}

static void print_file_contents(const char *path) {
    char buf[4096];
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return;
    }

    for (;;) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n <= 0) {
            break;
        }
        (void)write(STDOUT_FILENO, buf, (size_t)n);
    }

    close(fd);
}

static void print_csv_outputs(void) {
    DIR *dir = opendir("/bench");
    if (!dir) {
        perror("[init] opendir /bench");
        return;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (prefixed(entry->d_name, "output.") && suffixed(entry->d_name, ".csv")) {
            char path[512];
            snprintf(path, sizeof(path), "/bench/%s", entry->d_name);
            print_file_contents(path);
        }
    }

    closedir(dir);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    mkdir("/proc", 0555);
    mkdir("/sys", 0555);
    mkdir("/dev", 0755);
    mkdir("/bench", 0755);
    mkdir("/bench/TEST_DIR", 0755);

    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    write_to_file("/proc/sys/kernel/sysrq", "1\n");

    struct utsname uts;
    if (uname(&uts) != 0)
        strcpy(uts.release, "unknown");

    setenv("LEBENCH_DIR", "/bench/", 1);
    printf("[init] Kernel: %s\n", uts.release);
    printf("[init] Starting LEBench...\n");

    pid_t pid = fork();
    if (pid == 0) {
        chdir("/bench");
        execl("/OS_Eval", "OS_Eval", "0", uts.release, (char *)NULL);
        perror("[init] exec /OS_Eval");
        _exit(127);
    }

    int status = 0;
    if (pid < 0) {
        perror("[init] fork");
    } else {
        waitpid(pid, &status, 0);
        printf("[init] LEBench exit status: %d\n", status);
    }

    printf("=== LEBENCH_CSV_START ===\n");
    print_csv_outputs();
    printf("=== LEBENCH_CSV_END ===\n");

    printf("[init] Benchmark complete. Powering off.\n");
    sync();
    reboot(RB_POWER_OFF);
    write_to_file("/proc/sysrq-trigger", "o\n");
    for (;;)
        sleep(1);
}
INIT_EOF

echo "[initramfs] Compiling Linux /init for ${arch}..."
compiler="$(get_compiler)"
src="$(printf '%q' "$build/init.c")"
output="$(printf '%q' "$staging/init")"
eval "$compiler -static -Os $src -o $output"
chmod +x "$staging/init"

echo "[initramfs] Packing ${arch} initramfs..."
(
    cd "$staging"
    find . | cpio -o -H newc --quiet
) | gzip -n -9 > "$img"

sz=$(du -sh "$img" | cut -f1)
echo "[initramfs] Created: ${img}  (${sz})"
