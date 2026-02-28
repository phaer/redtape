# Darwin host using custom escape hatch (avoids needing real nix-darwin)
{ flake, inputs, hostName }:
{
  class = "nix-darwin";
  value = { _type = "test-darwin-system"; inherit hostName; };
}
