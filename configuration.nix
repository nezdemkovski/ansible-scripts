let
  sops-nix = builtins.fetchTarball {
    url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
  };
in
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./sops-key.nix
    "${sops-nix}/modules/sops"
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "nixos";

  networking.useDHCP = false;
  networking.interfaces.ens18.ipv4.addresses = [
    {
      address = "192.168.1.139";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  users.users.root.hashedPassword = "!";
  users.users.yuri = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFKcZEipj5l4bHtQp+fr763qC3XYWMbjil8fzJunwohZ yuri@nezdemkovski.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    git vim curl docker-compose sops age
  ];

  environment.variables.SOPS_AGE_KEY_FILE = "/etc/sops/age/keys.txt";

  systemd.timers.gitops-sync = {
    description = "Run GitOps sync every 1 min";
    wantedBy = [ "multi-user.target" ];
    enable = true;
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      Unit = "gitops-sync.service";
    };
  };

  systemd.services.gitops-sync = 
    let
      gitopsScript = pkgs.writeShellScript "gitops-sync" ''
        set -euo pipefail
        export SOPS_AGE_KEY_FILE="/etc/sops/age/keys.txt"
        
        # Ensure traefik-proxy network exists
        ${pkgs.docker}/bin/docker network create traefik-proxy --driver bridge 2>/dev/null || true
        
        cd /home/yuri
        
        if [ ! -d apps ]; then
          ${pkgs.git}/bin/git clone https://github.com/nezdemkovski/ansible-scripts.git apps
        fi
        
        cd apps
        ${pkgs.git}/bin/git fetch origin master
        ${pkgs.git}/bin/git reset --hard origin/master
        
        for dir in docker/*/; do
          if [ -d "$dir" ]; then
            echo "Processing $dir"
            cd "$dir"
            
            if [ -f ".env.enc" ]; then
              echo "Decrypting .env.enc for $dir"
              ${pkgs.sops}/bin/sops --input-type dotenv --output-type dotenv -d ".env.enc" > ".env.dec"
              chmod 600 ".env.dec"
            elif [ -f ".env" ]; then
              echo "Using existing .env for $dir"
              cp ".env" ".env.dec"
              chmod 600 ".env.dec"
            else
              echo "No .env file found for $dir, skipping"
              cd - > /dev/null
              continue
            fi
            
            if [ -f "docker-compose.yml" ] && [ -f ".env.dec" ]; then
              echo "Starting services for $dir"
              ${pkgs.docker-compose}/bin/docker-compose --env-file .env.dec pull
              ${pkgs.docker-compose}/bin/docker-compose --env-file .env.dec up -d --remove-orphans
            else
              echo "No docker-compose.yml or .env.dec found for $dir"
            fi
            
            cd - > /dev/null
          fi
        done
      '';
    in {
    description = "GitOps repo sync and docker-compose reload";
    after = [ "network-online.target" "docker.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gitopsScript}";
      User = "yuri";
      WorkingDirectory = "/home/yuri";
    };
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = false;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.efi.canTouchEfiVariables = false;

  system.stateVersion = "25.05";
}