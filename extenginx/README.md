# Flexible NGINX container for http and mail with SSL

This container offers an nginx server on alpine
with a suitable base configuration that is easy to extend.

Bring your own keys for SSL, they are mounted at runtime so
that another container or the host can refresh them,
and tell nginx to reload with no downtime.

For development purposes, you can generate dh params,
and a self signed cert with `create_dev_keys.sh`.

This container and its nginx config are designed around
composing small config snippets to build a full configuration,
and it can even be built with support for mounting the inclusion
directory at runtime so that the snippets can be changed and
hot reloaded for a fast development cycle with no downtime.

The `include.d` directory and its subrdirectories are a template
for what is possible with the configuration snippets and the `README.md`
files contained within offer suggestions about what types of
configuration belong in which subdirectory.

The provided compose files offer examples of how to build
this container. `container-compose-dev.yml` is suitable
for development and uses custom ports > 1024 so it can be run
as an unpriveleged user on a dev machine. Runtime snippets
are enabled so that the contents of `include.d` can be changed
on the fly to quickly iterate. Upon changing them, simply
exec `sh -c 'nginx -t && nginx -s reload'` within the container
to check syntax and apply the changes if they are acceptable.

The `container-compose.yml` file is a suitable base
for a production deployment. Runtime snippets are disabled,
and the default priveled ports are used. Snippets should
either be added to the `include.d` folder in this repository,
or the path should be changed (e.g. to a folder in a parent
directory if this repo is a submodule).

This container does almost nothing out of the box (since it
is designed to be a base for further development), but if you
want to verify it is working correctly before making any
of your own additions, it behaves as follows:
- http requests to the non ssl port return a 301 redirect
to the same path at https on the ssl port
- https GET requests to the empty path or `/` return a generic
nginx welcome page.
- non GET https requests on the empty path or `/` return a 405 error
- https requests to all other paths return a 404 error
- pop or smtp connections over ssl can progress through login, but
will recieve an internal server error after sending a password,
because no authentication backend is configured by default.
