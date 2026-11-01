{ pkgs, ... }:

# Forensics for the silent hard freezes: one TSV row every 2 s with the
# CPU/GPU power state at that instant. Rows are fsynced, so when the machine
# stops dead the last row is the last observation before it stopped. See
# docs/hard-hang-cstate.md.
let
  logDir = "/var/log/gpu-watch";

  gpuWatch = pkgs.writeText "gpu-watch.py" ''
    import glob
    import os
    import time

    LOG = "${logDir}/last.log"
    INTERVAL = 2
    MAX_BYTES = 2 * 1024 * 1024

    HEADER = (
        "ts\tuptime_s\tload1\tc1_us\tc2_us\tc3_us\tcpu_temp_mc\t"
        "gpu_cur_mhz\tgpu_act_mhz\trc6_ms\tthrottle\tgpu_energy_uj\t"
        "gpu_temp_mc\tgpu_fan_rpm\tnvme0_temp_mc\tnvme1_temp_mc\n"
    )


    def read(path, default=""):
        try:
            with open(path) as handle:
                return handle.read().strip()
        except OSError:
            return default


    def first(paths, default=""):
        for path in paths:
            value = read(path)
            if value:
                return value
        return default


    def hwmon_attr(sensor, attr, default=""):
        for base in glob.glob("/sys/class/hwmon/hwmon*"):
            if read(os.path.join(base, "name")) == sensor:
                value = read(os.path.join(base, attr))
                if value:
                    return value
        return default


    def gpu_attr(attr, default=""):
        return first(glob.glob("/sys/class/drm/card[0-9]*/gt/gt0/" + attr), default)


    def gpu_hwmon_attr(attr, default=""):
        paths = glob.glob("/sys/class/drm/card[0-9]*/device/hwmon/hwmon*/" + attr)
        return first(paths, default)


    def nvme_temp(index):
        paths = glob.glob("/sys/class/nvme/nvme" + str(index) + "/hwmon*/temp1_input")
        return first(paths, "0")


    def cpu_idle(state):
        path = "/sys/devices/system/cpu/cpu0/cpuidle/state" + str(state) + "/time"
        return read(path, "0")


    def sample():
        uptime = read("/proc/uptime", "0 0").split()[0]
        load1 = read("/proc/loadavg", "0").split()[0]
        fields = [
            time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            uptime,
            load1,
            cpu_idle(1),
            cpu_idle(2),
            cpu_idle(3),
            hwmon_attr("coretemp", "temp1_input", "0"),
            gpu_attr("rps_cur_freq_mhz", "0"),
            gpu_attr("rps_act_freq_mhz", "0"),
            gpu_attr("rc6_residency_ms", "0"),
            gpu_attr("throttle_reason_status", "0"),
            gpu_hwmon_attr("energy1_input", "0"),
            gpu_hwmon_attr("temp1_input", "0"),
            gpu_hwmon_attr("fan1_input", "0"),
            nvme_temp(0),
            nvme_temp(1),
        ]
        return "\t".join(fields) + "\n"


    def rotate():
        try:
            if os.path.getsize(LOG) > MAX_BYTES:
                os.replace(LOG, LOG + ".1")
        except OSError:
            pass


    def main():
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        if not os.path.exists(LOG):
            with open(LOG, "w") as handle:
                handle.write(HEADER)
        while True:
            rotate()
            with open(LOG, "a") as handle:
                handle.write(sample())
                handle.flush()
                os.fsync(handle.fileno())
            time.sleep(INTERVAL)


    if __name__ == "__main__":
        main()
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${logDir} 0755 root root -"
  ];

  systemd.services.gpu-watch = {
    description = "Sample CPU/GPU power states for hard-freeze forensics";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${gpuWatch}";
      Restart = "always";
      RestartSec = "5s";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
}
