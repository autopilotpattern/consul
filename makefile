# Makefile for shipping and testing the container image.

MAKEFLAGS += --warn-undefined-variables
.DEFAULT_GOAL := build
.PHONY: *

# we get these from CI environment if available, otherwise from git
GIT_COMMIT ?= $(shell git rev-parse --short HEAD)
GIT_BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

namespace ?= autopilotpattern
tag := branch-$(shell basename $(GIT_BRANCH))
image := $(namespace)/consul
test_image := $(namespace)/consul-testrunner

dockerLocal := DOCKER_HOST= DOCKER_TLS_VERIFY= DOCKER_CERT_PATH= docker

## Display this help message
help:
	@awk '/^##.*$$/,/[a-zA-Z_-]+:/' $(MAKEFILE_LIST) | awk '!(NR%2){print $$0p}{p=$$0}' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' | sort


# ------------------------------------------------
# Container builds

## Builds the application container image locally
build: test-runner
	$(dockerLocal) build -t=$(image):$(tag) .

## Build the test running container
test-runner:
	$(dockerLocal) build -f test/Dockerfile -t=$(test_image):$(tag) .

## Push the current application container images to the Docker Hub
push:
	$(dockerLocal) push $(image):$(tag)
	$(dockerLocal) push $(test_image):$(tag)

## Tag the current images as 'latest' and push them to the Docker Hub
ship:
	$(dockerLocal) tag $(image):$(tag) $(image):latest
	$(dockerLocal) tag $(test_image):$(tag) $(test_image):latest
	$(dockerLocal) tag $(image):$(tag) $(image):latest
	$(dockerLocal) push $(image):$(tag)
	$(dockerLocal) push $(image):latest



# ------------------------------------------------
# Test running

## Pull the container images from the Docker Hub
pull:
	docker pull $(image):$(tag)
	docker pull $(test_image):$(tag)

$(DOCKER_CERT_PATH)/key.pub:
	ssh-keygen -y -f $(DOCKER_CERT_PATH)/key.pem > $(DOCKER_CERT_PATH)/key.pub

# For Jenkins test runner only: make sure we have public keys available
SDC_KEYS_VOL ?= -v $(DOCKER_CERT_PATH):$(DOCKER_CERT_PATH)
keys: $(DOCKER_CERT_PATH)/key.pub

## Run the integration test runner. Runs locally but targets Triton.
test:
	$(call check_var, TRITON_ACCOUNT TRITON_DC, \
		required to run integration tests on Triton.)
	$(dockerLocal) run --rm \
		-e TAG=$(tag) \
		-e COMPOSE_HTTP_TIMEOUT=300 \
		-e DOCKER_HOST=$(DOCKER_HOST) \
		-e DOCKER_TLS_VERIFY=1 \
		-e DOCKER_CERT_PATH=$(DOCKER_CERT_PATH) \
		-e CONSUL=consul.svc.$(TRITON_ACCOUNT).$(TRITON_DC).cns.joyent.com \
		$(SDC_KEYS_VOL) -w /src \
		$(test_image):$(tag) python3 tests.py

## Print environment for build debugging
debug:
	@echo GIT_COMMIT=$(GIT_COMMIT)
	@echo GIT_BRANCH=$(GIT_BRANCH)
	@echo namespace=$(namespace)
	@echo tag=$(tag)
	@echo image=$(image)
	@echo test_image=$(test_image)

check_var = $(foreach 1,$1,$(__check_var))
__check_var = $(if $(value $1),,\
	$(error Missing $1 $(if $(value 2),$(strip $2))))
