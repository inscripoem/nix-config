# Journal hygiene baseline for all hosts.
#
# SystemMaxUse caps the persistent journal (default: 10% of fs / 4G — far
# larger than diagnostic value). RateLimitBurst suppresses log storms from a
# single unit: the default (10000/30s) lets a crashing user session emit
# thousands of lines per interval, which is exactly what the 2026-11 earlyoom
# kill storms did. 300/30s still allows normal chatty services while cutting
# storm volume ~30x.

{ ... }:
{
  services.journald.settings.Journal = {
    SystemMaxUse = "200M";
    RateLimitIntervalSec = "30s";
    RateLimitBurst = 300;
  };
}
