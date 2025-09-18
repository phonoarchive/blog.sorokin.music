# Static Blog Generator Makefile
# Configuration
MARKDOWN := smu
BUILD_DIR := build
POSTS_DIR := posts
PAGES_DIR := pages

# Source files
POSTS_MD := $(wildcard $(POSTS_DIR)/*.md)
PAGES_MD := $(wildcard $(PAGES_DIR)/*.md)
ALL_MD := $(POSTS_MD) $(PAGES_MD)

# Generated files
POSTS_HTML := $(patsubst $(POSTS_DIR)/%.md,$(BUILD_DIR)/%.html,$(POSTS_MD))
PAGES_HTML := $(patsubst $(PAGES_DIR)/%.md,$(BUILD_DIR)/%.html,$(PAGES_MD))
POSTS_GMI := $(patsubst $(POSTS_DIR)/%.md,$(BUILD_DIR)/%.gmi,$(POSTS_MD))
PAGES_GMI := $(patsubst $(PAGES_DIR)/%.md,$(BUILD_DIR)/%.gmi,$(PAGES_MD))

# Main targets
.PHONY: all clean dev production help

all: production

production: $(BUILD_DIR) $(BUILD_DIR)/index.html $(BUILD_DIR)/atom.xml $(POSTS_HTML) $(PAGES_HTML) $(POSTS_GMI) $(PAGES_GMI)

dev: $(BUILD_DIR) $(BUILD_DIR)/index-with-drafts.html $(BUILD_DIR)/atom.xml $(POSTS_HTML) $(PAGES_HTML) $(POSTS_GMI) $(PAGES_GMI)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Generate TSV index files
$(BUILD_DIR)/posts.tsv: $(POSTS_MD) | $(BUILD_DIR)
	@echo "Generating posts index..."
	@for f in $(POSTS_DIR)/*.md; do \
		if [ -f "$$f" ]; then \
			created=$$(git log --pretty='format:%aI' "$$f" 2>/dev/null | tail -1); \
			updated=$$(git log --pretty='format:%aI' "$$f" 2>/dev/null | head -1); \
			title=$$(sed -n '/^# /{s/# //p; q}' "$$f"); \
			printf '%s\t%s\t%s\t%s\n' "$$f" "$${title:=No Title}" "$${created:=draft}" "$${updated:=draft}"; \
		fi; \
	done | sort -rt "	" -k 3 > $@

$(BUILD_DIR)/pages.tsv: $(PAGES_MD) | $(BUILD_DIR)
	@echo "Generating pages index..."
	@for f in $(PAGES_DIR)/*.md; do \
		if [ -f "$$f" ]; then \
			created=$$(git log --pretty='format:%aI' "$$f" 2>/dev/null | tail -1); \
			updated=$$(git log --pretty='format:%aI' "$$f" 2>/dev/null | head -1); \
			title=$$(sed -n '/^# /{s/# //p; q}' "$$f"); \
			printf '%s\t%s\t%s\t%s\n' "$$f" "$${title:=No Title}" "$${created:=draft}" "$${updated:=draft}"; \
		fi; \
	done > $@

# Generate index pages
$(BUILD_DIR)/index.html: $(BUILD_DIR)/posts.tsv index.md header.html
	@echo "Generating main index..."
	@( \
		title=$$(sed -n '/^# /{s/# //p; q}' index.md); \
		sed "s/{{TITLE}}/$$title/" header.html; \
		$(MARKDOWN) index.md; \
		while IFS='	' read -r f title created updated; do \
			if [ "$$created" != "draft" ]; then \
				link=$$(echo "$$f" | sed -E 's|.*/(.*).md|\1.html|'); \
				created=$$(echo "$$created" | sed -E 's/T.*//'); \
				echo "$$created &mdash; <a href=\"$$link\">$$title</a><br/>"; \
			fi; \
		done < $< \
	) > $@

$(BUILD_DIR)/index-with-drafts.html: $(BUILD_DIR)/posts.tsv index.md header.html
	@echo "Generating index with drafts..."
	@( \
		title=$$(sed -n '/^# /{s/# //p; q}' index.md); \
		sed "s/{{TITLE}}/$$title/" header.html; \
		$(MARKDOWN) index.md; \
		while IFS='	' read -r f title created updated; do \
			link=$$(echo "$$f" | sed -E 's|.*/(.*).md|\1.html|'); \
			created=$$(echo "$$created" | sed -E 's/T.*//'); \
			echo "$$created &mdash; <a href=\"$$link\">$$title</a><br/>"; \
		done < $< \
	) > $@

