# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.3)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.3)
VERSION ?= main
# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
#IMAGE_TAG_BASE ?= docker.io/layer7api/layer7-operator
ARTIFACT_HOST ?= docker.io
IMAGE_TAG ?= layer7api/layer7-operator
IMAGE_TAG_BASE ?= $(ARTIFACT_HOST)/$(IMAGE_TAG)

CREATED ?= $(shell echo `date`)
YEAR ?= $(shell echo `date +%Y`)
AUTHOR ?= "layer7"
COPYRIGHT ?= Copyright © ${YEAR} Broadcom Inc. and/or its subsidiaries. All Rights Reserved.

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# Helmify generates a Helm Chart from Kustomize output
HELMIFY = $(shell pwd)/bin/helmify
# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.33.0
# Image URL to use all building/pushing image targets
#IMG ?= docker.io/layer7api/layer7-operator:v$(VERSION)
IMG ?= $(IMAGE_TAG_BASE):$(VERSION)
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.30.0

START_KIND_CLUSTER ?= true

KUBE_VERSION ?= 1.30
KIND_CONFIG ?= kind-$(KUBE_VERSION).yaml

GATEWAY_IMG ?= docker.io/caapim/gateway:11.1.2
GO_BUILD_IMG ?= golang:1.23
DISTROLESS_IMG ?= gcr.io/distroless/static:nonroot
GO_PROXY ?= ""

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
#$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd:generateEmbeddedObjectMeta=true,maxDescLen=75 webhook paths="./..." output:crd:artifacts:config=config/crd/bases


.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test -vet=off -v -timeout 1000s ./... -coverprofile cover.out

GOLANGCI_LINT = $(shell pwd)/bin/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.54.2
golangci-lint:
	@[ -f $(GOLANGCI_LINT) ] || { \
	set -e ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell dirname $(GOLANGCI_LINT)) $(GOLANGCI_LINT_VERSION) ;\
	}

.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter & yamllint
	$(GOLANGCI_LINT) run

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fix

# end-to-tests
.PHONY: e2e
e2e:
	$(KUTTL) test

.PHONY: prepare-e2e
prepare-e2e: kuttl docker-build start-kind
	kubectl create namespace l7operator
	kind load docker-image $(IMG)
	docker pull ${GATEWAY_IMG}
	kind load docker-image $(GATEWAY_IMG)
	sed -i 's+docker.io/layer7api/layer7-operator:main+$(IMG)+g' deploy/bundle.yaml
	kubectl apply -f deploy/bundle.yaml --namespace l7operator
	kubectl create secret generic gateway-license --from-file=./testdata/license.xml --namespace l7operator
	kubectl apply -f ./testdata/metallb-native.yaml
	sleep 15s
	kubectl wait --for=condition=ready --timeout=600s pod -l component=controller -n metallb-system
	kubectl wait --for=condition=ready --timeout=600s pod -l component=speaker -n metallb-system
	
	kubectl apply -f ./testdata/metallb.yaml

.PHONY: start-kind
start-kind:
ifeq (true,$(START_KIND_CLUSTER))
	kind create cluster --config $(KIND_CONFIG)
endif

.PHONY: kuttl
kuttl:
ifeq (, $(shell which kubectl-kuttl))
	which kubectl-kuttl

	@{ \
	set -e ;\
	echo "" ;\
	echo "ERROR: kuttl not found." ;\
	echo "Please check https://kuttl.dev/docs/cli.html for installation instructions and try again." ;\
	echo "" ;\
	exit 1 ;\
	}
else
KUTTL=$(shell which kubectl-kuttl)
endif

.PHONY: kind
kind:
ifeq (, $(shell which kind))
	@{ \
	set -e ;\
	echo "" ;\
	echo "ERROR: kind not found." ;\
	echo "Please check https://kind.sigs.k8s.io/docs/user/quick-start/#installation for installation instructions and try again." ;\
	echo "" ;\
	exit 1 ;\
	}
else
KIND=$(shell which kind)
endif

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go --zap-log-level=10

.PHONY: docker-build
docker-build: dockerfile #test ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -f operator.Dockerfile -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

