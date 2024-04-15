# singularity

The singularity at the center of the KDLP infrastructure black hole.

Section 1: Podman Setup 
--

0. Make sure you have `podman`, `python3`, `pip`, `socat`, and `git` installed on your host machine.

0. Clone the KDLP podman-compose repo.
We maintain a fork of podman compose with fixes and support for features
in the container-compose spec that are not yet in upstream podman-compose.

    ```sh
    git clone https://github.com/underground-software/podman-compose.git
    ```

0. Checkout our branch with the fixes.

    ```sh
    git checkout origin/kdlp
    ```

0. Get the podman-compose depdencies. Here are two options.

    1. Set up a python virtual environment.

        - Create a new venv.

        ```sh
        python3 -m venv kdlp-venv
        source kdlp-venv/bin/activate
        ```

        - Install podman-compose's requirements.

        ```sh
        pip install -r requirements.txt
        ```

        - If you install depenencies this way, make sure the venv is active (via `source kdlp-venv/bin/activate`) whenever you use our `podman-compose.py` script

    1. Get the dependencies from you system package manager:
        - Install the podman-compose packaged by your distribution.
        - It should install the appropriate python dependencies as global python packages.
        - NOTE: Running `podman-compose` in your terminal will invoke
        the unpatched version installed by your system package manager
        which is not compatible with singularity.
        You must invoke our patched `podman_compose.py` script directly
        unless you create your own symlink or alias.

### NOTE: From this point on, whenever we say `podman-compose`, treat this as an invocation of our patched version as described above.

Section 2: Singularity Setup
--

0. Clone the singularity repo.

    ```sh
    git clone https://github.com/underground-software/singularity.git
    ```

0. Build the containers.

    ```sh
    podman-compose build
    ```

0. Launch singularity.

    ```sh
    podman-compose up
    ```

0. Open another terminal and run the tests. If you followed the directions, they should pass.

    ```sh
    ./test.sh
    ```

0. At this point, the application is listening on three unix sockets located in the `socks` ~~drawer~~ directory.

    tl;dr run `sudo ./dev_sockets.sh &` to bind the services to the normal TCP ports.

    The `./dev_sockets.sh` script will spawn three instances of [`socat`](https://linux.die.net/man/1/socat).
    Each instance proxies requests on a TCP port to a corresponding unix socket.
    When run without privileges, it will listen on ports above the default threshold of 1024
    (as configured in `/proc/sys/net/ipv4/ip_unprivileged_port_start`),
    i.e. `1443` for https, `1465` for smtps, and `1995` for pop3s.
    This is suitable for local testing however you must take care
    to specify the port and protocol in any URLs that access these services,
    e.g. `https://localhost:1443` to access the local website deployment in your browser.

    When run with privileges, `socat` will bind to the normal, privileged ports for each service,
    i.e. `443` for https, `465` for smtps, and `995` for pop3s
    [as specifed by the IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt).
            
    ### NOTE: Singularity uses self-signed certificates by default. Accept any warning you see about the security certificate.

0. Terminate the singularity containers when you are finished.

    ```
    podman-compose down
    ```

Section 3: Development Configuration for Live Editiing
--

By default, your edits to the web content in the repo are not reflected on the live website until you rebuild the container.
However, you can setup your local environment to enable immediate live editing of the website.

If you set the following environment variable and rebuild the containers, they support live editing.

```sh
export COMPOSE_FILE="container-compose.yml:container-compose-dev.yml"
```

For security reasons, be sure to `unset COMPOSE_FILE` before production deployment.

Section 4: Production Deployment
--

To publish an instance of singularity on the internet, you must configure the hostname.

```sh
export SINGULARITY_HOSTNAME=singularity.example.com
```

You may want to remove the "(in development)" label from the footer of the website.

```sh
export SINGUALRITY_DEPLOYMENT_STATUS=""
```
You can alternativelty set this to whatever text you'd like, e.g. "(in staging)".

For the simple case of a single instance deployment,
you can run `sudo ./dev_sockets.sh &` to directly map
the TCP ports on your host to this singulariy instance's unix sockets.

Alternatively, you could configure an existing reverse proxy on the host such as `nginx` to proxy requests from the host to this container.

You should obtain and deploy real SSL certificates.
The details of obtaining these certs are beyond the scope of these instructions.
We use
[letsencrypt's certbot](https://certbot.eff.org/).

To install your real certificates into an instance of singularity,
create a tarball containing the approriate `fullchain.pem` and `privkey.pem`,
and then run `podman volume import singularity_ssl-certs /path/to/tarball`
followed by `podman exec singularity_nginx_1 nginx -s reload`.
