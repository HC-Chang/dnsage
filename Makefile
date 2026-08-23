.PHONY: all test st pi-hole clean setup

all: pi-hole

test:
	dig +short doubleclick.net
st:
	cat /etc/resolv.conf
	
pi-hole:
	sudo resolvectl dns wlp195s0 127.0.0.1
	$(MAKE) test

clean:
	sudo resolvectl dns wlp195s0 192.168.1.1
	$(MAKE) test

setup:
	@echo "==> DNSage Setup"
	@echo ""
	@echo "1) Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 || { echo "   [✗] docker not found"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "   [✗] docker compose not found"; exit 1; }
	@echo "   [✓] Docker + Docker Compose"
	@echo ""
	@echo "2) Creating .env from .env.example..."
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		PIHOLE_PASS=$$(openssl rand -hex 16); \
		POSTGRES_PASS=$$(openssl rand -hex 16); \
		JWT_SECRET=$$(openssl rand -hex 32); \
		ADMIN_PASS=$$(openssl rand -hex 16); \
		sed -i "s/^PIHOLE_PASSWORD=.*/PIHOLE_PASSWORD=$$PIHOLE_PASS/" .env; \
		sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$$POSTGRES_PASS/" .env; \
		sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$$JWT_SECRET/" .env; \
		sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$$ADMIN_PASS/" .env; \
		echo "   [✓] .env created with auto-generated secrets"; \
	else \
		echo "   [ ] .env already exists, skipping"; \
	fi
	@echo ""
	@echo "3) Checking Ollama external network..."
	@docker network inspect ollama_ollama-docker >/dev/null 2>&1 || { \
		echo "   Creating ollama_ollama-docker network..."; \
		docker network create ollama_ollama-docker; \
	}
	@echo "   [✓] Ollama network ready"
	@echo ""
	@echo "4) Checking Ollama models..."
	@docker exec ollama ollama list 2>/dev/null | grep -q "llama3.2" || echo "   [ ] llama3.2 not pulled"
	@docker exec ollama ollama list 2>/dev/null | grep -q "all-minilm" || echo "   [ ] all-minilm:33m not pulled"
	@echo ""
	@echo "5) Initializing submodules..."
	@git submodule update --init --recursive 2>/dev/null || echo "   [ ] git not available or no submodules"
	@echo "   [✓] Submodules ready"
	@echo ""
	@echo "6) Starting services..."
	@docker compose up -d
	@echo ""
	@echo "7) Service status:"
	@docker compose ps
	@echo ""
	@echo "==> Setup complete!"
	@echo ""
	@echo "  Donut-Hole UI: https://$$(grep '^DOMAIN=' .env | cut -d= -f2-)/"
	@echo "  Pi-hole Admin: https://$$(grep '^PIHOLE_DOMAIN=' .env | cut -d= -f2-)/admin/"
	@echo ""
	@grep -E "^(ADMIN_USERNAME|PIHOLE_PASSWORD)" .env
