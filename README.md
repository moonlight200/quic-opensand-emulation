# Opensand Measurement Testbed

These scripts can be used to automate measurements of different protocols on the
[OpenSAND](https://opensand.org/content/home.php) satellite emulation platform.
Each emulation (one execution of the `opensand.sh` script) consist of multiple
scenarios that are tested, each of which has a different configuration (such as
the orbit of the emulated satellite). Within a single scenario multiple measurements
are executed to measure the performance of different protocols. Each measurement is
executed multiple times with each execution being called a run. This will generate
more statistically stable results.

### Measured performance values

While the complete output of each component taking part in a measurement is captured,
the runs aim to measure the following set of performance values:

* Goodput Evolution
* Congestion Window Evolution
* Connection Establishment Time
* Time to First Byte

### Script structure

The main executable script is `opensand.sh` it will source all other scripts before
starting the measurements. Some scripts (such as `setup.sh` and `teardown.sh`) can
also be executed individually for e.g. manual measurements.

* `opensand.sh` - Main executable
* `env.sh` - Environment configuration
* `setup*.sh` - Environment creation and setup
* `teardown*.sh` - Environment disassembly
* `run*.sh` - Execution of the individual measurement runs
* `stats.sh` - System statistics collection during the emulation

# Installation

1. Ensure the requirements below are met
2. Copy all files (including subdirectories) to the machine that will run the emulation
3. Update configuration in `env.sh`, especially the file and directory paths

### Requirements

These programs need to be cloned and built

* [qperf](https://gitlab.lrz.de/kosekmike/qperf)
* [pepsal](https://github.com/danielinux/pepsal)

The following utilities need to be installed on the system:

* [opensand](https://opensand.org/content/get.php) (which installs `opensand-core`, `opensand-network` and `opensand-daemon`)  
  Not required are `opensand-collector` and `opensand-manager`
* iperf3
* tmux
* curl
* nginx (deamon can be disabled, is only used standalone)

# Usage

Executing the main script `opensand.sh` will start the automated emulation. As this
will take some time, it is recommended to start the script in a tmux session.
```bash
tmux new-session
./opensand.sh
```
This allows to detach from the process and re-attach at any time later.

The results of an emulation can be found in a subdirectory of the configured
`RESULTS_DIR` (set in `env.sh`), along with the emulation log file. To simplify
downloading the results, the symlink `latest` in `RESULTS_DIR` is updated to the
latest emulation output directory. When downloading the results, it is
recommended to use `rsync` over `scp` since the output consists of many small
files.

The script can be interrupted at any point, which will stop the current emulation
and cleanup the environment.

## Parameters

### General parameters 

| Name | Argument | Description |
| ---- | -------- | --- |
| `-f` | `<file>` | Read the scenario configuration from the file instead of the commandline arguments |
| `-h` |          | Print a help message and exit |
| `-s` |          | Show the system statistics also in the log printed to stdout |
| `-t` | `<tag>`  | A tag to append to the output directory name, used for easier identification |
| `-v` |          | Print version and exit |

### Scenario configuration

These parameters configure the scenarios that are executed. All combinations of
all configured values are executed. The time parameters (N,P,T) and measurement
control parameters (V,W,X,Y,Z) apply to all scenarios.

E.g. if orbits `-O GEO,MEO`, congestion controls
`-C rrrr,cccc` and goodput measurements `-N 5` are configured, four different scenarios are executed.

| Name | Argument   | Default | Description |
| ---- | ---------- | --- | --- |
| `-A` | `<#,>`     | Comma separated list of attenuation values to measure | `0` |
| `-B` | `<GT,>*`   | Comma separated list of two qperf transfer buffer sizes for gateway and terminal. Repeat parameter for multiple configurations | `1M,1M` |
| `-C` | `<SGTC,>`  | Comma separated list of four congestion control algorithms for server, gateway, terminal and client. (c = cubic, r = reno) | `rrrr` |
| `-N` | `#`        | Number of runs per goodput measurement in a scenario | `1` |
| `-O` | `<#,>`     | Comma separated list of orbits to measure (GEO,MEO,LEO) | `GEO` |
| `-P` | `#`        | Number of seconds to prime a new environment with some pings | `5` |
| `-Q` | `<SGTC,>*` | Comma separated list of four qperf quicly buffer sizes at server, gateway, terminal and client. Repeat parameter for multiple configurations | `1M,1M,1M,1M` |
| `-T` | `#`        | Number of runs per timing measurement in a scenario | `4` |
| `-U` | `<SGTC,>*` | Comma separated list of four qperf udp buffer sizes at server, gateway, terminal and client. Repeat parameter for multiple configurations | `1M,1M,1M,1M` |
| `-V` |            | Disable plain (non pep) measurements | |
| `-W` |            | Disable pep measurements | |
| `-X` |            | Disable ping measurements | |
| `-Y` |            | Disable quic measurements | |
| `-Z` |            | Disable tcp measurements | |

The command line arguments are used to generate a temporary scenario configuration
file in the emulations temporary directory (`/tmp/opensand.*/`).

## Scenario file format

The scenario file allows a much more fine-grained control over the individual
scenarios that are executed. While in the example for the command line arguments
all four combinations of orbits and congestion control algorithms form the four
scenarios, the scenario file allows executing only some of them.

Each line in the file describes a single scenario. Blank lines and lines starting
with `#` are ignored. For each scenario the exact same arguments and syntax are
used as for the scenario configuration command line arguments with the exception,
that only a single scenario must be described. Repeatable arguments must only be
given once. Arguments that define different configuration values via comma separated
lists must only have a single value.

### Example file

```
# Example scenario configuration

-N 5 -O GEO -C rrrr -Q 1M,2M,3M,4M
-N 3 -O MEO -C cccc -Q 1M,2M,3M,4M
-O GEO -C cccc -Q 1M,2M,3M,4M
```
This file describes three scenarios with varying orbits, congestion control algorithms
and goodput measurement runs. All parameters that are not given use the default value,
thus the last scenario would be executed with one run per goodput measurement.