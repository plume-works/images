# /var/lib/docker is a declared volume

`core` declares `VOLUME /var/lib/docker`, as the official Docker-in-Docker image
does, so the nested daemon's data is never on the container's overlay
filesystem. Every container gets an anonymous volume there, whether or not it
starts Docker.

Not chosen:

- Measuring first whether the volume is needed.
- Only documenting that each image should mount one.
