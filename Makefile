default: build

build:
	docker build -t image-builder-odroid-xu4 .

sd-image: build
	 docker run --rm --privileged -v //host_data:/workspace -v //boot:/boot -v //lib/modules:/lib/modules -e TRAVIS_TAG -e VERSION image-builder-odroid-xu4

shell: build
	 docker run -ti --privileged -v //host_data:/workspace -v //boot:/boot -v //lib/modules:/lib/modules -e TRAVIS_TAG -e VERSION image-builder-odroid-xu4 bash

vagrant:
	vagrant up

test:
	 VERSION=dirty  docker run --rm -ti --privileged -v //host_data:/workspace -v //boot:/boot -v //lib/modules:/lib/modules -e TRAVIS_TAG -e VERSION image-builder-odroid-xu4 bash -c "unzip /workspace/hypriotos-odroid-xu4-dirty.img.zip && rspec --format documentation --color /workspace/builder/test/*_spec.rb"

shellcheck: build
	VERSION=dirty docker run --rm -ti -v //host_data:/workspace image-builder-odroid-xu4 bash -c 'shellcheck /workspace/builder/*.sh /workspace/builder/files/etc/firstboot.d/*'

test-integration: test-integration-image test-integration-docker

test-integration-image:
	 docker run --rm -ti -v //host_data/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-image"

test-integration-docker:
	 docker run --rm -ti -v //host_data/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-docker"

tag:
	git tag ${TAG}
	git push origin ${TAG}
