# The inner Docker engine is cleaned up daily, and each kind of leftover is configurable

The core systemd image removes, once a day, whatever its inner Docker engine has left unused for a week:
stopped containers, anonymous volumes, images and build cache. Named volumes are kept. Each kind has its own
age, and an image that builds on core systemd, or a user at run time, can change the age or turn it off.

## Considered Options

- Weekly removal of images and build cache only, never containers or volumes (the decision this replaces):
  stopped containers and their volumes pile up on an engine that runs many short-lived containers, and a stopped
  container keeps its image from ever being removed.
- Named volumes removed by default too: deletes a login or cache volume that sits unattached on purpose.
- One age for every kind: a consumer cannot keep stopped containers longer as a log while clearing images sooner.

## Consequences

- A stopped container is kept a week by default, so a short-lived container can be inspected after it ends.
- A user who keeps work in a stopped container or an anonymous volume loses it after a week, unless they change
  the setting.
