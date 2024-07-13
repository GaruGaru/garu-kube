.PHONY: test lint

test: lint
	cd gitops/overlays/garu-home && kustomize build . > /dev/null

lint:
	 yamllint -c .yamllint.yml gitops/
