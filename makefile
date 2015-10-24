MAKEFLAGS += --warn-undefined-variables
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail
.DEFAULT_GOAL := build

TAG?=latest

# run the Docker build
build:
	docker build -t="misterbisson/triton-consul:${TAG}" .

# push our image to the public registry
ship: build
	docker push "misterbisson/triton-consul:${TAG}"

