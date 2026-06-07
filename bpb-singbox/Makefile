CGO_ENABLED=0

up:
	COMPOSE_BAKE=true docker compose up -d --remove-orphans

logs:
	docker compose logs -f

down:
	docker compose down

edit-compose:
	nvim docker-compose.yaml

ps:
	docker compose ps

upload:
	scp -r biba-serv2/ pet:projects/

.PHONY: build
build:
	 go build -tags netgo,osusergo --ldflags '-s -w -extldflags "-static"' -v -o build/package/biba-serv2 cmd/biba-serv2-bytes-slice/main.go