#!/bin/bash

# osnd_teardown_namespaces()
# Remove all namespaces and the components within them.
function osnd_teardown_namespaces() {
	sudo ip netns del osnd-cl
	sudo ip netns del osnd-st
	sudo ip netns del osnd-emu
	sudo ip netns del osnd-sat
	sudo ip netns del osnd-gw
	sudo ip netns del osnd-sv
}

# If script is executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	osnd_teardown_namespaces "$@"
fi

