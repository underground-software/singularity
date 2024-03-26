# submatrix

This repository implements a container to host a matrix server
running the synapse implementation that federates with a single
parent server.

The purpose of this container is to form a part of the syzygy/orbit
project to serve as the communication hub for instruction using KDLP
curriculum modules, such as the Introduction to Linux Kernel Development
college course.

Example setup:

```bash
podman build -f Containerfile -t submatrix
./create_dev_keys
podman run --name submatrix_1 -v ./ssl:/ssl:z -p 8448:8448 --replace submatrix:latest
# create a new user
podman exec -it submatrix_1 register_new_matrix_user -c /homeserver.yaml
```

You probably need to adjust the domain names and ssl cert paths in homeserver.yaml
