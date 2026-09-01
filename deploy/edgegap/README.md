# Edgegap deployment

This image runs one Not Enough Hands room. The Godot ENet server listens on
the App Version's internal UDP port (normally `7777`), while Edgegap assigns a
random public external port for players.

## 1. Export the Linux dedicated server

From the project root, using Godot 4.7.1 Mono with export templates installed:

On this development machine, run this as one PowerShell line from the project
root (do not add backslashes before underscores):

```powershell
& "C:\Users\dorry\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --headless --path . --export-release "Linux Dedicated Server"
```

If Godot is moved later, replace only the quoted executable path with its real
location. `C:\path\to\...` is a placeholder, not a literal command.

The preset writes the server and its support files to `build/server/`.

## 2. Build and test the image

Install Docker Desktop and make sure Linux containers are enabled, then run:

```powershell
docker build --platform linux/amd64 `
  -f deploy/edgegap/Dockerfile `
  -t not-enough-hands-server:0.1.1 .

docker run --rm -p 7777:7777/udp not-enough-hands-server:0.1.1
```

Never reuse `latest` for an Edgegap release. Give every uploaded image a new
immutable tag such as `0.1.0`, `0.1.1`, or a commit identifier.

**Test as the unprivileged user, never with `--user 0:0`.** Edgegap honours the
`USER 10001` line in the Dockerfile, so a permission problem that root hides
will still crash the real deployment. `HOME` is `/app`, and Godot aborts with
`SIGSEGV` (exit 139) if it cannot create its user data dir there — this is why
the Dockerfile chowns `/app` itself and not just the files copied into it.

Godot block-buffers stdout when it has no TTY, which used to leave `docker logs`
empty even on a healthy server — and, worse, threw away the last few kilobytes of
a server that *crashed*, so an Edgegap "exit code 139" arrived with nothing to
read. The ENTRYPOINT now goes through `stdbuf -oL -eL`, so `NETWORK_SERVER_READY
port=7777`, every GDScript error and any crash backtrace reach the Logs tab as
they happen. **When a deployment crashes, read the Logs tab first** — that output
is the only account of why.

You can still confirm the socket directly — ENet binds dual-stack, so the entry
is in `udp6`, not `udp` (`7777` is hex `1E61`):

```powershell
docker exec <container> sh -c "grep -i :1E61 /proc/net/udp6"
```

## 3. Push to Edgegap Container Registry

In the Edgegap dashboard, open **Tools > Container Registry**, request
credentials, and use the exact URL/project/username shown there. Do not put the
registry token in this repository.

The project name is *not* the organization name. Edgegap runs Harbor, whose
robot accounts are named `robot$<project>+<robot>` — the separator is `+`, so
the robot `robot$redrat-a7im5xwhgsdo+client-push` belongs to the project
`redrat-a7im5xwhgsdo`. Pushing to the wrong project fails with a misleading
`401 Unauthorized` rather than a not-found error.

```powershell
docker login registry.edgegap.com
docker tag not-enough-hands-server:0.1.1 `
  registry.edgegap.com/redrat-a7im5xwhgsdo/not-enough-hands-server:0.1.1
docker push registry.edgegap.com/redrat-a7im5xwhgsdo/not-enough-hands-server:0.1.1
```

## 4. Create the Edgegap App Version

Create an Application and a Version in the dashboard with:

- image repository/tag matching the pushed image;
- architecture `linux/amd64`;
- one port named `gameport`;
- internal port `7777`;
- protocol `UDP`;
- TLS upgrade disabled;
- port verification disabled initially (ENet is not an HTTP health endpoint);
- command and arguments left empty so the Docker defaults are used;
- the same robot username and token, since the registry is private.

Start with at least 512 vCPU units and 1024 MiB memory, then measure a real
four-player Villa session and tune those values.

## 5. Let players join

Create a deployment from that App Version. Once its status is `READY`, copy the
deployment's FQDN/public IP and the `gameport` external port. The external port
is intentionally random and is not usually `7777`.

Each player opens the normal Windows build, enters that FQDN/IP and external
port on the multiplayer menu, then joins the lobby. The first player connected
to a dedicated deployment becomes the lobby host; everyone presses Ready and
that host starts the Villa.

For a production **Create Room** button, call Edgegap's deployment API from a
small trusted backend, wait for `READY`, and return only the FQDN and external
port to the Godot client. Never ship an Edgegap API token inside the game.
