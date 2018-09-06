NAME := gokeyless
VENDOR := "Cloudflare"
LICENSE := "See License File"
URL := "https://github.com/cloudflare/gokeyless"
DESCRIPTION="A Go implementation of the keyless server protocol"
VERSION := $(shell git describe --tags --always --dirty=-dev)
LDFLAGS := "-X main.version=$(VERSION)"

DESTDIR                      := build
PREFIX                       := usr/local
INSTALL_BIN                  := $(DESTDIR)/$(PREFIX)/bin
INIT_PREFIX                  := $(DESTDIR)/etc/init.d
SYSTEMD_PREFIX               := $(DESTDIR)/lib/systemd/system
CONFIG_PATH                  := etc/keyless
CONFIG_PREFIX                := $(DESTDIR)/$(CONFIG_PATH)

GO ?= go
OS ?= linux
ARCH ?= amd64
DEB_PACKAGE := $(NAME)_$(VERSION)_$(ARCH).deb
RPM_PACKAGE := $(NAME)-$(VERSION).$(ARCH).rpm

TRIS_REV    := "2fd37b550fe5873c1eb39c3aa3564379bce6e751"
TRIS_URL    := "https://github.com/cloudflare/tls-tris/archive/$(TRIS_REV).zip"
TRIS_DIR    := vendor/github.com/cloudflare/tls-tris
TRIS_GOROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/$(TRIS_DIR)/_dev/GOROOT/$(OS)_$(ARCH)
TRIS        := $(TRIS_GOROOT)/.ok_$(shell go version  | cut -d' ' -f3)_$(OS)_$(ARCH)
GO_TRIS     := GOROOT=$(TRIS_GOROOT) $(GO)

.PHONY: all
all: $(DEB_PACKAGE) $(RPM_PACKAGE)

.PHONY: install-config
install-config:
	@mkdir -p $(INSTALL_BIN)
	@mkdir -p $(CONFIG_PREFIX)/keys
	@chmod 700 $(CONFIG_PREFIX)/keys
	@mkdir -p $(INIT_PREFIX)
	@mkdir -p $(SYSTEMD_PREFIX)
	@install -m644 pkg/keyless_cacert.pem $(CONFIG_PREFIX)/keyless_cacert.pem
	@install -m755 pkg/gokeyless.sysv $(INIT_PREFIX)/gokeyless
	@install -m755 pkg/gokeyless.service $(SYSTEMD_PREFIX)/gokeyless.service
	@install -m600 pkg/gokeyless.yaml $(CONFIG_PREFIX)/gokeyless.yaml

$(TRIS):
	@mkdir -p $(TRIS_DIR)
	@wget -nc -P $(TRIS_DIR) -q $(TRIS_URL)
	@unzip -d $(TRIS_DIR) -q $(TRIS_DIR)/$(TRIS_REV).zip
	@mv $(TRIS_DIR)/tls-tris-$(TRIS_REV)/* $(TRIS_DIR)
	@mv $(TRIS_DIR)/tls-tris-$(TRIS_REV)/.[!.]* $(TRIS_DIR)
	@rmdir $(TRIS_DIR)/tls-tris-$(TRIS_REV)
	@rm $(TRIS_DIR)/$(TRIS_REV).zip
	@make -C $(TRIS_DIR) -f _dev/Makefile $@

$(INSTALL_BIN)/$(NAME): $(TRIS) | install-config
	@GOOS=$(OS) GOARCH=$(ARCH) $(GO_TRIS) build -ldflags $(LDFLAGS) -o $@ ./cmd/$(NAME)/...

.PHONY: clean
clean:
	@$(RM) -r $(DESTDIR)
	@$(RM) -r $(TRIS_DIR)
	@$(RM) $(DEB_PACKAGE)
	@$(RM) $(RPM_PACKAGE)

FPM = fpm -C $(DESTDIR) \
	-n $(NAME) \
	-a $(ARCH) \
	-s dir \
	-v $(VERSION) \
	--url $(URL) \
	--description $(DESCRIPTION) \
	--vendor $(VENDOR) \
	--license $(LICENSE) \

$(DEB_PACKAGE): | $(INSTALL_BIN)/$(NAME) install-config
	@$(FPM) \
	-t deb \
	-d libltdl7 \
	--before-install pkg/debian/before-install.sh \
	--before-remove pkg/debian/before-remove.sh \
	--after-install pkg/debian/after-install.sh \
	--config-files /$(CONFIG_PATH)/gokeyless.yaml \
	--deb-compression bzip2 \
	--deb-user root --deb-group root \
	.

$(RPM_PACKAGE): | $(INSTALL_BIN)/$(NAME) install-config
	@$(FPM) \
	-t rpm \
	-d libtool-ltdl \
	--rpm-os linux \
	--before-install pkg/centos/before-install.sh \
	--before-remove pkg/centos/before-remove.sh \
	--after-install pkg/centos/after-install.sh \
	--config-files /$(CONFIG_PATH)/gokeyless.yaml \
	--rpm-use-file-permissions \
	--rpm-user root --rpm-group root \
	.

.PHONY: dev
dev: gokeyless
gokeyless: $(shell find . -path $(TRIS_DIR) -prune -o -type f -name '*.go') $(TRIS)
	$(GO_TRIS) build -ldflags "-X main.version=dev" -o $@ ./cmd/gokeyless/...

.PHONY: vet
vet:
	$(GO) vet `$(GO) list ./... | grep -v /vendor/`

.PHONY: lint
lint:
	for i in `$(GO) list ./... | grep -v /vendor/`; do golint $$i; done

.PHONY: test
test: $(TRIS)
	GODEBUG=cgocheck=2 $(GO_TRIS) test -v -cover -race `$(GO) list ./... | grep -v /vendor/`
	GODEBUG=cgocheck=2 $(GO_TRIS) test -v -cover -race ./tests -args -softhsm2

.PHONY: test-nohsm
test-nohsm: $(TRIS)
	GODEBUG=cgocheck=2 $(GO_TRIS) test -v -cover -race `$(GO) list ./... | grep -v /vendor/`

.PHONY: benchmark-softhsm
benchmark-softhsm: $(TRIS)
	$(GO_TRIS) test -v -race ./server -bench HSM -args -softhsm2
