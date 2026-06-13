{
  services.pueue = {
    enable = true;
    settings = {
      daemon = {
        default_parallel_tasks = 2;
      };
      client = {
        read_local_logs = true;
        show_confirmation_questions = false;
        dark_mode = true;
      };
    };
  };
}
