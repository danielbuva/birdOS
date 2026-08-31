#!/usr/bin/env python3
"""Host contract tests for deferred RG34XX-SP Wi-Fi SDIO power-up."""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-sunxi-mmc-deferred-wifi.py"

FIXTURE = """static int sunxi_mmc_probe(struct platform_device *pdev)
{
\tstruct mmc_host *mmc;
\tint ret;

\tret = mmc_of_parse(mmc);
\tif (ret)
\t\tgoto error_free_dma;

\tret = mmc_add_host(mmc);
\tif (ret)
\t\tgoto error_free_dma;
\treturn 0;
error_free_dma:
\treturn ret;
}
"""


def load_transform():
    spec = importlib.util.spec_from_file_location("bird_deferred_wifi", TRANSFORM)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_refusal(module, source: str, diagnostic: str) -> None:
    try:
        module.transform(source)
    except SystemExit as error:
        assert diagnostic in str(error)
    else:
        raise AssertionError("source-authority drift was accepted")


def main() -> None:
    module = load_transform()
    result = module.transform(FIXTURE)

    predicate = "if ((mmc->caps & MMC_CAP_NONREMOVABLE) && mmc->pwrseq)"
    assignment = "mmc->caps2 |= MMC_CAP2_NO_PRESCAN_POWERUP;"
    assert result.count(predicate) == 1
    assert result.count(assignment) == 1
    assert result.index("mmc_of_parse(mmc)") < result.index(predicate)
    assert result.index(predicate) < result.index("mmc_add_host(mmc)")
    assert "200 ms power sequence" in result

    expect_refusal(
        module,
        FIXTURE.replace("mmc_of_parse(mmc)", "mmc_of_parse(changed)"),
        "parse authority changed",
    )
    expect_refusal(module, result, "already present")
    expect_refusal(module, FIXTURE + FIXTURE, "2 matching probe anchors")

    with tempfile.TemporaryDirectory(prefix="bird-sunxi-mmc-test-") as directory:
        path = pathlib.Path(directory) / "sunxi-mmc.c"
        path.write_text(FIXTURE, encoding="utf-8")
        subprocess.run([sys.executable, str(TRANSFORM), str(path)], check=True)
        assert path.read_text(encoding="utf-8") == result

    print("sunxi MMC deferred Wi-Fi transform tests: PASS")


if __name__ == "__main__":
    main()
