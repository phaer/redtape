# red-tape

* There's a new alternative for the NixOS Module system, called adios.
  It's at  https://github.com/adisbladis/adios. Clone it and have a look at it

* There's blueprint, a convience layer around nix flakes. It's at https://github.com/numtide/blueprint. Clone it and take a look at it.

* There's https://github.com/Mic92/adios-flake, a project that uses adios to re-implement parts of flake-parts, another convienience layer around nxi flakes.

Please carefully investigate blueprints features and create a plan, on how to re-implement them using adios. It:

* should be modular
* should stay fast
* have minimal code
* support both traditional nix setups (default.nix, similar to how adios and the existing code in this repo does) as well as flakes

Do not implement anything, but provide a plan & design
