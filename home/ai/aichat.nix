{ pkgs, ... }:

{
  programs.aichat = {
    enable = true;
    # settings = {
    #   # Configure LLM providers here
    #   # model = "openai:gpt-4";
    #   # clients = [
    #   #   {
    #   #     type = "openai";
    #   #     api_key = "env:OPENAI_API_KEY";
    #   #   }
    #   # ];
    # };
  };
}
