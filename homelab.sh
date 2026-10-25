#/bin/bash
# Add Docker's official GPG key:
sudo apt update -y
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -y
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo groupadd docker || true
sudo usermod -aG docker $USER
newgrp docker
mkdir Caddy
mkdir homepage
cd homepage
mkdir config
cd ..
cd Caddy
cat << EOF > caddyfile
{
        # Allows HTTP/HTTPS fallback without breaking on unmanaged hostnames/IPs
        local_certs
}

http://*:8081 {
        # 1. Wide-Open CORS & Global Headers
        header {
                Access-Control-Allow-Origin "*"
                Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
                Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With, X-ND-Authorization, *"
                Access-Control-Expose-Headers "*"

                # Disable frame restrictions so you can embed these if needed
                -X-Frame-Options
                X-Content-Type-Options "nosniff"
        }

        # Instantly reply to CORS preflight OPTIONS requests
        @options {
                method OPTIONS
        }
        respond @options 204

        # 2. Service Routing (Sub-paths)

        # FIX: Portainer needs explicit https:// and self-signed certificate bypass
        handle /home* {
                uri strip_prefix /home
                reverse_proxy homepage:3000 {
                        # FIX: Forces the Host header to be "homepage:3000" instead of "localh>
                        header_up Host homepage:3000
                }
        }

        handle /portainer* {
                uri strip_prefix /portainer
                reverse_proxy https://127.0.0.1:9443 {
                        transport http {
                                tls_insecure_skip_verify
                        }
                }
        }

        handle /navidrome* {
                uri strip_prefix /navidrome
                reverse_proxy 127.0.0.1:4533
        }

        handle /jellyfin* {
                uri strip_prefix /jellyfin
                reverse_proxy 127.0.0.1:8096
        }

        handle /yacht* {
                uri strip_prefix /yacht
                reverse_proxy 127.0.0.1:8000
        }

        # 3. Dedicated Root Path & Catch-All for Homepage assets
        # FIX: Using 'handle' without a path makes it a true catch-all for port 3000
        handle {
                reverse_proxy homepage:3000 {
                        # FIX: Forces the Host header to be "homepage:3000" instead of "localhost:8082"
                        header_up Host homepage:3000
                }
        }
}
EOF
mkdir config
cd ..

docker run -d
--name homepage
-e HOMEPAGE_ALLOWED_HOSTS="*"
-e PUID=1000
-e PGID=1000
-p 3000:3000
-v ./homepage/config:/app/config
-v /var/run/docker.sock:/var/run/docker.sock:ro
--restart unless-stopped
ghcr.io/gethomepage/homepage:latest

# Make Caddy Network
docker network create caddy
docker network connect caddy homepage


docker run -d
--name caddy-proxy
-p 8081:80
-p 443:443
-p 8082:8081
-p 443:443/udp
-v ./Caddy/caddyfile:/etc/caddy/Caddyfile
-v caddy_data:/data
--network caddy
-v ./Caddy/config:/config
--add-host=host.docker.internal:host-gateway
--restart unless-stopped
caddy:latest
