// SPDX-License-Identifier: GPL-2.0+
/*
 * AXP305 driver
 *
 * (C) Copyright 2020 Jernej Skrabec <jernej.skrabec@siol.net>
 *
 * Based on axp221.c
 * (C) Copyright 2014 Hans de Goede <hdegoede@redhat.com>
 * (C) Copyright 2013 Oliver Schinagl <oliver@schinagl.nl>
 */

#include <common.h>
#include <command.h>
#include <errno.h>
#include <asm/arch/pmic_bus.h>
#include <axp_pmic.h>

#define AXP305_DCDC4_1600MV_OFFSET 46

static u8 axp305_mvolt_to_cfg(int mvolt, int min, int max, int div)
{
	if (mvolt < min)
		mvolt = min;
	else if (mvolt > max)
		mvolt = max;

	return  (mvolt - min) / div;
}


int axp_set_dcdc4(unsigned int mvolt)
{
	int ret;
	u8 cfg;

	#if 0
	if (mvolt >= 1600)
		cfg = AXP305_DCDC4_1600MV_OFFSET +
			axp305_mvolt_to_cfg(mvolt, 1600, 3300, 100);
	else
		cfg = axp305_mvolt_to_cfg(mvolt, 600, 1500, 20);

	if (mvolt == 0)
		return pmic_bus_clrbits(AXP305_OUTPUT_CTRL1,
					AXP305_OUTPUT_CTRL1_DCDCD_EN);

	ret = pmic_bus_write(AXP305_DCDCD_VOLTAGE, cfg);
	if (ret)
		return ret;

	return pmic_bus_setbits(AXP305_OUTPUT_CTRL1,
				AXP305_OUTPUT_CTRL1_DCDCD_EN);
	#endif
	return 0;
}



#define AXP305_DCDC3_1200MV_OFFSET 71
int axp_set_dcdc3(unsigned int mvolt)
{
	int ret;
	u8 cfg;

	if (mvolt >= 1220)
	{
		cfg = AXP305_DCDC3_1200MV_OFFSET +
			axp305_mvolt_to_cfg(mvolt, 1220, 1840, 20);
	}
	else
		cfg = axp305_mvolt_to_cfg(mvolt, 500, 1200, 10);

	if (mvolt == 0)
		return pmic_bus_clrbits(AXP305_OUTPUT_CTRL1,
					AXP305_OUTPUT_CTRL1_DCDCD_EN);

	ret = pmic_bus_write(AXP305_DCDCD_VOLTAGE, cfg);
	if (ret)
		return ret;
 
	return pmic_bus_setbits(AXP305_OUTPUT_CTRL1,
				0x1f);
}


int axp_init(void)
{
	u8 axp_chip_id;
	int ret;

	ret = pmic_bus_init();
	if (ret)
		return ret;

	ret = pmic_bus_read(AXP305_CHIP_VERSION, &axp_chip_id);
	if (ret)
		return ret;

	// if ((axp_chip_id & AXP305_CHIP_VERSION_MASK) != 0x40)
	// 	return -ENODEV;

	if ((axp_chip_id & AXP305_CHIP_VERSION_MASK) != 0x4b)
		return -ENODEV;

	printf("pmic id is 0x%x\n",axp_chip_id);

	axp_set_dcdc3(1500);

	return ret;
}

#if !CONFIG_IS_ENABLED(ARM_PSCI_FW) && !IS_ENABLED(CONFIG_SYSRESET_CMD_POWEROFF)
int do_poweroff(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
	pmic_bus_write(AXP305_SHUTDOWN, AXP305_POWEROFF);

	/* infinite loop during shutdown */
	while (1) {}

	/* not reached */
	return 0;
}
#endif
