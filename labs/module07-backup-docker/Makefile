SHELL := /bin/bash
LAB := bash scripts/lab.sh

.PHONY: up status files logical-backup logical-damage logical-restore \
        physical-full physical-change physical-incremental physical-restore \
        pitr globals scheduled stop down clean

up:
	$(LAB) up

status:
	$(LAB) status

files:
	$(LAB) files

logical-backup:
	$(LAB) logical-backup

logical-damage:
	$(LAB) logical-damage

logical-restore:
	$(LAB) logical-restore

physical-full:
	$(LAB) physical-full

physical-change:
	$(LAB) change daily

physical-incremental:
	$(LAB) physical-incremental

physical-restore:
	$(LAB) physical-restore

pitr:
	$(LAB) pitr-demo

globals:
	$(LAB) globals

scheduled:
	bash scripts/scheduled-backup.sh

stop:
	$(LAB) stop

down:
	$(LAB) down

clean:
	$(LAB) clean --yes
