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
testImage := $(namespace)/consul-testrunner

## Display this help message
help:
	@awk '/^##.*$$/,/[a-zA-Z_-]+:/' $(MAKEFILE_LIST) | awk '!(NR%2){print $$0p}{p=$$0}' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' | sort


# ------------------------------------------------
# Container builds

## Builds the application container image locally
build: build/tester
	docker build -t=$(image):$(tag) .

## Build the test running container
build/tester:
	docker build -f test/Dockerfile -t=$(testImage):$(tag) .

## Push the current application container images to the Docker Hub
push:
	docker push $(image):$(tag)
	docker push $(testImage):$(tag)

## Tag the current images as 'latest' and push them to the Docker Hub
ship:
	docker tag $(image):$(tag) $(image):latest
	docker tag $(testImage):$(tag) $(testImage):latest
	docker tag $(image):$(tag) $(image):latest
	docker push $(image):$(tag)
	docker push $(image):latest


# ------------------------------------------------
# Test running

## Pull the container images from the Docker Hub
pull:
	docker pull $(image):$(tag)

## Run all integration tests
test: test/compose test/triton

## Run the integration test runner against Compose locally.
test/compose:
	docker run --rm \
		-e TAG=$(tag) \
		-e GIT_BRANCH=$(GIT_BRANCH) \
		--network=bridge \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-w /src \
		$(testImage):$(tag) /src/compose.sh

## Run the integration test runner. Runs locally but targets Triton.
test/triton:
	$(call check_var, TRITON_PROFILE, \
		required to run integration tests on Triton.)
	docker run --rm \
		-e TAG=$(tag) \
		-e TRITON_PROFILE=$(TRITON_PROFILE) \
		-e GIT_BRANCH=$(GIT_BRANCH) \
		-v ~/.ssh:/root/.ssh:ro \
		-v ~/.triton/profiles.d:/root/.triton/profiles.d:ro \
		-w /src \
		$(testImage):$(tag) /src/triton.sh

# runs the integration test above but entirely within your local
# development environment rather than the clean test rig
test/triton/dev:
	./test/triton.sh


# ------------------------------------------------
# Multi-datacenter usage
clean/triton-multi-dc:
	rm -rf examples/triton-multi-dc/_env* examples/triton-multi-dc/docker-compose-*.yml


## Print environment for build debugging
debug:
	@echo GIT_COMMIT=$(GIT_COMMIT)
	@echo GIT_BRANCH=$(GIT_BRANCH)
	@echo namespace=$(namespace)
	@echo tag=$(tag)
	@echo image=$(image)
	@echo testImage=$(testImage)

check_var = $(foreach 1,$1,$(__check_var))
__check_var = $(if $(value $1),,\
	$(error Missing $1 $(if $(value 2),$(strip $2))))
