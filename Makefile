build:
	docker build -t mcfedr/agents .

install:
	ln -s $(shell pwd)/agents /Users/mcfedr/.local/bin/agents
