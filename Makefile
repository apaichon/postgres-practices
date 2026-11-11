.DEFAULT_GOAL := slides

MODULE ?= 1
PORT ?= 3031
ARGS ?=
NODE ?= replica2
LAB8 := python3 labs/module08-replication/lab.py
LAB_NO ?= list

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
	@echo "make slides MODULE=5 PORT=3035    Start the source Thai architecture deck"
	@echo "make lab5 LAB_NO=list             List source Module 5 SQL sections"
	@echo "make lab5-setup                   Seed the dedicated architecture_m5_xx DB"
	@echo "make slides MODULE=8 PORT=3048    Start the source Module 8 deck (English)"
	@echo "make slides MODULE=8:th PORT=3048 Start Module 8 in Thai"
	@echo "make up / node-add / node-status Start Lab 8 and add/inspect replica2"
	@echo "make node-down NODE=replica2     Stop a standby for Lab 8C"
	@echo "make node-up NODE=replica2       Resume the standby"
	@echo "make sql-m8 / lab8-wal           Inspect replication / generate WAL"
	@echo "make logical-up / logical-verify Run Lab 8D with a separate subscriber"
	@echo "make pgbouncer / pool-verify     Run Lab 8E with a real app login"
	@echo "make lab8-verify / stop / down    Check replication / stop / keep volumes"
	@echo "make slides ARGS=--open           Open the slides in your browser"
	@echo "make slides-install              Reinstall slide dependencies"

.PHONY: lab5 lab5-setup
lab5:
	python3 labs/module05-architecture/lab.py "$(LAB_NO)"
lab5-setup:
	python3 labs/module05-architecture/lab.py setup

.PHONY: lab8-init lab8-config lab8-pull lab8-verify up stop down status psql replica replica2 \
        node-add node-status node-down node-up sql-m8 lab8-wal logical-up logical-verify \
        subscriber pgbouncer pool-verify

lab8-init:
	$(LAB8) init
lab8-config:
	$(LAB8) config
lab8-pull:
	$(LAB8) pull
lab8-verify:
	$(LAB8) verify
up: lab8-init
	$(LAB8) up
stop:
	$(LAB8) stop
down:
	$(LAB8) down
status node-status:
	$(LAB8) status
psql:
	$(LAB8) psql primary
replica:
	$(LAB8) psql replica
replica2:
	$(LAB8) psql replica2
node-add:
	$(LAB8) node-add
node-down:
	$(LAB8) node-down $(NODE)
node-up:
	$(LAB8) node-up $(NODE)
sql-m8:
	$(LAB8) inspect
lab8-wal:
	$(LAB8) wal
logical-up:
	$(LAB8) logical-up
logical-verify:
	$(LAB8) logical-verify
subscriber:
	$(LAB8) psql subscriber
pgbouncer:
	$(LAB8) pgbouncer
pool-verify:
	$(LAB8) pool-verify
