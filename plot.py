#!/usr/bin/env python3
import os
import platform
import re
import sys
import glob

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, Normalize
import numpy as np

RESULTS_DIRECTORY_PATH = "results"
PLOTS_DIRECTORY_PATH = "plots"
BASELINE_KERNEL_VERSION = os.environ.get("BASELINE_VERSION", "4.0")
ARCHITECTURE_NAME_ALIASES = {
    "x86_64"     : "amd64",
    "amd64"      : "amd64",
    "aarch64"    : "arm64",
    "arm64"      : "arm64",
    "armv7l"     : "armhf",
    "armhf"      : "armhf",
    "arm"        : "armhf",
    "ppc64le"    : "ppc64el",
    "powerpc64le": "ppc64el",
    "ppc64el"    : "ppc64el",
    "riscv64"    : "riscv64",
    "s390x"      : "s390x"
}
ORDERED_TEST_NAMES = [
    "context siwtch",
    "small read",
    "mid read",
    "big read",
    "small write",
    "mid write",
    "big write",
    "mmap",
    "small mmap",
    "small munmap",
    "mid munmap",
    "big munmap",
    "fork",
    "big fork",
    "thr create",
    "send",
    "recv",
    "big send",
    "big recv",
    "select",
    "poll",
    "epoll",
    "big select",
    "big poll",
    "big epoll",
    "small page fault",
    "big page fault",
    "getpid"
]

PRETTY_DISPLAY_NAMES = {
    "context siwtch"  : "contextswitch",
    "thr create"      : "thread",
    "small write"     : "small-write",
    "small read"      : "small-read",
    "mid write"       : "med-write",
    "mid read"        : "med-read",
    "big write"       : "big-write",
    "big read"        : "big-read",
    "small mmap"      : "mmap *",
    "mmap"            : "mmap *",
    "small munmap"    : "small-munmap",
    "mid munmap"      : "med-munmap",
    "big munmap"      : "big-munmap",
    "send"            : "send & recv *",
    "recv"            : "send & recv *",
    "big send"        : "big-send & recv *",
    "big recv"        : "big-send & recv *",
    "small page fault": "small-pagefault",
    "big page fault"  : "big-pagefault",
}


def get_target_architecture() -> str:
    architecture = (
        os.environ.get("TARGET_ARCH")
        or os.environ.get("ARCH")
        or platform.machine()
    )
    return ARCHITECTURE_NAME_ALIASES.get(architecture, architecture)


def parse_result_csv(path: str) -> dict[str, float]:
    results = {}
    with open(path, encoding="utf-8", errors="replace") as file:
        for line in file:
            if "kbest:," not in line:
                continue

            parts = line.split(",")
            if len(parts) < 2:
                continue

            left = parts[0]
            timestamp = parts[1].strip()

            name = re.sub(r"\s+kbest:\s*$", "", left).strip()
            match = re.match(r"(\d+)\.(\d{9})", timestamp)
            if not match:
                continue

            seconds = int(match.group(1))
            nanoseconds = int(match.group(2))
            duration = seconds * 1_000_000_000 + nanoseconds
            results[name] = duration
    return results


def load_benchmark_results() -> pd.DataFrame:
    csv_file_paths = sorted(
        path for path in glob.glob(
            os.path.join(RESULTS_DIRECTORY_PATH, "**", "*.csv"),
            recursive=True,
        )

        if os.path.basename(path) != "results.csv"
    )
    if not csv_file_paths:
        print(f"[plot] No result CSV files found in '{RESULTS_DIRECTORY_PATH}/'.")
        print("[plot] Run 'make run-all' first.")
        sys.exit(1)

    rows = []
    default_target_architecture = get_target_architecture()
    for path in csv_file_paths:
        relative = os.path.relpath(path, RESULTS_DIRECTORY_PATH)
        parts = relative.split(os.sep)
        architecture = parts[0] if len(parts) > 1 else default_target_architecture
        kernel = os.path.basename(path)[:-len(".csv")]
        measurements = parse_result_csv(path)
        for test, duration in measurements.items():
            rows.append({
                "arch": architecture,
                "kernel": kernel,
                "series": f"{architecture} Linux {kernel}",
                "test": test,
                "ns": duration,
            })

    frame = pd.DataFrame(rows)
    print(f"[plot] Loaded {len(csv_file_paths)} result file(s): "
          f"{[os.path.basename(path) for path in csv_file_paths]}")
    return frame


def version_sorting_key(version: str) -> tuple:
    parts = re.findall(r"\d+|[A-Za-z]+", version)
    key = []
    for part in parts:
        key.append((0, int(part)) if part.isdigit() else (1, part))
    return tuple(key)


