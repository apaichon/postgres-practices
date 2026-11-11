.DEFAULT_GOAL := slides

MODULE ?= 1
PORT ?= 3031
ARGS ?=

.PHONY: slides start overview slides-install help

slides: slides/node_modules/.package-lock.json
	cd slides && npm run slides:$(MODULE) -- --port $(PORT) $(ARGS)

start: slides

overview:
	$(MAKE) slides MODULE=0

slides-install:
	cd slides && npm ci

slides/node_modules/.package-lock.json: slides/package.json slides/package-lock.json
	cd slides && npm ci

help:
	@echo "make overview                    Open the student SSH and lab prerequisites"
	@echo "make slides                      Start module 1 on port 3031"
	@echo "make slides MODULE=2 PORT=3032    Start another module (0–10)"
	@echo "make slides MODULE=4:clone PORT=3044 Start the isolated security clone lab"
	@echo "make slides MODULE=4:th PORT=3046  Start the imported Thai Pure SQL security deck"
	@echo "make slides MODULE=8:en PORT=3048 Start module 8 in English"
	@echo "make slides ARGS=--open           Open the slides in your browser"
	@echo "make slides-install              Reinstall slide dependencies"