$(BUILD_DIR)/index.gmi: $(BUILD_DIR)/posts.tsv index.md $(PAGES_DIR)/projects.md
	@echo "Generating Gemini index..."
	@( \
		if command -v md2gemini >/dev/null 2>&1; then \
			<index.md perl -0pe 's/<a href="([^"]*)".*>(.*)<\/a>/[\2](\1)/g;s/^<!--.*-->//gsm' | md2gemini --links paragraph; \
		else \
			echo "# $$(sed -n '/^# /{s/# //p; q}' index.md)"; \
			echo ""; \
		fi; \
		while IFS='	' read -r f title created updated; do \
			if [ "$$created" != "draft" ]; then \
				link=$$(echo "$$f" | sed -E 's|.*/(.*).md|\1.gmi|'); \
				created=$$(echo "$$created" | sed -E 's/T.*//'); \
				echo "=> $$link $$created - $$title"; \
			fi; \
		done < $<; \
		if command -v md2gemini >/dev/null 2>&1 && [ -f "$(PAGES_DIR)/projects.md" ]; then \
			<$(PAGES_DIR)/projects.md perl -0pe 's/<a href="([^"]*)".*>(.*)<\/a>/[\2](\1)/g;s/^<!--.*-->//gsm' | md2gemini --links paragraph; \
		fi \
	) > $@

