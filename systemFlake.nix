{ flake-utils }:

{ self
, defaultSystem ? "x86_64-linux"
, sharedExtraArgs ? { inherit inputs; }
, supportedSystems ? flake-utils.lib.defaultSystems
, inputs
, nixosConfigurations ? { }
, nixosProfiles ? { }
, channels ? { }
, channelsConfig ? { }
, sharedModules ? [ ]
, sharedOverlays ? [ ]

, packagesBuilder ? null
, defaultPackageBuilder ? null
, appsBuilder ? null
, defaultAppBuilder ? null
, devShellBuilder ? null
, checksBuilder ? null
, ...
}@args:

let
  otherArguments = builtins.removeAttrs args [
    "defaultSystem"
    "sharedExtraArgs"
    "inputs"
    "nixosProfiles"
    "channels"
    "channelsConfig"
    "self"
    "sharedModules"
    "sharedOverlays"
    "supportedSystems"

    "packagesBuilder"
    "defaultPackageBuilder"
    "appsBuilder"
    "defaultAppBuilder"
    "devShellBuilder"
    "checksBuilder"
  ];

  nixosConfigurationBuilder = hostname: profile: (
    # It would be nice to get `nixosSystem` reference from `selectedNixpkgs` but it is not possible at this moment
    inputs.nixpkgs.lib.nixosSystem (genericConfigurationBuilder (getNixpkgs profile) hostname profile)
  );

  getNixpkgs = channelDefinition:
    let
      system = channelDefinition.system or defaultSystem;
      channelName = channelDefinition.channelName or "nixpkgs";
    in
    self.pkgs."${system}"."${channelName}";

  genericConfigurationBuilder = selectedNixpkgs: hostname: profile: (
    {
      inherit (selectedNixpkgs) system;
      modules = [
        ({ pkgs, lib, ... }: {
          networking.hostName = hostname;

          nixpkgs = {
            inherit (selectedNixpkgs) overlays config system;
          };

          system.configurationRevision = lib.mkIf (self ? rev) self.rev;
          nix.package = lib.mkDefault pkgs.nixUnstable;
        })
      ]
      ++ sharedModules
      ++ (selectedNixpkgs.lib.optionals (profile ? modules) profile.modules);
      extraArgs = sharedExtraArgs // selectedNixpkgs.lib.optionalAttrs (profile ? extraArgs) profile.extraArgs;
    }
  );
in
otherArguments

// flake-utils.lib.eachSystem supportedSystems (system:
  let
    patchChannel = channel: patches:
      if patches == [ ] then channel else
      (import channel { inherit system; }).pkgs.applyPatches {
        name = "nixpkgs-patched-${channel.shortRev}";
        src = channel;
        patches = patches;
      };

    importChannel = name: value: import (patchChannel value.input (value.patches or [ ])) {
      inherit system;
      overlays = sharedOverlays ++ (if (value ? overlaysBuilder) then (value.overlaysBuilder pkgs) else [ ]);
      config = channelsConfig // (value.config or {});
    };

    pkgs = builtins.mapAttrs importChannel channels;

    optional = check: value: (if check != null then value else { });
  in
  { inherit pkgs; }
  // optional packagesBuilder { packages = packagesBuilder pkgs; }
  // optional defaultPackageBuilder { defaultPackage = defaultPackageBuilder pkgs; }
  // optional appsBuilder { apps = appsBuilder pkgs; }
  // optional defaultAppBuilder { defaultApp = defaultAppBuilder pkgs; }
  // optional devShellBuilder { devShell = devShellBuilder pkgs; }
  // optional checksBuilder { checks = checksBuilder pkgs; }
)

  // {
  nixosConfigurations = nixosConfigurations // (builtins.mapAttrs nixosConfigurationBuilder nixosProfiles);
}

