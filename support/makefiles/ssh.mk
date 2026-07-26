# ---------------------------------------------------------------------------
# SSH Key Management
# ---------------------------------------------------------------------------
##@ SSH Keys
ssh-generate-rsa: ## Generate an RSA SSH key (4096-bit)
	@echo "🔑 Generating RSA SSH key (4096-bit)..."
	@read -p "📝 Filename (without extension): " filename; \
	if [ -z "$$filename" ]; then \
		echo "❌ Filename required"; exit 1; \
	fi; \
	if [ -f "$$filename" ] || [ -f "$$filename.pub" ]; then \
		echo "⚠️  File already exists. Overwrite? (y/N)"; \
		read -p "> " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Aborted"; exit 1; \
		fi; \
	fi; \
	ssh-keygen -t rsa -b 4096 -f "$$filename" -C "$$(whoami)@$$(hostname)-$$(date +%Y%m%d)"; \
	echo "✅ RSA key generated: $$filename / $$filename.pub"
.PHONY: ssh-generate-rsa

ssh-generate-ed25519: ## Generate an ED25519 SSH key (recommended)
	@echo "🔑 Generating ED25519 SSH key..."
	@read -p "📝 Filename (without extension): " filename; \
	if [ -z "$$filename" ]; then \
		echo "❌ Filename required"; exit 1; \
	fi; \
	if [ -f "$$filename" ] || [ -f "$$filename.pub" ]; then \
		echo "⚠️  File already exists. Overwrite? (y/N)"; \
		read -p "> " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "❌ Aborted"; exit 1; \
		fi; \
	fi; \
	ssh-keygen -t ed25519 -f "$$filename" -C "$$(whoami)@$$(hostname)-$$(date +%Y%m%d)"; \
	echo "✅ ED25519 key generated: $$filename / $$filename.pub"
.PHONY: ssh-generate-ed25519

ssh-show-keys: ## Show all SSH keys
	@echo "🔍 SSH keys in the current directory:"
	@find . -maxdepth 1 -name "*.pub" -exec basename {} \; 2>/dev/null | sort | sed 's/^/  📄 /' || echo "  No .pub files found"
	@echo ""
	@echo "🔐 Keys loaded in the agent:"
	@ssh-add -l 2>/dev/null | sed 's/^/  🔑 /' || echo "  No keys in the SSH agent"
.PHONY: ssh-show-keys

ssh-add-key: ## Add an SSH key to the agent
	@echo "🔍 Available private keys:"
	@find . -maxdepth 1 -type f ! -name "*.pub" -exec sh -c 'file "{}" 2>/dev/null | grep -q "private key" && basename "{}"' \; | sort | sed 's/^/  📄 /' || echo "  No private keys found"
	@read -p "📝 Which key to add? " keyfile; \
	if [ -z "$$keyfile" ]; then \
		echo "❌ No key specified"; exit 1; \
	fi; \
	if [ ! -f "$$keyfile" ]; then \
		echo "❌ File not found: $$keyfile"; exit 1; \
	fi; \
	ssh-add "$$keyfile" && echo "✅ Key added: $$keyfile"
.PHONY: ssh-add-key

ssh-start-agent: ## Start the SSH agent and load keys
	@if [ -z "$$SSH_AUTH_SOCK" ]; then \
		echo "🚀 Starting SSH agent..."; \
		eval $$(ssh-agent -s); \
		echo "SSH_AUTH_SOCK=$$SSH_AUTH_SOCK"; \
		echo "SSH_AGENT_PID=$$SSH_AGENT_PID"; \
	else \
		echo "✅ SSH agent already running"; \
	fi
	@echo "🔑 Loading available keys..."
	@ssh-add 2>/dev/null || echo "⚠️  No default keys found"
.PHONY: ssh-start-agent