# Generate Atom feed
$(BUILD_DIR)/atom.xml: $(BUILD_DIR)/posts.tsv header.html index.md
	@echo "Generating Atom feed..."
	@( \
		uri=$$(sed -rn '/atom.xml/ s/.*href="([^"]*)".*/\1/ p' header.html); \
		host=$$(echo "$$uri" | sed -r 's|.*//([^/]+).*|\1|'); \
		first_commit_date=$$(git log --pretty='format:%ai' . | cut -d ' ' -f1 | tail -1); \
		echo '<?xml version="1.0" encoding="utf-8"?>'; \
		echo '<feed xmlns="http://www.w3.org/2005/Atom">'; \
		echo "	<title>$$(sed -n '/^# /{s/# //p; q}' index.md)</title>"; \
		echo "	<link href=\"$$uri\" rel=\"self\" />"; \
		echo "	<updated>$$(date --iso=seconds)</updated>"; \
		echo "	<author>"; \
		echo "		<name>$$(git config user.name)</name>"; \
		echo "	</author>"; \
		echo "	<id>tag:$$host,$$first_commit_date:default-atom-feed</id>"; \
		while IFS='	' read -r f title created updated; do \
			if [ "$$created" != "draft" ]; then \
				day=$$(echo "$$created" | sed 's/T.*//'); \
				content=$$($(MARKDOWN) "$$f" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'\''/\&#39;/g'); \
				link=$$(echo "$$f" | sed -E 's|posts/(.*).md|\1.html|'); \
				echo "	<entry>"; \
				echo "		<title>$$title</title>"; \
				echo "		<content type=\"html\">$$content</content>"; \
				echo "		<link href=\"$$link\"/>"; \
				echo "		<id>tag:$$host,$$day:$$f</id>"; \
				echo "		<published>$$created</published>"; \
				echo "		<updated>$$updated</updated>"; \
				echo "	</entry>"; \
			fi; \
		done < $<; \
		echo '</feed>' \
	) > $@

# Generate HTML pages from posts
$(BUILD_DIR)/%.html: $(POSTS_DIR)/%.md header.html $(BUILD_DIR)/posts.tsv
	@echo "Generating $@..."
	@f="$<"; \
	target="$@"; \
	title=$$(sed -n '/^# /{s/# //p; q}' "$$f"); \
	created=$$(grep "$$f	" $(BUILD_DIR)/posts.tsv | cut -f3 | sed 's/T.*//'); \
	updated=$$(grep "$$f	" $(BUILD_DIR)/posts.tsv | cut -f4 | sed 's/T.*//'); \
	dates_text="Written on $$created."; \
	if [ "$$created" != "$$updated" ]; then \
		dates_text="$$dates_text Last updated on $$updated."; \
	fi; \
	page_url=$$(echo "$$f" | sed -E 's|.*/(.*).md|/\1|'); \
	content=$$($(MARKDOWN) "$$f" | sed "$ a <small>$$dates_text</small>"); \
	content="$$content"'<style>.isso-comment.isso-is-page-author > .isso-text-wrapper {background-color: #bae0ea;} .isso-comment.isso-is-page-author > .isso-text-wrapper > .isso-comment-header > .isso-author {color: #19798d;} .isso-comment.isso-is-page-author .isso-avatar img {box-shadow: 0 0 12px #ff6b6b; border-radius: 50%;}</style><section id="isso-thread" data-isso-id="'"$$page_url"'" data-title="'"$$title"'"></section><script data-isso="https://comments.sorokin.music" data-isso-page-author-hashes="ff0c0ae5337923403aad2449bccdfc47, 92264c714dff" src="https://comments.sorokin.music/js/embed.min.js" async="async"></script>'; \
	printf '%s\n' "$$content" | cat header.html - | sed "s/{{TITLE}}/$$title/" > "$$target"

# Generate HTML pages from pages (without comments, simpler date handling)
$(BUILD_DIR)/%.html: $(PAGES_DIR)/%.md header.html $(BUILD_DIR)/pages.tsv
	@echo "Generating $@..."
	@f="$<"; \
	target="$@"; \
	title=$(sed -n '/^# /{s/# //p; q}' "$f"); \
	created=$(grep "$f	" $(BUILD_DIR)/pages.tsv | cut -f3 | sed 's/T.*//'); \
	updated=$(grep "$f	" $(BUILD_DIR)/pages.tsv | cut -f4 | sed 's/T.*//'); \
	if [ "$created" != "draft" ] && [ "$updated" != "draft" ]; then \
		if [ "$created" != "$updated" ]; then \
			dates_text="Last updated on $updated."; \
		else \
			dates_text="Created on $created."; \
		fi; \
		content=$($(MARKDOWN) "$f" | sed "$ a <small>$dates_text</small>"); \
	else \
		content=$($(MARKDOWN) "$f"); \
	fi; \
	printf '%s\n' "$content" | cat header.html - | sed "s/{{TITLE}}/$title/" > "$target"

# Generate Gemini pages from posts
$(BUILD_DIR)/%.gmi: $(POSTS_DIR)/%.md $(BUILD_DIR)/posts.tsv
	@echo "Generating Gemini $@..."
	@f="$<"; \
	created=$$(grep "$$f	" $(BUILD_DIR)/posts.tsv | cut -f3 | sed 's/T.*//'); \
	updated=$$(grep "$$f	" $(BUILD_DIR)/posts.tsv | cut -f4 | sed 's/T.*//'); \
	dates_text="Written on $$created."; \
	if [ "$$created" != "$$updated" ]; then \
		dates_text="$$dates_text Last updated on $$updated."; \
	fi; \
	if command -v md2gemini >/dev/null 2>&1; then \
		<"$$f" perl -0pe 's/<a href="([^"]*)".*>(.*)<\/a>/[\2](\1)/g;s/^<!--.*-->//gsm' | md2gemini --links paragraph | sed "$ s/$$/\\n\\n$$dates_text/" > $@; \
	else \
		echo "# $$(sed -n '/^# /{s/# //p; q}' "$$f")" > $@; \
		echo "" >> $@; \
		echo "$$dates_text" >> $@; \
	fi

# Generate Gemini pages from pages (simpler date handling)
$(BUILD_DIR)/%.gmi: $(PAGES_DIR)/%.md $(BUILD_DIR)/pages.tsv
	@echo "Generating Gemini $@..."
	@f="$<"; \
	created=$(grep "$f	" $(BUILD_DIR)/pages.tsv | cut -f3 | sed 's/T.*//'); \
	updated=$(grep "$f	" $(BUILD_DIR)/pages.tsv | cut -f4 | sed 's/T.*//'); \
	if command -v md2gemini >/dev/null 2>&1; then \
		if [ "$created" != "draft" ] && [ "$updated" != "draft" ]; then \
			if [ "$created" != "$updated" ]; then \
				dates_text="Last updated on $updated."; \
			else \
				dates_text="Created on $created."; \
			fi; \
			<"$f" perl -0pe 's/<a href="([^"]*)".*>(.*)<\/a>/[\2](\1)/g;s/^<!--.*-->//gsm' | md2gemini --links paragraph | sed "$ s/$/\\n\\n$dates_text/" > $@; \
		else \
			<"$f" perl -0pe 's/<a href="([^"]*)".*>(.*)<\/a>/[\2](\1)/g;s/^<!--.*-->//gsm' | md2gemini --links paragraph > $@; \
		fi; \
	else \
		echo "# $(sed -n '/^# /{s/# //p; q}' "$f")" > $@; \
		if [ "$created" != "draft" ] && [ "$updated" != "draft" ]; then \
			echo "" >> $@; \
			if [ "$created" != "$updated" ]; then \
				echo "Last updated on $updated." >> $@; \
			else \
				echo "Created on $created." >> $@; \
			fi; \
		fi; \
	fi

# Development server (requires Python)
.PHONY: serve
serve: dev
	@echo "Starting development server at http://localhost:8000"
	@cd $(BUILD_DIR) && python3 -m http.server 8000

# Watch for changes (requires inotify-tools)
.PHONY: watch
watch:
	@echo "Watching for changes..."
	@while inotifywait -r -e modify,create,delete $(POSTS_DIR) $(PAGES_DIR) header.html index.md 2>/dev/null; do \
		echo "Changes detected, rebuilding..."; \
		$(MAKE) --no-print-directory dev; \
	done

# Clean build directory
clean:
	rm -rf $(BUILD_DIR)

# Deploy to nginx folder
.PHONY: deploy
deploy: production
	@echo "Deploying to /var/www/blog.sorokin.music..."
	@sudo rsync -av --delete $(BUILD_DIR)/ /var/www/blog.sorokin.music/
	@sudo chown -R www-data:www-data /var/www/blog.sorokin.music/
	@echo "Deployment complete!"

# Git operations
.PHONY: commit push publish status
status:
	@echo "Git status:"
	@git status --porcelain

commit: status
	@if git diff --quiet && git diff --staged --quiet; then \
		echo "No changes to commit."; \
	else \
		echo "Committing changes..."; \
		git add .; \
		if [ -n "$(MSG)" ]; then \
			git commit -m "$(MSG)"; \
		else \
			echo "Please provide a commit message: make commit MSG=\"your message\""; \
			exit 1; \
		fi; \
	fi

push: commit
	@echo "Pushing to remote repository..."
	@if git remote | grep -q .; then \
		if git push 2>/dev/null; then \
			echo "Push successful!"; \
		else \
			echo "Setting upstream and pushing..."; \
			git push --set-upstream origin $(git branch --show-current); \
		fi; \
	else \
		echo "No remote repository configured. Skipping push."; \
		echo "To configure: git remote add origin <your-repo-url>"; \
	fi

# Full publish workflow: build, commit, push, deploy
publish: clean production commit push deploy
	@echo "Published successfully!"

# Help
help:
	@echo "Static Blog Generator Makefile"
	@echo ""
	@echo "Build Targets:"
	@echo "  all/production  Build production site (hide drafts)"
	@echo "  dev             Build development site (show drafts)"
	@echo "  clean           Remove build directory"
	@echo ""
	@echo "Development Targets:"
	@echo "  serve           Start development server on port 8000"
	@echo "  watch           Watch for changes and rebuild automatically"
	@echo ""
	@echo "Git & Deployment:"
	@echo "  status          Show git status"
	@echo "  commit          Commit changes (use: make commit MSG=\"message\")"
	@echo "  push            Commit and push to remote"
	@echo "  deploy          Deploy to /var/www/blog.sorokin.music"
	@echo "  publish         Full workflow: clean, build, commit, push, deploy"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make commit MSG=\"Add new post about X\""
	@echo "  make publish MSG=\"Update blog with latest changes\""
	@echo ""
	@echo "Files:"
	@echo "  Posts:    $(POSTS_DIR)/*.md"
	@echo "  Pages:    $(PAGES_DIR)/*.md"
	@echo "  Output:   $(BUILD_DIR)/"
	@echo "  Deploy:   /var/www/blog.sorokin.music/"
