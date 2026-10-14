// SPDX-License-Identifier: GPL-2.0
/*
 * ps5_hdmi_fix - re-arm the PS5 FLAVA3 DP->HDMI bridge after the monitor
 * re-announces itself.
 *
 * The in-kernel driver (drivers/ps5/hdmi.c) configures the bridge once per
 * modeset and has no hot-plug handling. 4K60 needs HDMI scrambling, and when
 * the monitor pulses hot-plug after the mode was set (it does this ~10 s after
 * a quick mode change, and after waking up) the picture is lost until the
 * bridge is configured again. This module watches for the "got real edid"
 * notification and replays the bridge setup for the current mode.
 *
 * Manual trigger: echo reconf > /sys/module/ps5_hdmi_fix/parameters/cmd
 */
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/kprobes.h>
#include <linux/workqueue.h>
#include <linux/jiffies.h>
#include <linux/mutex.h>
#include <linux/string.h>
#include <linux/ps5.h>
#include <drm/drm_modes.h>

static bool enabled = true;
module_param(enabled, bool, 0644);
static bool only_4k = true;          /* only 4K needs scrambling */
module_param(only_4k, bool, 0644);
static unsigned int delay_ms = 1500; /* wait after the notification */
module_param(delay_ms, uint, 0644);
static unsigned int reconf_count;
module_param(reconf_count, uint, 0444);

static struct drm_display_mode last_mode;
static bool have_mode;
static int last_channels = 2;
static unsigned long last_cfg_jiffies;
static bool in_reconf;
static unsigned long burst_start;
static unsigned int burst_n;
static DEFINE_MUTEX(fix_lock);
static struct delayed_work fix_work;

static void do_reconf(const char *why)
{
	struct drm_display_mode m;

	mutex_lock(&fix_lock);
	if (!have_mode) {
		pr_info("ps5_hdmi_fix: %s: no mode seen yet, skipping\n", why);
		goto out;
	}
	m = last_mode;
	pr_info("ps5_hdmi_fix: %s: reconfiguring bridge for %dx%d\n", why,
		m.hdisplay, m.vdisplay);
	in_reconf = true;
	sceHdmiSetAudioMute(1);
	sceHdmiDeviceSetVideoMute(1);
	sceHdmiInitVideoConfig();
	sceHdmiSetVideoConfig(&m);
	sceHdmiDeviceSetVideoMute(0);
	sceHdmiSetAudioConfig(last_channels);
	sceHdmiSetAudioMute(0);
	in_reconf = false;
	last_cfg_jiffies = jiffies;
	reconf_count++;
out:
	mutex_unlock(&fix_lock);
}

static void fix_work_fn(struct work_struct *w)
{
	if (!enabled || !have_mode)
		return;
	if (only_4k && !(last_mode.hdisplay == 3840 && last_mode.vdisplay == 2160))
		return;
	/* a real modeset is running or just ran: let it finish, then go */
	if (time_before(jiffies, last_cfg_jiffies + msecs_to_jiffies(4000))) {
		schedule_delayed_work(&fix_work, msecs_to_jiffies(2000));
		return;
	}
	/* never loop: at most 3 automatic replays per minute */
	if (time_after(jiffies, burst_start + 60 * HZ)) {
		burst_start = jiffies;
		burst_n = 0;
	}
	if (burst_n >= 3) {
		pr_warn("ps5_hdmi_fix: too many replays, backing off\n");
		return;
	}
	burst_n++;
	do_reconf("monitor re-announced");
}

/* kprobe handlers run in atomic context: only record and schedule */
static int kp_setvideo(struct kprobe *p, struct pt_regs *regs)
{
	const struct drm_display_mode *m = (void *)regs->di;

	if (!in_reconf && m) {
		pr_info("ps5_hdmi_fix: modeset %dx%d\n", m->hdisplay, m->vdisplay);
		last_mode = *m;
		have_mode = true;
		last_cfg_jiffies = jiffies;
	}
	return 0;
}

static int kp_setaudio(struct kprobe *p, struct pt_regs *regs)
{
	if (!in_reconf)
		last_channels = (int)regs->di;
	return 0;
}

static int kp_notify(struct kprobe *p, struct pt_regs *regs)
{
	struct icc_msg *msg = (void *)regs->di;

	if (enabled && msg && msg->data[1] == 0x02)
		mod_delayed_work(system_wq, &fix_work, msecs_to_jiffies(delay_ms));
	return 0;
}

static struct kprobe kps[] = {
	{ .symbol_name = "sceHdmiSetVideoConfig", .pre_handler = kp_setvideo },
	{ .symbol_name = "sceHdmiSetAudioConfig", .pre_handler = kp_setaudio },
	{ .symbol_name = "hdmi_notification_handler", .pre_handler = kp_notify },
};
static struct kprobe *kpp[] = { &kps[0], &kps[1], &kps[2] };

static int cmd_set(const char *val, const struct kernel_param *kp)
{
	if (!sysfs_streq(val, "reconf"))
		return -EINVAL;
	do_reconf("manual");
	return 0;
}
static const struct kernel_param_ops cmd_ops = { .set = cmd_set };
module_param_cb(cmd, &cmd_ops, NULL, 0200);

static int __init fix_init(void)
{
	int ret;

	INIT_DELAYED_WORK(&fix_work, fix_work_fn);
	burst_start = jiffies;
	last_cfg_jiffies = jiffies - 60 * HZ;
	ret = register_kprobes(kpp, ARRAY_SIZE(kpp));
	if (ret) {
		pr_err("ps5_hdmi_fix: kprobe registration failed: %d\n", ret);
		return ret;
	}
	pr_info("ps5_hdmi_fix: loaded\n");
	return 0;
}

static void __exit fix_exit(void)
{
	unregister_kprobes(kpp, ARRAY_SIZE(kpp));
	cancel_delayed_work_sync(&fix_work);
}
module_init(fix_init);
module_exit(fix_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("PS5 HDMI bridge re-arm on monitor hot-plug");
