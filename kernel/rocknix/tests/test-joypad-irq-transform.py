#!/usr/bin/env python3
"""Host contract tests for the fixed RG34XX-SP IRQ button transform."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
TRANSFORM = ROOT / "kernel/rocknix/transform-joypad-irq.py"


def load_transform():
    spec = importlib.util.spec_from_file_location("bird_joypad_irq", TRANSFORM)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PRE_IRQ = r'''#include <linux/jiffies.h>
#define DRV_NAME "rocknix-singleadc-joypad"
struct bt_gpio {
	int num;
	int report_type;
	int linux_code;
	bool old_value;
	/* button press level */
	bool active_level;
};
struct joypad {
	struct mutex lock;
	bool enable;
	struct input_dev *input;
};
static bool joypad_gpio_check(struct input_polled_dev *poll_dev)
{
	return false;
}
static bool joypad_adc_check(struct input_polled_dev *poll_dev)
{
	return false;
}
static void joypad_poll(struct input_polled_dev *poll_dev)
{
	joypad_adc_check(poll_dev);
	joypad_gpio_check(poll_dev);
}
static void joypad_open(struct input_polled_dev *poll_dev)
{
	input_sync(poll_dev->input);
}
static void joypad_close(struct input_polled_dev *poll_dev)
{
}
static int joypad_amux_setup(struct device *dev, struct joypad *joypad)
{
	return 0;
}
static int joypad_gpio_setup(struct device *dev, struct joypad *joypad)
{
	int nbtn;
	int error;
	if (of_property_read_u32(pp, "linux,code", &gpio->linux_code))
		return -EINVAL;
	if (nbtn == 0)
		return -EINVAL;

	return	0;
}
static int joypad_input_setup(struct device *dev, struct joypad *joypad)
{
	struct input_dev *input;
	struct input_polled_dev *poll_dev;
	input = poll_dev->input;

	input->name = DRV_NAME;
	return 0;
}
static int __maybe_unused joypad_suspend(struct device *dev)
{
	return 0;
}
static int __maybe_unused joypad_resume(struct device *dev)
{
	return 0;
}
static SIMPLE_DEV_PM_OPS(joypad_pm_ops, joypad_suspend, joypad_resume);
static int joypad_probe(struct platform_device *pdev)
{
	struct joypad *joypad;
	mutex_init(&joypad->lock);
	return 0;
}
'''


def function_body(source: str, signature: str, next_signature: str) -> str:
    return source[source.index(signature) : source.index(next_signature)]


def main() -> None:
    module = load_transform()
    result = module.transform(PRE_IRQ, 17)

    assert "#define BIRD_FIXED_GPIO_BUTTONS 17" in result
    assert "#define BIRD_GPIO_DEBOUNCE_MS 5" in result
    assert "IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING" in result
    assert "IRQF_NO_AUTOEN" in result
    assert "int irq_error;" in result
    assert "irq_error = devm_request_irq" in result
    assert "hrtimer_setup(&gpio->debounce_timer, joypad_gpio_debounce," in result
    assert "hrtimer_init(" not in result
    assert "hrtimer_start(&gpio->debounce_timer" in result
    assert "hrtimer_cancel(&joypad->gpios[nbtn].debounce_timer);" in result
    assert result.count("hrtimer_cancel(&joypad->gpios[nbtn].debounce_timer);") == 2
    assert "nbtn != BIRD_FIXED_GPIO_BUTTONS" in result
    assert "joypad->input = input;" in result
    assert "spin_lock_init(&joypad->event_lock);" in result

    poll = function_body(
        result,
        "static void joypad_poll(struct input_polled_dev *poll_dev)",
        "static bool joypad_reconcile_buttons(struct joypad *joypad, bool force)",
    )
    assert "joypad_adc_check(poll_dev, true);" in poll
    assert "gpio_get_value" not in poll
    assert "joypad_gpio_check" not in poll

    adc = function_body(
        result,
        "static bool joypad_adc_check(struct input_polled_dev *poll_dev, bool publish)",
        "static void joypad_poll(struct input_polled_dev *poll_dev)",
    )
    assert adc.index("joypad_adc_read") < adc.index("spin_lock_irqsave")
    assert "if (publish && changed)\n\t\tinput_sync" in adc

    opened = function_body(
        result,
        "static void joypad_open(struct input_polled_dev *poll_dev)",
        "static void joypad_close(struct input_polled_dev *poll_dev)",
    )
    assert opened.count("joypad_reconcile_buttons(joypad, true);") == 1
    assert opened.count("joypad_reconcile_buttons(joypad, false);") == 1
    assert opened.index("joypad_adc_check(poll_dev, false);") < opened.index(
        "joypad_reconcile_buttons(joypad, true);"
    )
    assert opened.index("joypad->enable = true;") < opened.index("enable_irq(")
    assert opened.index("enable_irq(") < opened.index(
        "joypad_reconcile_buttons(joypad, false);"
    )

    closed = function_body(
        result,
        "static void joypad_close(struct input_polled_dev *poll_dev)",
        "static int joypad_amux_setup(struct device *dev, struct joypad *joypad)",
    )
    assert closed.index("joypad->enable = false;") < closed.index("disable_irq(")
    assert closed.index("disable_irq(") < closed.index("hrtimer_cancel(")

    suspend = function_body(
        result,
        "static int __maybe_unused joypad_suspend(struct device *dev)",
        "static int __maybe_unused joypad_resume(struct device *dev)",
    )
    assert suspend.index("joypad->suspended = true;") < suspend.index(
        "joypad->irqs_enabled = false;"
    )
    assert suspend.index("joypad->irqs_enabled = false;") < suspend.index(
        "disable_irq("
    )
    assert suspend.index("disable_irq(") < suspend.index("hrtimer_cancel(")

    resume = function_body(
        result,
        "static int __maybe_unused joypad_resume(struct device *dev)",
        "static SIMPLE_DEV_PM_OPS(joypad_pm_ops, joypad_suspend, joypad_resume);",
    )
    assert "activate_irqs = joypad->enable && !joypad->irqs_enabled;" in resume
    assert resume.index("enable_irq(") < resume.index(
        "joypad_reconcile_buttons(joypad, false);"
    )

    registration = result[result.index("gpio->irq = gpio_to_irq") :]
    assert registration.index("IRQF_NO_AUTOEN") < registration.index("return\t0;")
    assert "disable_irq(gpio->irq);" not in registration[: registration.index("return\t0;")]

    # The transform must preserve the DT-provided keycode/capability path. This
    # includes BTN_THUMBL/BTN_THUMBR (L3/R3), which are digital GPIO children.
    assert 'of_property_read_u32(pp, "linux,code", &gpio->linux_code)' in result
    assert "input_set_capability" not in PRE_IRQ or "input_set_capability" in result

    drifted = PRE_IRQ.replace("\tstruct mutex lock;", "\tstruct mutex changed;")
    try:
        module.transform(drifted, 17)
    except SystemExit as error:
        assert "event lock" in str(error)
    else:
        raise AssertionError("source-authority drift was accepted")

    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "joypad.c"
        path.write_text(PRE_IRQ, encoding="utf-8")
        transformed = module.transform(path.read_text(encoding="utf-8"), 17)
        path.write_text(transformed, encoding="utf-8")
        assert path.read_text(encoding="utf-8") == result

    # When the pinned source checkout is available, exercise the exact four
    # prerequisite transforms and this transform against the complete driver.
    joypad_root = pathlib.Path(
        os.environ.get(
            "JOYPAD_SOURCE", str(pathlib.Path.home() / "muos-kernel-source/rocknix-joypad")
        )
    )
    pristine = joypad_root / "rocknix-singleadc-joypad.c"
    if pristine.is_file():
        builder = (ROOT / "kernel/rocknix/build-source-reference.sh").read_text(
            encoding="utf-8"
        )
        scripts = re.findall(
            r'python3 - drivers/input/joystick/rocknix-singleadc-joypad\.c <<"PY"\n(.*?)\nPY',
            builder,
            re.S,
        )
        assert len(scripts) == 4
        with tempfile.TemporaryDirectory() as directory:
            exact_path = pathlib.Path(directory) / "rocknix-singleadc-joypad.c"
            exact_path.write_bytes(pristine.read_bytes())
            for script in scripts:
                subprocess.run(
                    [sys.executable, "-", str(exact_path)],
                    input=script,
                    text=True,
                    check=True,
                )
            exact = module.transform(exact_path.read_text(encoding="utf-8"), 17)
            assert "joypad_gpio_check(poll_dev)" not in exact
            assert "IRQF_NO_AUTOEN" in exact
            assert exact.count("joypad_reconcile_buttons(joypad, false);") == 2

    print("joypad IRQ transform tests: PASS")


if __name__ == "__main__":
    main()