def get_ordered_tests(tests: list[str]) -> list[str]:
    preferred = [test for test in ORDERED_TEST_NAMES if test in tests]
    remaining = sorted((test for test in tests if test not in preferred), key=str.lower)
    return preferred + remaining


def format_heatmap_label(test: str) -> str:
    return PRETTY_DISPLAY_NAMES.get(test, test.replace(" ", "-"))


def select_baseline_version(pivot: pd.DataFrame) -> str:
    if BASELINE_KERNEL_VERSION in pivot.columns:
        return BASELINE_KERNEL_VERSION

    fallback = sorted(pivot.columns, key=version_sorting_key)[0]
    print(
        f"[plot] WARNING: baseline {BASELINE_KERNEL_VERSION} not found; "
        f"using {fallback} instead."
    )
    return fallback


def make_percentage_heatmap(frame: pd.DataFrame) -> None:
    colormap = LinearSegmentedColormap.from_list(
        "latency_change",
        [
            (0.00, "#12e83f"),
            (0.25, "#12e83f"),
            (0.50, "#fff200"),
            (0.75, "#ff9d24"),
            (1.00, "#ff2a1f"),
        ],
    )
    normalizer = Normalize(vmin=-50, vmax=150)

    for architecture, subset in frame.groupby("arch", sort=True):
        pivot = subset.pivot_table(
            index="test",
            columns="kernel",
            values="ns",
            aggfunc="mean",
        )
        
        pivot = pivot.reindex(index=get_ordered_tests(pivot.index.tolist()))
        pivot = pivot.reindex(columns=sorted(pivot.columns, key=version_sorting_key))
        pivot.index = [format_heatmap_label(test) for test in pivot.index]
        pivot = pivot.groupby(level=0, sort=False).mean()

        baseline = select_baseline_version(pivot)
        change = ((pivot.div(pivot[baseline], axis=0) - 1.0) * 100.0).replace(
            [np.inf, -np.inf],
            np.nan,
        )

        height = max(4.8, 0.29 * len(change.index))
        width = max(9.5, 0.28 * len(change.columns))
        figure, axes = plt.subplots(figsize=(width, height))

        image = axes.imshow(
            change.to_numpy(dtype=float),
            cmap=colormap,
            norm=normalizer,
            aspect="auto",
            interpolation="nearest",
        )

        axes.set_title(
            f"(a) Percentage Change in Test Latency Relative to v{baseline}",
            fontsize=14,
            fontfamily="serif",
            pad=10,
        )
        axes.set_xticks(np.arange(len(change.columns)))
        axes.set_xticklabels(change.columns, rotation=90, fontsize=9, va="top")
        axes.set_yticks(np.arange(len(change.index)))
        axes.set_yticklabels(change.index, fontsize=10)
        axes.tick_params(axis="both", length=0)
        axes.set_xticks(np.arange(-0.5, len(change.columns), 1), minor=True)
        axes.set_yticks(np.arange(-0.5, len(change.index), 1), minor=True)
        axes.grid(which="minor", color="black", linestyle="-", linewidth=0.35)
        axes.tick_params(which="minor", bottom=False, left=False)

        for row, test in enumerate(change.index):
            for column, kernel in enumerate(change.columns):
                value = change.loc[test, kernel]
                if pd.isna(value):
                    label = ""
                else:
                    label = f"{int(round(value))}"

                axes.text(
                    column,
                    row,
                    label,
                    ha="center",
                    va="center",
                    fontsize=5.5,
                    color="black",
                )

        bar = figure.colorbar(image, ax=axes, fraction=0.025, pad=0.012)
        ticks = [-50, -25, 0, 25, 50, 75, 100, 125, 150]
        bar.set_ticks(ticks)
        bar.set_ticklabels([f"{tick}%" for tick in ticks])
        bar.outline.set_linewidth(0.8)

        figure.tight_layout(pad=0.4)
        destination = os.path.join(
            PLOTS_DIRECTORY_PATH,
            f"percentage_change_{architecture}.png",
        )
        figure.savefig(destination, dpi=200, bbox_inches="tight")
        plt.close(figure)
        print(f"[plot] Saved: {destination}")


def main() -> None:
    os.makedirs(PLOTS_DIRECTORY_PATH, exist_ok=True)

    frame = load_benchmark_results()
    print(f"[plot] Architectures found: {sorted(frame['arch'].unique())}")
    print(f"[plot] Kernels found: {sorted(frame['kernel'].unique())}")
    print(f"[plot] Tests found:   {sorted(frame['test'].unique())}")

    make_percentage_heatmap(frame)

    aggregated_results_path = os.path.join(RESULTS_DIRECTORY_PATH, "results.csv")
    frame.to_csv(aggregated_results_path, index=False)
    print(f"[plot] Results path:  {aggregated_results_path}")


if __name__ == "__main__":
    main()
