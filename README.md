# singularity

The singularity at the center of the KDLP infrastructure black hole.

Section 1: Podman Setup 
--
 - Unfortunately, this project uses features that have been merged into podman-compose but as of June 2024,
have not yet been made part of a tagged release, so the version of podman-compose provided by any distro
is unlikely to work.

 - Fortunately, as podman-compose is written in python, it is simple to just clone a newer version of the
source code and add a symlink to your path to run the newer version of the script. Python will find any
libraries needed to run the code from the system packages installed as dependencies of the system podman-compose
package.

 - Make sure you have `git`, `podman`, and `podman-compose` installed on your host machine.
On fedora these packages can be obtained by running `sudo dnf install -y git podman podman-compose`.

 - Clone the upstream podman-compose repo. We recommend creating folder `mkdir -p ~/.local/src/` where the repo
can be placed. The appropriate command is `git -C ~/.local/src clone https://github.com/containers/podman-compose.git`

 - Create a symlink in `~/.local/bin` named `podman-compose` which points to the `podman_compose.py` script in
the cloned repository. The appropriate command is `ln -s ../src/podman-compose/podman_compose.py ~/.local/bin/podman-compose`

 - Verify that `which podman-compose` outputs `~/.local/bin/podman-compose`. If it does not, you may need to refresh the cached
path for the program (for bash that is `hash podman-compose`), or potentially add `$HOME/.local/bin` to `$PATH` if it is
not already present. The exact details will vary depending on your shell and are outside the scope of this document.

Section 2: Singularity Setup
--

 - Clone the singularity repo: `git clone https://github.com/underground-software/singularity.git`.

 - Create an empty `docs` folder within the repository: `mkdir docs`.

 - Build the containers: `podman-compose build`.

 - Launch singularity: `podman-compose up -d`.

 - At this point, the application is listening on three unix sockets located in the `socks` ~~drawer~~ directory.

Section 3: Testing and basic functionality
--

 - In order to verify that singularity is behaving correctly, you should run the test suite.

 - You will need to install some host packages needed by the testing script: flake8, shellcheck, jq, and curl.
On fedora these packages can be obtained by running `sudo dnf install -y flake8 shellcheck jq curl`.

 - Now you can run `./test.sh && echo 'tests passed'`. If you followed the directions, the tests should pass.

 - You will not be able to access the services using a normal web browser or email client without one more step as the
services listening on unix sockets instead of TCP ports.

 - Fortunately, it is easy to proxy the relevant TCP ports to the unix sockets so that the services can be accessed.
You will need the host program socat. On fedora it can be obtained by running `sudo dnf install -y socat`.

 - Run `./dev_sockets.sh &` or `sudo ./dev_sockets.sh &` to spawn three instances of socat in the background.

 - Each socat instance will bind a specific TCP port and redirect connections to the unix socket for the corresponding service.

 - When run without root privileges they will use ports above the threshold restricted for system services
(as configured in `/proc/sys/net/ipv4/ip_unprivileged_port_start`, 1024 by default):

 - When run with root privileges it will use the traditional ports for the services
[as specified by the IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt).

 - The test script will have created a user named `resu` whose password is `ssap` that you can use for manual testing.

 - Try opening the website in your browser and/or the email services with your email client and/or the matrix server with your matrix client.

 - Since singularity can only create self signed certificates by itself, you may need to accept warnings about them before you can proceed.

 - Make sure to specify the protocol (https, smtps, pop3s) and port (443 or 1443, 465 or 1465, 995 or 1995) explicitly or your client may
try to use the wrong port or the unencrypted version of the protocol.

 - There is no web content by default so the homepage of the website will give a 404 error, however the links  to the course
services in the navigation bar should work once signed in.

 - Once finished:

    - Terminate the socat instances by bringing the script to the foreground `fg` and pressing `ctrl+c`

    - Terminate the singularity containers with `podman-compose down` when you are finished.

    - Clean up any volumes with changes made by the test script by pruning unused volumes `podman volume prune`

        - NOTE: if you have other dangling podman volumes that you do not want to lose,
        you can instead manually delete each of the volumes for this project using `podman volume rm`.

        - They can be found in the output of `podman volume ls`. This project's volume names all start with `singularity`.


Section 4: Adding web content
--

 - By default no static web content is included with the repo. It goes in the `docs` folder.

 - Markdown files with the `.md` extension will be converted to HTML automatically.

 - Other static content will be served as is (e.g. images, css, etc).

 - You can edit `index.md` in docs to set the homepage that shows up when you visit the website without specifying a path.

Section 5: Development Configuration for Live Editing
--

 - By default, your edits to the web content in the repo are not reflected on the live website until you rebuild the container.
However, you can setup your local environment to enable immediate live editing of the website content without needing to rebuild.

 - If you set the following environment variable and rebuild the containers, they will support live editing:
`export COMPOSE_FILE="container-compose.yml:container-compose-dev.yml"`

 - For security reasons, be sure to `unset COMPOSE_FILE` and rebuild before a production deployment.

Section 5: Production Deployment
--

 - To publish an instance of singularity on the internet, you must configure the hostname.
You may also want to remove or change the "(in development)" label from the footer of the website.

 - To do this, edit the `.env` file in the project directory, or make a copy of it and specify
that new file with `--env-file` when running podman-compose.

 - podman-compose currently does not properly override values specified in `.env` with the values
of the corresponding environment variables as required by the compose specification, however
we maintain our own fork of the project with a not yet merged pr applied to fix it. You can add 
[our repository](https://github.com/underground-software/podman-compose.git) as a remote in your
clone of `podman-compose` and check out the `kdlp` branch. You can then export values in your shell
(e.g. `export SINGULARITY_HOSTNAME=my.real.domain.name`) and the containers will pick them up instead
of the defaults in `.env`.

 - For the simple case of a single instance deployment,
you can run `sudo ./dev_sockets.sh &` to directly map
the TCP ports on your host to this singularity instance's unix sockets.

 - Alternatively, you could configure an existing reverse proxy on the host
such as `nginx` to proxy requests from the host ports to the unix sockets.

 - You should obtain and deploy real SSL certificates. We use
[letsencrypt's certbot](https://certbot.eff.org/), but the
details of obtaining certs are beyond the scope of these instructions.

 - To install your real certificates into an instance of singularity,
create a `.tar` file containing the appropriate `fullchain.pem` and `privkey.pem`,
and then run `podman volume import singularity_ssl-certs /path/to/tarball`
followed by `podman-compose exec nginx nginx -s reload`.
