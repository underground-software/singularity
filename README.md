# singularity

We have crossed the event horizon

## Recommended Setup Instructions

0. Make sure you have `podman`, `python3`, `pip`, and `git` installed on your host machine
1. Clone the syzygy repo and its submodules
```
git clone --recurse-submodules https://github.com/underground-software/syzygy.git
```
2. Clone the kdlp podman-compose repo
```
git clone https://github.com/underground-software/podman-compose.git
```
3. Set up a python virtual environment
- Whenever you use `podman-compose.py`, make sure you use the `kdlp-venv` you set up! (run the `source` command listed below)
```
python3 -m venv kdlp-venv
source kdlp-venv/bin/activate
```
4. `cd` into podman-compose and switch to the kdlp-devel branch (we use our own podman-compose fork)
```
cd podman-compose
git checkout origin/devel-kdlp
```
5. Install podman-compose's requirements
```
pip install -r requirements.txt
```
6. Go into `syzygy`, make the `email` directory and its subdirectories
```
cd ../syzygy
mkdir -p email/{logs,mail}
```
7. Run the ssl setup script found in extenginx
- Make sure you run it from within the syzygy directory!
- If you get the error `extenginx/create_dev_keys.sh: 2: set: Illegal_option -o pipefail`, edit the `create_dev_keys.sh` script and comment out the line `set -uexo pipefail`
```
extenginx/create_dev_keys.sh
```
8. Compose using the kdlp podman-compose branch and the container-compose-dev.yml file
```
../podman-compose/podman_compose.py -f container-compose-dev.yml build
../podman-compose/podman_compose.py -f container-compose-dev.yml up
```
9. Access your local version of kdlp.underground.software
- open web browser
- go to https://localhost:1443
- accept the warning your browser probably gives you about the security certificate

You should now have a working, local version of the kdlp site!
To compose down, use
```
../podman-compose/podman_compose.py -f container-compose-dev.yml down -t0
```
