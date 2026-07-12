# Virtual machine class.
# VMware/open-vm-tools guest support.
{ ... }:
{
  services.xserver.videoDrivers = [ "vmware" ];
  virtualisation.vmware.guest.enable = true;
}
