# Build the Repman image and push it to a private AWS ECR repository.
# Settings come from ecr.env (see ecr.env.dist); any of them can be overridden
# on the command line, e.g. `make push IMAGE_TAG=1.2.3`.

ENV_FILE ?= ecr.env
-include $(ENV_FILE)

AWS_REGION   ?= eu-west-3
IMAGE_TAG    ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo latest)
PLATFORM     ?= linux/amd64

# amazon-ecr-credential-helper (credsStore "ecr-login") fetches tokens itself and
# rejects `docker login` ("not implemented"); it reads the profile from the environment.
export AWS_PROFILE
DOCKER_CONFIG_FILE = $(or $(DOCKER_CONFIG),$(HOME)/.docker)/config.json
ECR_HELPER   = $(shell grep -qs '"credsStore"[[:space:]]*:[[:space:]]*"ecr-login"' $(DOCKER_CONFIG_FILE) && echo yes)

AWS_CLI      = aws $(if $(AWS_PROFILE),--profile $(AWS_PROFILE)) --region $(AWS_REGION)
ECR_REGISTRY = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
IMAGE        = $(ECR_REGISTRY)/$(ECR_REPOSITORY)

.DEFAULT_GOAL := help
.PHONY: help check-env build login push release

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

check-env:
	@test -n "$(AWS_ACCOUNT_ID)" || { echo "AWS_ACCOUNT_ID is not set (create $(ENV_FILE) from ecr.env.dist)"; exit 1; }
	@test -n "$(ECR_REPOSITORY)" || { echo "ECR_REPOSITORY is not set (create $(ENV_FILE) from ecr.env.dist)"; exit 1; }

build: check-env ## Build the image (tagged IMAGE_TAG and latest)
	docker build --platform $(PLATFORM) -t $(IMAGE):$(IMAGE_TAG) -t $(IMAGE):latest .

login: check-env ## Authenticate docker against the private ECR registry
ifeq ($(ECR_HELPER),yes)
	@echo "docker-credential-ecr-login is configured: no login needed, it authenticates on push"
else
	$(AWS_CLI) ecr get-login-password | docker login --username AWS --password-stdin $(ECR_REGISTRY)
endif

push: build login ## Build then push both tags to ECR
	docker push $(IMAGE):$(IMAGE_TAG)
	docker push $(IMAGE):latest

release: push
