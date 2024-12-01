repo = https://github.com/nanomq/nanomq.git
yaml = snap/snapcraft.yaml
arch = $(shell dpkg --print-architecture)
version = $(shell yq e '.version' snap/snapcraft.yaml)
local = nanomq/$(version)

init-snap-env:
	snap login
	snap install snapcraft --classic
	snapcraft login

local-source:
	sed -i 's/\s*$$//g' $(yaml)
	yq -i '.parts.nanomq.source="$(local)"' $(yaml)
	yq -i 'del(.parts.nanomq.source-tag)' $(yaml)
	(cd "$(local)" && git pull) || git clone --recursive $(repo) --branch $(version) --single-branch "$(local)" 2> /dev/null

remote-source:
	sed -i 's/\s*$$//g' $(yaml)
	yq -i '.parts.nanomq.source="$(repo)"' $(yaml)
	yq -i '.parts.nanomq.source-tag="$$SNAPCRAFT_PROJECT_VERSION"' $(yaml)

build-local: local-source
	snapcraft --debug --verbosity debug

build-remote: remote-source
	snapcraft --debug --verbosity debug

install:
	snap install nanomq_$(version)_$(arch).snap --devmode

uninstall: 
	snap remove --purge nanomq

enter-shell:
	snap run --shell nanomq

clean-build:
	snapcraft clean

clean-local: remote-source uninstall clean-build
	rm -rf "$(local)/../"*
	rm -f *.snap