.PHONY: docker-build-push
docker-build-push: dockerfile #test ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} -f operator.Dockerfile --push --build-arg COPYRIGHT="${COPYRIGHT}" --build-arg AUTHOR="layer7" --build-arg TITLE="layer7-operator" --build-arg VERSION="${IMAGE_TAG}" --build-arg CREATED="${CREATED}"  .

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64
.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the manager for cross-platform support
# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > cross.Dockerfile
	- $(CONTAINER_TOOL) buildx create --name xplatform-builder
	$(CONTAINER_TOOL) buildx use xplatform-builder
	- $(CONTAINER_TOOL) buildx build  --platform=$(PLATFORMS) --tag ${IMG} -f cross.Dockerfile --build-arg COPYRIGHT="${COPYRIGHT}" --build-arg VERSION="${IMAGE_TAG}" --build-arg CREATED="${CREATED}"  . --push
	- $(CONTAINER_TOOL) buildx rm xplatform-builder

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: generate-deployment
generate-deployment: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd > deploy/crd.yaml
	$(KUSTOMIZE) build config/rbac > deploy/rbac.yaml
	$(KUSTOMIZE) build config/samples > deploy/gateway.yaml
	$(KUSTOMIZE) build config/operator > deploy/operator.yaml

.PHONY: generate-cw-deployment
generate-cw-deployment: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd > deploy/crd.yaml
	$(KUSTOMIZE) build config/cw-rbac > deploy/cw-rbac.yaml
	$(KUSTOMIZE) build config/samples > deploy/gateway.yaml
	$(KUSTOMIZE) build config/cw-operator > deploy/cw-operator.yaml

.PHONY: generate-deployment-bundle
generate-deployment-bundle: manifests kustomize
	$(KUSTOMIZE) build config/bundle > deploy/bundle.yaml

.PHONY: generate-cw-deployment-bundle
generate-cw-deployment-bundle: manifests kustomize
	$(KUSTOMIZE) build config/cw-bundle > deploy/cw-bundle.yaml

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v5.4.2
CONTROLLER_TOOLS_VERSION ?= v0.16.5

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@release-0.20

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests --interactive=false -q
	cd config/cw-operator && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: opm
OPM = ./bin/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

version:
	sed -i "s~newName:.*~newName: ${IMAGE_TAG_BASE}~g" config/operator/kustomization.yaml
	sed -i "s~newName:.*~newName: ${IMAGE_TAG_BASE}~g" config/cw-operator/kustomization.yaml
	sed -i "s~newName:.*~newName: ${IMAGE_TAG_BASE}~g" config/bundle/kustomization.yaml
	sed -i "s~newTag:.*~newTag: ${VERSION}~g" config/operator/kustomization.yaml
	sed -i "s~newTag:.*~newTag: ${VERSION}~g" config/cw-operator/kustomization.yaml
	sed -i "s~newTag:.*~newTag: ${VERSION}~g" config/bundle/kustomization.yaml

.PHONY: dockerfile
dockerfile:
	cat Dockerfile | sed -e "s~DISTROLESS_IMG~${DISTROLESS_IMG}~g" | sed -e "s~GO_BUILD_IMG~${GO_BUILD_IMG}~g" > operator.Dockerfile

generate-docs: controller-gen
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=./tmp/crd/bases
	crdoc --resources ./tmp/crd/bases/security.brcmlabs.com_gateways.yaml --output docs/gateway.md
	crdoc --resources ./tmp/crd/bases/security.brcmlabs.com_repositories.yaml --output docs/repository.md
	crdoc --resources ./tmp/crd/bases/security.brcmlabs.com_l7portals.yaml --output docs/l7portals.md
	crdoc --resources ./tmp/crd/bases/security.brcmlabs.com_l7apis.yaml --output docs/l7apis.md
	crdoc --resources ./tmp/crd/bases/security.brcmlabs.com_l7statestores.yaml --output docs/l7statestores.md
	rm -r ./tmp/

helmify:
#$(call go-get-tool,$(HELMIFY),github.com/arttor/helmify/cmd/helmify@v0.3.7)
	test -s $(LOCALBIN)/helmify || GOBIN=$(LOCALBIN) go install github.com/arttor/helmify/cmd/helmify@v0.4.10


helm: manifests kustomize helmify
	$(KUSTOMIZE) build config/cw-bundle | $(HELMIFY) -crd-dir charts/layer7-operator