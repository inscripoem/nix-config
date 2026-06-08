{
  programs.fish = {
    enable = true;
    shellAliases = {
      nhs = "nh os switch . -- --show-trace";
      ze = "zeditor .";
    };
  };
}
