{
  description = "MeiliSearch development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        # Default configuration values
        defaultConfig = {
          listenAddress = "127.0.0.1";
          listenPort = 7700;
          environment = "development";
          noAnalytics = true;
          logLevel = "INFO";
          maxIndexSize = "107374182400";
          payloadSizeLimit = "104857600";
        };

      in {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              meilisearch
              curl # For API testing
              jq   # For JSON processing
            ];

            shellHook = ''
              export MEILI_DB_PATH="$PWD/.meilisearch"
              export MEILI_HTTP_ADDR="${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}"
              export MEILI_NO_ANALYTICS="${toString defaultConfig.noAnalytics}"
              export MEILI_ENV="${defaultConfig.environment}"
              export MEILI_DUMP_DIR="$PWD/.meilisearch/dumps"
              export MEILI_LOG_LEVEL="${defaultConfig.logLevel}"
              export MEILI_MAX_INDEX_SIZE="${defaultConfig.maxIndexSize}"
              export MEILI_PAYLOAD_SIZE_LIMIT="${defaultConfig.payloadSizeLimit}"

              # Create necessary directories
              mkdir -p "$MEILI_DB_PATH"
              mkdir -p "$MEILI_DUMP_DIR"

              # Function to start MeiliSearch
              start_meilisearch() {
                if [ -f ".env" ]; then
                  source .env
                fi
                
                echo "Starting MeiliSearch..."
                ${pkgs.meilisearch}/bin/meilisearch
              }

              # Function to stop MeiliSearch
              stop_meilisearch() {
                echo "Stopping MeiliSearch..."
                pkill meilisearch || true
              }

              # Function to check MeiliSearch health
              check_health() {
                curl -s http://${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}/health | jq
              }

              # Function to create a backup
              create_dump() {
                if [ -n "$MEILI_MASTER_KEY" ]; then
                  curl \
                    -X POST \
                    -H "Authorization: Bearer $MEILI_MASTER_KEY" \
                    http://${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}/dumps
                else
                  curl \
                    -X POST \
                    http://${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}/dumps
                fi
              }

              echo "MeiliSearch Development Environment"
              echo "===================================="
              echo "Commands available:"
              echo "  start_meilisearch - Start MeiliSearch server"
              echo "  stop_meilisearch  - Stop MeiliSearch server"
              echo "  check_health      - Check MeiliSearch health"
              echo "  create_dump       - Create a backup dump"
              echo ""
              echo "Environment Configuration:"
              echo "  Listen Address: $MEILI_HTTP_ADDR"
              echo "  Database Path: $MEILI_DB_PATH"
              echo "  Environment: $MEILI_ENV"
              echo "  Log Level: $MEILI_LOG_LEVEL"
            '';
          };

          # Production shell with additional security measures
          production = pkgs.mkShell {
            buildInputs = with pkgs; [
              meilisearch
              curl
              jq
            ];

            shellHook = ''
              export MEILI_ENV="production"
              export MEILI_DB_PATH="/var/lib/meilisearch"
              export MEILI_HTTP_ADDR="0.0.0.0:${toString defaultConfig.listenPort}"
              export MEILI_NO_ANALYTICS="true"
              export MEILI_DUMP_DIR="/var/lib/meilisearch/dumps"
              export MEILI_LOG_LEVEL="ERROR"
              export MEILI_MAX_INDEX_SIZE="${defaultConfig.maxIndexSize}"
              export MEILI_PAYLOAD_SIZE_LIMIT="${defaultConfig.payloadSizeLimit}"

              if [ ! -f ".env" ]; then
                echo "Error: .env file with MEILI_MASTER_KEY is required for production"
                exit 1
              fi

              source .env

              start_meilisearch() {
                if [ -z "$MEILI_MASTER_KEY" ]; then
                  echo "Error: MEILI_MASTER_KEY must be set in production"
                  return 1
                }

                echo "Starting MeiliSearch in production mode..."
                ${pkgs.meilisearch}/bin/meilisearch
              }

              check_health() {
                curl -s -H "Authorization: Bearer $MEILI_MASTER_KEY" \
                  http://localhost:${toString defaultConfig.listenPort}/health | jq
              }

              echo "MeiliSearch Production Environment"
              echo "================================="
              echo "Commands available:"
              echo "  start_meilisearch - Start MeiliSearch server"
              echo "  check_health      - Check MeiliSearch health"
              echo ""
              echo "Environment Configuration:"
              echo "  Listen Address: $MEILI_HTTP_ADDR"
              echo "  Environment: $MEILI_ENV"
              echo "  Log Level: $MEILI_LOG_LEVEL"
            '';
          };
        };

        # Package definition
        packages.default = pkgs.stdenv.mkDerivation {
          name = "meilisearch-service";
          version = "1.0.0";
          
          buildInputs = with pkgs; [
            meilisearch
          ];

          dontUnpack = true;

          installPhase = ''
            mkdir -p $out/bin
            
            # Create wrapper script
            cat > $out/bin/meilisearch-server <<EOF
            #!${pkgs.bash}/bin/bash
            
            # Default paths and settings
            export MEILI_DB_PATH="\''${MEILI_DB_PATH:-/var/lib/meilisearch}"
            export MEILI_DUMP_DIR="\''${MEILI_DUMP_DIR:-/var/lib/meilisearch/dumps}"
            export MEILI_HTTP_ADDR="\''${MEILI_HTTP_ADDR:-${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}}"
            export MEILI_ENV="\''${MEILI_ENV:-${defaultConfig.environment}}"
            export MEILI_NO_ANALYTICS="\''${MEILI_NO_ANALYTICS:-${toString defaultConfig.noAnalytics}}"
            export MEILI_LOG_LEVEL="\''${MEILI_LOG_LEVEL:-${defaultConfig.logLevel}}"
            export MEILI_MAX_INDEX_SIZE="\''${MEILI_MAX_INDEX_SIZE:-${defaultConfig.maxIndexSize}}"
            export MEILI_PAYLOAD_SIZE_LIMIT="\''${MEILI_PAYLOAD_SIZE_LIMIT:-${defaultConfig.payloadSizeLimit}}"

            # Load master key from environment file if specified
            if [ -n "\$MEILI_MASTER_KEY_FILE" ] && [ -f "\$MEILI_MASTER_KEY_FILE" ]; then
              source "\$MEILI_MASTER_KEY_FILE"
            fi

            # Create necessary directories
            mkdir -p "\$MEILI_DB_PATH"
            mkdir -p "\$MEILI_DUMP_DIR"

            # Set proper permissions
            chmod 700 "\$MEILI_DB_PATH"
            chmod 700 "\$MEILI_DUMP_DIR"

            # Validate production environment
            if [ "\$MEILI_ENV" = "production" ] && [ -z "\$MEILI_MASTER_KEY" ]; then
              echo "Error: MEILI_MASTER_KEY must be set in production environment"
              exit 1
            fi

            # Start MeiliSearch with proper error handling
            exec ${pkgs.meilisearch}/bin/meilisearch || {
              echo "Error: MeiliSearch failed to start"
              exit 1
            }
            EOF

            chmod +x $out/bin/meilisearch-server

            # Create systemd service file
            mkdir -p $out/lib/systemd/system
            cat > $out/lib/systemd/system/meilisearch.service <<EOF
            [Unit]
            Description=MeiliSearch Search Engine
            After=network.target
            
            [Service]
            Type=simple
            User=meilisearch
            Group=meilisearch
            EnvironmentFile=-/etc/default/meilisearch
            ExecStart=$out/bin/meilisearch-server
            Restart=always
            RestartSec=10
            
            # Security hardening
            NoNewPrivileges=true
            PrivateTmp=true
            PrivateDevices=true
            ProtectSystem=strict
            ProtectHome=true
            ReadWritePaths=/var/lib/meilisearch
            CapabilityBoundingSet=
            AmbientCapabilities=
            SystemCallFilter=@system-service
            SystemCallErrorNumber=EPERM
            
            [Install]
            WantedBy=multi-user.target
            EOF

            # Create default configuration file
            mkdir -p $out/etc/default
            cat > $out/etc/default/meilisearch <<EOF
            # MeiliSearch configuration file
            
            # Server configuration
            MEILI_HTTP_ADDR=${defaultConfig.listenAddress}:${toString defaultConfig.listenPort}
            MEILI_ENV=${defaultConfig.environment}
            MEILI_NO_ANALYTICS=${toString defaultConfig.noAnalytics}
            
            # Data paths
            MEILI_DB_PATH=/var/lib/meilisearch
            MEILI_DUMP_DIR=/var/lib/meilisearch/dumps
            
            # Performance settings
            MEILI_MAX_INDEX_SIZE=${defaultConfig.maxIndexSize}
            MEILI_PAYLOAD_SIZE_LIMIT=${defaultConfig.payloadSizeLimit}
            
            # Logging
            MEILI_LOG_LEVEL=${defaultConfig.logLevel}
            
            # Security (uncomment and set in production)
            #MEILI_MASTER_KEY_FILE=/etc/meilisearch/master.key
            EOF

            # Create documentation
            mkdir -p $out/share/doc/meilisearch
            cat > $out/share/doc/meilisearch/README.md <<EOF
            # MeiliSearch Service

            ## Installation

            1. Copy the systemd service file:
               \`\`\`
               cp $out/lib/systemd/system/meilisearch.service /etc/systemd/system/
               \`\`\`

            2. Copy the default configuration:
               \`\`\`
               cp $out/etc/default/meilisearch /etc/default/
               \`\`\`

            3. Create meilisearch user and group:
               \`\`\`
               useradd -r -s /bin/false meilisearch
               \`\`\`

            4. Create and set permissions for data directory:
               \`\`\`
               mkdir -p /var/lib/meilisearch
               chown -R meilisearch:meilisearch /var/lib/meilisearch
               chmod 700 /var/lib/meilisearch
               \`\`\`

            5. For production, create and configure master key:
               \`\`\`
               mkdir -p /etc/meilisearch
               echo "MEILI_MASTER_KEY=your-secure-key" > /etc/meilisearch/master.key
               chmod 600 /etc/meilisearch/master.key
               chown meilisearch:meilisearch /etc/meilisearch/master.key
               \`\`\`

            6. Enable and start the service:
               \`\`\`
               systemctl daemon-reload
               systemctl enable meilisearch
               systemctl start meilisearch
               \`\`\`

            ## Configuration

            Edit /etc/default/meilisearch to modify the service configuration.

            ## Logs

            View logs with:
            \`\`\`
            journalctl -u meilisearch
            \`\`\`
            EOF
          '';

          meta = with pkgs.lib; {
            description = "Lightning Fast, Ultra Relevant, and Typo-Tolerant Search Engine";
            homepage = "https://www.meilisearch.com";
            license = licenses.mit;
            platforms = platforms.linux;
            maintainers = with maintainers; [ ];
          };
        };

        # Add app definition for easy running
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          name = "meilisearch-server";
        };
      }
    );
}