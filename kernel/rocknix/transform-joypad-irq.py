#!/usr/bin/env python3
"""Strictly split fixed H700 buttons from the 10 ms analog poller."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"joypad IRQ {label} authority changed ({count} matches)")
    return source.replace(old, new)


def replace_region(
    source: str, start: str, end: str, replacement: str, label: str
) -> str:
    if source.count(start) != 1 or source.count(end) != 1:
        raise SystemExit(f"joypad IRQ {label} boundary authority changed")
    begin = source.index(start)
    finish = source.index(end, begin)
    return source[:begin] + replacement + source[finish:]


def transform(source: str, expected_buttons: int) -> str:
    source = replace_once(
        source,
        '#include <linux/jiffies.h>\n',
        '#include <linux/jiffies.h>\n'
        '#include <linux/hrtimer.h>\n'
        '#include <linux/interrupt.h>\n'
        '#include <linux/spinlock.h>\n',
        "includes",
    )
    source = replace_once(
        source,
        '#define DRV_NAME "rocknix-singleadc-joypad"\n',
        '#define DRV_NAME "rocknix-singleadc-joypad"\n'
        f'#define BIRD_FIXED_GPIO_BUTTONS {expected_buttons}\n'
        '#define BIRD_GPIO_DEBOUNCE_MS 5\n',
        "fixed constants",
    )
    source = replace_once(
        source,
        'struct bt_gpio {\n',
        'struct joypad;\n\nstruct bt_gpio {\n',
        "joypad forward declaration",
    )
    source = replace_once(
        source,
        '\t/* button press level */\n\tbool active_level;\n};\n',
        '\t/* button press level */\n'
        '\tbool active_level;\n'
        '\tstruct joypad *joypad;\n'
        '\tstruct hrtimer debounce_timer;\n'
        '\tint irq;\n'
        '};\n',
        "GPIO IRQ state",
    )
    source = replace_once(
        source,
        '\tstruct mutex lock;\n',
        '\tstruct mutex lock;\n'
        '\tspinlock_t event_lock;\n'
        '\tbool suspended;\n'
        '\tbool irqs_enabled;\n',
        "event lock",
    )

    irq_and_adc = r'''static enum hrtimer_restart joypad_gpio_debounce(struct hrtimer *timer)
{
	struct bt_gpio *gpio = container_of(timer, struct bt_gpio,
					     debounce_timer);
	struct joypad *joypad = gpio->joypad;
	unsigned long flags;
	int value;

	if (!READ_ONCE(joypad->enable) || READ_ONCE(joypad->suspended) ||
	    !READ_ONCE(joypad->irqs_enabled))
		return HRTIMER_NORESTART;

	value = gpio_get_value(gpio->num);
	if (value < 0) {
		dev_err_ratelimited(joypad->dev, "failed to get gpio state\n");
		return HRTIMER_NORESTART;
	}

	spin_lock_irqsave(&joypad->event_lock, flags);
	if (joypad->enable && !joypad->suspended && joypad->irqs_enabled &&
	    value != gpio->old_value) {
		input_event(joypad->input, gpio->report_type,
			    gpio->linux_code,
			    value == gpio->active_level ? 1 : 0);
		gpio->old_value = value;
		input_sync(joypad->input);
	}
	spin_unlock_irqrestore(&joypad->event_lock, flags);

	return HRTIMER_NORESTART;
}

static irqreturn_t joypad_gpio_irq(int irq, void *data)
{
	struct bt_gpio *gpio = data;
	struct joypad *joypad = gpio->joypad;

	if (READ_ONCE(joypad->enable) && !READ_ONCE(joypad->suspended) &&
	    READ_ONCE(joypad->irqs_enabled))
		hrtimer_start(&gpio->debounce_timer,
			      ms_to_ktime(BIRD_GPIO_DEBOUNCE_MS),
			      HRTIMER_MODE_REL);

	return IRQ_HANDLED;
}

/*----------------------------------------------------------------------------*/
static bool joypad_adc_check(struct input_polled_dev *poll_dev, bool publish)
{
	struct joypad *joypad = poll_dev->private;
	int report_type[4];
	int report_value[4];
	unsigned long flags;
	bool changed = false;
	int report_count = 0;
	int nbtn;
	int mag;
	int old_value;

	/* Sample all four axes before publishing one coherent input frame. */
	for (nbtn = 0; nbtn < joypad->amux_count; nbtn += 2) {
		struct bt_adc *adcx = &joypad->adcs[nbtn];
		struct bt_adc *adcy = &joypad->adcs[nbtn + 1];

		adcx->value = joypad_adc_read(joypad->amux, adcx);
		if (!adcx->value)
			continue;
		adcx->value -= adcx->cal;

		adcy->value = joypad_adc_read(joypad->amux, adcy);
		if (!adcy->value)
			continue;
		adcy->value -= adcy->cal;

		mag = int_sqrt((adcx->value * adcx->value) +
			       (adcy->value * adcy->value));
		if (joypad->bt_adc_deadzone) {
			if (mag <= joypad->bt_adc_deadzone) {
				adcx->value = 0;
				adcy->value = 0;
			} else {
				adcx->value = (((adcx->max * adcx->value) / mag) *
					       (mag - joypad->bt_adc_deadzone)) /
					      (adcx->max - joypad->bt_adc_deadzone);
				adcy->value = (((adcy->max * adcy->value) / mag) *
					       (mag - joypad->bt_adc_deadzone)) /
					      (adcy->max - joypad->bt_adc_deadzone);
			}
		}

		if (adcx->tuning_n && adcx->value < 0)
			adcx->value = ADC_DATA_TUNING(adcx->value, adcx->tuning_n);
		if (adcx->tuning_p && adcx->value > 0)
			adcx->value = ADC_DATA_TUNING(adcx->value, adcx->tuning_p);
		if (adcy->tuning_n && adcy->value < 0)
			adcy->value = ADC_DATA_TUNING(adcy->value, adcy->tuning_n);
		if (adcy->tuning_p && adcy->value > 0)
			adcy->value = ADC_DATA_TUNING(adcy->value, adcy->tuning_p);

		adcx->value = CLAMP(adcx->value, adcx->min, adcx->max);
		adcy->value = CLAMP(adcy->value, adcy->min, adcy->max);
		report_type[report_count] = adcx->report_type;
		report_value[report_count++] =
			adcx->invert ? -adcx->value : adcx->value;
		report_type[report_count] = adcy->report_type;
		report_value[report_count++] =
			adcy->invert ? -adcy->value : adcy->value;
	}

	spin_lock_irqsave(&joypad->event_lock, flags);
	for (nbtn = 0; nbtn < report_count; nbtn++) {
		old_value = input_abs_get_val(poll_dev->input, report_type[nbtn]);
		input_report_abs(poll_dev->input, report_type[nbtn],
				 report_value[nbtn]);
		changed |= input_abs_get_val(poll_dev->input,
					       report_type[nbtn]) != old_value;
	}
	if (publish && changed)
		input_sync(poll_dev->input);
	spin_unlock_irqrestore(&joypad->event_lock, flags);

	return changed;
}

/*----------------------------------------------------------------------------*/
'''
    source = replace_region(
        source,
        "static bool joypad_gpio_check(struct input_polled_dev *poll_dev)\n",
        "static void joypad_poll(struct input_polled_dev *poll_dev)\n",
        irq_and_adc,
        "GPIO/ADC functions",
    )

    poll_open_close = r'''static void joypad_poll(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	unsigned long flags;
	bool changed = false;
	int old_value;

	if (joypad->enable) {
		if (joypad->use_miyoo_serial) {
			spin_lock_irqsave(&joypad->event_lock, flags);
#define BIRD_REPORT_SERIAL_AXIS(code, value) do { \
	old_value = input_abs_get_val(poll_dev->input, code); \
	input_report_abs(poll_dev->input, code, value); \
	changed |= input_abs_get_val(poll_dev->input, code) != old_value; \
} while (0)
			BIRD_REPORT_SERIAL_AXIS(ABS_X, joypad->miyoo.left_x);
			BIRD_REPORT_SERIAL_AXIS(ABS_Y, joypad->miyoo.left_y);
			BIRD_REPORT_SERIAL_AXIS(ABS_RX, joypad->miyoo.right_x);
			BIRD_REPORT_SERIAL_AXIS(ABS_RY, joypad->miyoo.right_y);
#undef BIRD_REPORT_SERIAL_AXIS
			if (changed)
				input_sync(poll_dev->input);
			spin_unlock_irqrestore(&joypad->event_lock, flags);
		} else {
			joypad_adc_check(poll_dev, true);
		}
	}
	if (poll_dev->poll_interval != joypad->poll_interval) {
		mutex_lock(&joypad->lock);
		poll_dev->poll_interval = joypad->poll_interval;
		mutex_unlock(&joypad->lock);
	}
}

/*----------------------------------------------------------------------------*/
static bool joypad_reconcile_buttons(struct joypad *joypad, bool force)
{
	int values[BIRD_FIXED_GPIO_BUTTONS];
	unsigned long flags;
	bool changed = false;
	int nbtn;

	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
		values[nbtn] = gpio_get_value(joypad->gpios[nbtn].num);

	spin_lock_irqsave(&joypad->event_lock, flags);
	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++) {
		struct bt_gpio *gpio = &joypad->gpios[nbtn];

		if (values[nbtn] < 0) {
			if (!force)
				continue;
			values[nbtn] = gpio->active_level ? 0 : 1;
		}
		if (force || values[nbtn] != gpio->old_value) {
			input_event(joypad->input, gpio->report_type,
				    gpio->linux_code,
				    values[nbtn] == gpio->active_level ? 1 : 0);
			gpio->old_value = values[nbtn];
			changed = true;
		}
	}
	if (changed)
		input_sync(joypad->input);
	spin_unlock_irqrestore(&joypad->event_lock, flags);
	return changed;
}

/*----------------------------------------------------------------------------*/
static void joypad_open(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	unsigned long flags;
	bool activate_irqs;
	int nbtn;

	for (nbtn = 0; nbtn < joypad->amux_count; nbtn++) {
		struct bt_adc *adc = &joypad->adcs[nbtn];

		adc->value = joypad_adc_read(joypad->amux, adc);
		if (!adc->value) {
			dev_err(joypad->dev, "%s : saradc channels[%d]!\n",
				__func__, nbtn);
			continue;
		}
		adc->cal = adc->value;
	}
	joypad_adc_check(poll_dev, false);
	joypad_reconcile_buttons(joypad, true);

	spin_lock_irqsave(&joypad->event_lock, flags);
	joypad->enable = true;
	activate_irqs = !joypad->suspended;
	joypad->irqs_enabled = activate_irqs;
	spin_unlock_irqrestore(&joypad->event_lock, flags);

	if (activate_irqs) {
		for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
			enable_irq(joypad->gpios[nbtn].irq);
		/* Close the sample-to-enable window. */
		joypad_reconcile_buttons(joypad, false);
	}
}

/*----------------------------------------------------------------------------*/
static void joypad_close(struct input_polled_dev *poll_dev)
{
	struct joypad *joypad = poll_dev->private;
	unsigned long flags;
	bool deactivate_irqs;
	int nbtn;

	spin_lock_irqsave(&joypad->event_lock, flags);
	joypad->enable = false;
	deactivate_irqs = joypad->irqs_enabled;
	joypad->irqs_enabled = false;
	spin_unlock_irqrestore(&joypad->event_lock, flags);

	if (deactivate_irqs) {
		for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
			disable_irq(joypad->gpios[nbtn].irq);
	}
	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
		hrtimer_cancel(&joypad->gpios[nbtn].debounce_timer);

	if (joypad->has_rumble) {
		cancel_work_sync(&joypad->play_work);
		pwm_vibrator_stop(joypad);
	}
}

/*----------------------------------------------------------------------------*/
'''
    source = replace_region(
        source,
        "static void joypad_poll(struct input_polled_dev *poll_dev)\n",
        "static int joypad_amux_setup(struct device *dev, struct joypad *joypad)\n",
        poll_open_close,
        "poll/open/close functions",
    )

    source = replace_once(
        source,
        "\tif (nbtn == 0)\n\t\treturn -EINVAL;\n\n\treturn\t0;\n",
        "\tif (nbtn != BIRD_FIXED_GPIO_BUTTONS) {\n"
        "\t\tdev_err(dev, \"fixed RG34XX-SP GPIO count changed: %d\\n\", nbtn);\n"
        "\t\treturn -EINVAL;\n"
        "\t}\n\n"
        "\tfor (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++) {\n"
        "\t\tstruct bt_gpio *gpio = &joypad->gpios[nbtn];\n\n"
        "\t\tint irq_error;\n\n"
        "\t\tgpio->joypad = joypad;\n"
        "\t\tgpio->irq = gpio_to_irq(gpio->num);\n"
        "\t\tif (gpio->irq < 0)\n"
        "\t\t\treturn gpio->irq;\n"
		"\t\thrtimer_setup(&gpio->debounce_timer, joypad_gpio_debounce,\n"
		"\t\t\t      CLOCK_MONOTONIC, HRTIMER_MODE_REL);\n"
        "\t\tirq_error = devm_request_irq(dev, gpio->irq, joypad_gpio_irq,\n"
        "\t\t\t\t IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING |\n"
        "\t\t\t\t IRQF_NO_AUTOEN,\n"
        "\t\t\t\t gpio->label, gpio);\n"
        "\t\tif (irq_error) {\n"
        "\t\t\tdev_err(dev, \"Failed to request GPIO IRQ %d, error %d\\n\",\n"
        "\t\t\t\tgpio->irq, irq_error);\n"
        "\t\t\treturn irq_error;\n"
        "\t\t}\n"
        "\t}\n\n"
        "\treturn\t0;\n",
        "GPIO IRQ registration",
    )
    source = replace_once(
        source,
        "\tinput = poll_dev->input;\n\n\tinput->name = DRV_NAME;\n",
        "\tinput = poll_dev->input;\n"
        "\tjoypad->input = input;\n\n"
        "\tinput->name = DRV_NAME;\n",
        "input pointer",
    )
    source = replace_once(
        source,
        "\tmutex_init(&joypad->lock);\n",
        "\tmutex_init(&joypad->lock);\n"
        "\tspin_lock_init(&joypad->event_lock);\n",
        "spinlock initialization",
    )

    suspend_resume = r'''static int __maybe_unused joypad_suspend(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	unsigned long flags;
	bool deactivate_irqs;
	int nbtn;

	spin_lock_irqsave(&joypad->event_lock, flags);
	joypad->suspended = true;
	deactivate_irqs = joypad->irqs_enabled;
	joypad->irqs_enabled = false;
	spin_unlock_irqrestore(&joypad->event_lock, flags);
	if (deactivate_irqs) {
		for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
			disable_irq(joypad->gpios[nbtn].irq);
	}
	for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
		hrtimer_cancel(&joypad->gpios[nbtn].debounce_timer);

	if (joypad->has_rumble) {
		cancel_work_sync(&joypad->play_work);
		if (joypad->level)
			pwm_vibrator_stop(joypad);
	}
	return 0;
}

static int __maybe_unused joypad_resume(struct device *dev)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct joypad *joypad = platform_get_drvdata(pdev);
	unsigned long flags;
	bool activate_irqs;
	int nbtn;

	spin_lock_irqsave(&joypad->event_lock, flags);
	joypad->suspended = false;
	activate_irqs = joypad->enable && !joypad->irqs_enabled;
	if (activate_irqs)
		joypad->irqs_enabled = true;
	spin_unlock_irqrestore(&joypad->event_lock, flags);
	if (activate_irqs) {
		for (nbtn = 0; nbtn < joypad->bt_gpio_count; nbtn++)
			enable_irq(joypad->gpios[nbtn].irq);
		joypad_reconcile_buttons(joypad, false);
	}

	if (joypad->has_rumble && joypad->level)
		pwm_vibrator_start(joypad);
	return 0;
}

'''
    source = replace_region(
        source,
        "static int __maybe_unused joypad_suspend(struct device *dev)\n",
        "static SIMPLE_DEV_PM_OPS(joypad_pm_ops, joypad_suspend, joypad_resume);\n",
        suspend_resume,
        "suspend/resume functions",
    )

    required = {
        "both-edge IRQ": "IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING",
        "5 ms debounce": "BIRD_GPIO_DEBOUNCE_MS 5",
        "all fixed buttons": f"BIRD_FIXED_GPIO_BUTTONS {expected_buttons}",
        "timer close cancellation": "hrtimer_cancel(&joypad->gpios[nbtn].debounce_timer);",
        "analog poll": "joypad_adc_check(poll_dev, true);",
        "initial state frame": "input_sync(poll_dev->input);",
    }
    for label, needle in required.items():
        if needle not in source:
            raise SystemExit(f"joypad IRQ {label} output missing")
    if "joypad_gpio_check(poll_dev)" in source:
        raise SystemExit("joypad GPIO polling remains in periodic path")
    return source


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--expected-buttons", type=int, required=True)
    args = parser.parse_args()
    if args.expected_buttons <= 0:
        raise SystemExit("expected button count must be positive")
    original = args.source.read_text(encoding="utf-8")
    transformed = transform(original, args.expected_buttons)
    args.source.write_text(transformed, encoding="utf-8")


if __name__ == "__main__":
    main()
