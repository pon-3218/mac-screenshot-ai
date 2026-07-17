.PHONY: build app verify release-local release-notarized clean

build:
	swift build

app:
	./scripts/build-app.sh

verify: app
	./scripts/verify-app.sh

release-local:
	./scripts/release.sh local

release-notarized:
	./scripts/release.sh notarized

clean:
	swift package clean
