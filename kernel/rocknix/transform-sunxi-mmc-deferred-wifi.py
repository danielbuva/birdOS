#!/usr/bin/env python3
"""Defer the fixed RG34XX-SP Wi-Fi SDIO power wait until MMC rescan."""

from __future__ import annotations

import argparse
from pathlib import Path


ANCHOR = """\tret = mmc_of_parse(mmc);
\tif (ret)
\t\tgoto error_free_dma;
"""

REPLACEMENT = ANCHOR + """
\t/*
\t * birdOS targets only the RG34XX-SP. Its one non-removable,
\t * power-sequenced sunxi host is the RTL8821CS Wi-Fi SDIO device.
\t * Let MMC's already queued rescan perform the 200 ms power sequence
\t * instead of holding the asynchronous platform probe and /init.
\t */
\tif ((mmc->caps & MMC_CAP_NONREMOVABLE) && mmc->pwrseq)
\t\tmmc->caps2 |= MMC_CAP2_NO_PRESCAN_POWERUP;
"""


def transform(source: str) -> str:
    count = source.count(ANCHOR)
    if count != 1:
        raise SystemExit(
            f"sunxi MMC parse authority changed ({count} matching probe anchors)"
        )
    if "MMC_CAP2_NO_PRESCAN_POWERUP" in source:
        raise SystemExit("sunxi MMC deferred-power policy is already present")
    result = source.replace(ANCHOR, REPLACEMENT)
    required = (
        "MMC_CAP_NONREMOVABLE",
        "mmc->pwrseq",
        "MMC_CAP2_NO_PRESCAN_POWERUP",
        "mmc_add_host(mmc)",
    )
    for needle in required:
        if needle not in result:
            raise SystemExit(f"sunxi MMC deferred-power output missing: {needle}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    original = args.source.read_text(encoding="utf-8")
    args.source.write_text(transform(original), encoding="utf-8")


if __name__ == "__main__":
    main()
