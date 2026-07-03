{ pkgs ? import <nixpkgs> {} }:

let
  luaEnv = pkgs.lua52Packages.lua.withPackages (ps: with ps; [
    luasocket
    luaposix
    dkjson
  ]);
in
  luaEnv
