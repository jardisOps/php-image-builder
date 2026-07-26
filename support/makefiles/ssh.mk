# ---------------------------------------------------------------------------
# SSH Key Management
# ---------------------------------------------------------------------------
##@ SSH Keys
ssh-generate-rsa: ## RSA SSH-Schlüssel generieren (4096-bit)
	@echo "🔑 Generiere RSA SSH-Schlüssel (4096-bit)..."
	@read -p "📝 Dateiname (ohne Endung): " filename; \
	if [ -z "$$filename" ]; then \
		echo "❌ Dateiname erforderlich"; exit 1; \
	fi; \
	if [ -f "$$filename" ] || [ -f "$$filename.pub" ]; then \
		echo "⚠️  Datei existiert bereits. Überschreiben? (y/N)"; \
		read -p "> " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Abgebrochen"; exit 1; \
		fi; \
	fi; \
	ssh-keygen -t rsa -b 4096 -f "$$filename" -C "$$(whoami)@$$(hostname)-$$(date +%Y%m%d)"; \
	echo "✅ RSA-Schlüssel generiert: $$filename / $$filename.pub"
.PHONY: ssh-generate-rsa

ssh-generate-ed25519: ## ED25519 SSH-Schlüssel generieren (empfohlen)
	@echo "🔑 Generiere ED25519 SSH-Schlüssel..."
	@read -p "📝 Dateiname (ohne Endung): " filename; \
	if [ -z "$$filename" ]; then \
		echo "❌ Dateiname erforderlich"; exit 1; \
	fi; \
	if [ -f "$$filename" ] || [ -f "$$filename.pub" ]; then \
		echo "⚠️  Datei existiert bereits. Überschreiben? (y/N)"; \
		read -p "> " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Abgebrochen"; exit 1; \
		fi; \
	fi; \
	ssh-keygen -t ed25519 -f "$$filename" -C "$$(whoami)@$$(hostname)-$$(date +%Y%m%d)"; \
	echo "✅ ED25519-Schlüssel generiert: $$filename / $$filename.pub"
.PHONY: ssh-generate-ed25519

ssh-show-keys: ## Alle SSH-Schlüssel anzeigen
	@echo "🔍 SSH-Schlüssel im aktuellen Verzeichnis:"
	@find . -maxdepth 1 -name "*.pub" -exec basename {} \; 2>/dev/null | sort | sed 's/^/  📄 /' || echo "  Keine .pub-Dateien gefunden"
	@echo ""
	@echo "🔐 Geladene SSH-Keys im Agent:"
	@ssh-add -l 2>/dev/null | sed 's/^/  🔑 /' || echo "  Keine Keys im SSH-Agent"
.PHONY: ssh-show-keys

ssh-add-key: ## SSH-Schlüssel zum Agent hinzufügen
	@echo "🔍 Verfügbare private Keys:"
	@find . -maxdepth 1 -type f ! -name "*.pub" -exec sh -c 'file "{}" 2>/dev/null | grep -q "private key" && basename "{}"' \; | sort | sed 's/^/  📄 /' || echo "  Keine private Keys gefunden"
	@read -p "📝 Welchen Key hinzufügen? " keyfile; \
	if [ -z "$$keyfile" ]; then \
		echo "❌ Kein Key angegeben"; exit 1; \
	fi; \
	if [ ! -f "$$keyfile" ]; then \
		echo "❌ Datei nicht gefunden: $$keyfile"; exit 1; \
	fi; \
	ssh-add "$$keyfile" && echo "✅ Key hinzugefügt: $$keyfile"
.PHONY: ssh-add-key

ssh-start-agent: ## SSH-Agent starten und Keys laden
	@if [ -z "$$SSH_AUTH_SOCK" ]; then \
		echo "🚀 Starte SSH-Agent..."; \
		eval $$(ssh-agent -s); \
		echo "SSH_AUTH_SOCK=$$SSH_AUTH_SOCK"; \
		echo "SSH_AGENT_PID=$$SSH_AGENT_PID"; \
	else \
		echo "✅ SSH-Agent läuft bereits"; \
	fi
	@echo "🔑 Lade verfügbare Keys..."
	@ssh-add 2>/dev/null || echo "⚠️  Keine Standard-Keys gefunden"
.PHONY: ssh-start-agent
