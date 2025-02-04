GO := go
GO_BUILD = CGO_ENABLED=0 $(GO) build
GO_GENERATE = $(GO) generate
GO_TAGS ?=
TARGET=pwru
INSTALL = $(QUIET)install
BINDIR ?= /usr/local/bin
VERSION=$(shell git describe --tags --always)

TEST_TIMEOUT ?= 5s
RELEASE_UID ?= $(shell id -u)
RELEASE_GID ?= $(shell id -g)

$(TARGET):
	$(GO_GENERATE)
	$(GO_BUILD) $(if $(GO_TAGS),-tags $(GO_TAGS)) \
		-ldflags "-w -s \
		-X 'github.com/cilium/pwru/internal/pwru.Version=${VERSION}'"

release:
	docker run \
		--rm \
		--workdir /pwru \
		--volume `pwd`:/pwru docker.io/library/golang:1.18.3-alpine3.16 \
		sh -c "apk add --no-cache make git clang llvm && \
			addgroup -g $(RELEASE_GID) release && \
			adduser -u $(RELEASE_UID) -D -G release release && \
			su release -c 'make local-release VERSION=${VERSION}'"

local-release: clean
	OS=linux; \
	ARCHS='amd64 arm64'; \
	for ARCH in $$ARCHS; do \
		echo Building release binary for $$OS/$$ARCH...; \
		test -d release/$$OS/$$ARCH|| mkdir -p release/$$OS/$$ARCH; \
		$(GO_GENERATE) main_$$ARCH.go; \
		env GOOS=$$OS GOARCH=$$ARCH $(GO_BUILD) $(if $(GO_TAGS),-tags $(GO_TAGS)) -ldflags "-w -s -X 'github.com/cilium/pwru/internal/pwru.Version=${VERSION}'" -o release/$$OS/$$ARCH/$(TARGET) ; \
		tar -czf release/$(TARGET)-$$OS-$$ARCH.tar.gz -C release/$$OS/$$ARCH $(TARGET); \
		(cd release && sha256sum $(TARGET)-$$OS-$$ARCH.tar.gz > $(TARGET)-$$OS-$$ARCH.tar.gz.sha256sum); \
		rm -r release/$$OS; \
	done; \

install: $(TARGET)
	$(INSTALL) -m 0755 -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -m 0755 $(TARGET) $(DESTDIR)$(BINDIR)

clean:
	rm -f $(TARGET)
	rm -f kprobepwru_bpf*
	rm -f kprobepwruwithoutoutputskb_bpf*
	rm -rf ./release

test:
	$(GO) test -timeout=$(TEST_TIMEOUT) -race -cover $$($(GO) list ./...)

.PHONY: $(TARGET) release local-release install clean test
