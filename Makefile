.PHONY: build

all    :  build
build  :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=1000000 dapp --use solc:0.8.13 build
clean  :; dapp clean
test   :  build
	./test.sh $(match)
deploy :; dapp create CurveLPOracle
