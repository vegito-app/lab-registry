# Vegito OCI Registry

Self-hosted OCI container registries for the Vegito development infrastructure.

This project deploys three independent [Docker Distribution](https://distribution.github.io/distribution/) registries using Docker Compose.

The registries provide persistent storage for public container images, private container images, and BuildKit remote caches.

## Architecture

The deployment consists of three registry instances:

| Service | Default host port | Purpose | Intended access |
|---|---|---|---|
| `registry-public` | `5000` | Public container images | Public pull, restricted push |
| `registry-private` | `5001` | Private container images | Restricted pull and push |
| `registry-cache` | `5002` | BuildKit registry cache | Restricted pull and push |

Each instance runs `registry:3` and maintains an independent storage directory.

```text
                       HTTPS
                         |
                    Caddy ingress
                         |
          +--------------+--------------+
          |              |              |
        Public         Private         Cache
          |              |              |
                    HTTP gateway
          |              |              |
          v              v              v
    registry-public registry-private registry-cache
        :5000          :5001          :5002
          |              |              |
          v              v              v
       data/public    data/private    data/cache
```

The registries themselves provide OCI storage and distribution.

TLS termination, public/private access policies, and network restrictions are handled by the surrounding infrastructure.

## Requirements

- Docker Engine
- Docker Compose
- GNU Make
- Persistent storage for registry data
- Optional: Caddy reverse proxy
- Optional: NAS storage mounted on the Docker host

## Quick start

Clone the repository:

```bash
git clone https://github.com/vegito-app/registry.git
cd registry
```

Start all registry instances:

```bash
make up
```

Check their status:

```bash
docker compose ps
```

Follow logs:

```bash
make logs-f
```

Stop the registries:

```bash
make down
```

The `make up` target creates the required local storage directories before starting the containers.

## Configuration

The deployment can be configured through environment variables.

### Network

| Variable | Default | Description |
|---|---|---|
| `REGISTRY_PUBLIC_HOST_PORT` | `0.0.0.0:5000` | Public registry host binding |
| `REGISTRY_PRIVATE_HOST_PORT` | `0.0.0.0:5001` | Private registry host binding |
| `REGISTRY_CACHE_HOST_PORT` | `0.0.0.0:5002` | Cache registry host binding |

For example:

```bash
export REGISTRY_PUBLIC_HOST_PORT=127.0.0.1:5000
export REGISTRY_PRIVATE_HOST_PORT=127.0.0.1:5001
export REGISTRY_CACHE_HOST_PORT=127.0.0.1:5002

make up
```

These variables control how the Docker host publishes the registry ports.

**Security:** The default configuration binds all three services to `0.0.0.0`. This does not implement access restrictions. Configure host firewall rules, trusted network bindings, or an appropriately secured reverse proxy before exposing the services.

### Storage

| Variable | Default | Description |
|---|---|---|
| `REGISTRY_PUBLIC_DATA` | `./.containers/registry/data/public` | Public registry storage |
| `REGISTRY_PRIVATE_DATA` | `./.containers/registry/data/private` | Private registry storage |
| `REGISTRY_CACHE_DATA` | `./.containers/registry/data/cache` | BuildKit cache storage |

Example:

```bash
export REGISTRY_PUBLIC_DATA=/mnt/registry_data/public
export REGISTRY_PRIVATE_DATA=/mnt/registry_data/private
export REGISTRY_CACHE_DATA=/mnt/registry_data/cache

make up
```

All storage directories are mounted into their respective containers at:

```text
/var/lib/registry
```

The Compose configuration uses bind mounts with:

```yaml
bind:
  create_host_path: false
```

Consequently, the directories must exist before the containers start.

The `make up` target creates the default local directories. When using custom storage paths, create and mount those directories beforehand.

## Persistent storage

Registry data is stored outside the container lifecycle.

Default directory layout:

```text
.containers/
└── registry/
    └── data/
        ├── public/
        ├── private/
        └── cache/
```

The directories can reside on local storage or on a filesystem mounted from a NAS.

For example:

```text
NAS / NFS
    |
    v
/mnt/registry_data
    ├── public
    ├── private
    └── cache
```

The project intentionally separates container configuration from storage provisioning.

This allows the same Compose deployment to be used with local disks, dedicated storage volumes, or externally mounted filesystems.

When using NFS, ensure that the mount is available before starting the registries.

Avoid starting the containers against an empty local directory when the intended remote filesystem is unavailable.

## Registry endpoints

When running with the default port mappings:

```bash
curl http://localhost:5000/v2/
curl http://localhost:5001/v2/
curl http://localhost:5002/v2/
```

A healthy unauthenticated registry normally returns:

```http
HTTP/1.1 200 OK
```

with an empty JSON object:

```json
{}
```

These HTTP endpoints are intended for local or trusted-network use.

Docker clients and BuildKit generally expect HTTPS unless explicitly configured otherwise.

## Reverse proxy integration

The Vegito infrastructure can expose the registries through Caddy using the following hostnames:

| Public hostname | Backend |
|---|---|
| `public.registry.vegito.app` | `registry-public:5000` |
| `private.registry.vegito.app` | `registry-private:5000` |
| `cache.registry.vegito.app` | `registry-cache:5000` |

The backend ports above refer to the internal container ports.

When accessing the registries through their published Docker host ports, use `5000`, `5001`, and `5002`, respectively.

### Intended access policy

| Registry | Anonymous pull | Restricted-network pull | Restricted-network push |
|---|---|---|---|
| Public | Allowed | Allowed | Allowed |
| Private | Denied | Allowed | Allowed |
| Cache | Denied | Allowed | Allowed |

These restrictions are **not implemented by this repository's Compose configuration**.

They must be enforced by the reverse proxy and network infrastructure.

Network-based authorization does not identify individual users. Additional authentication is recommended when multiple users or less-trusted clients can access the registries.

The reverse proxy must also prevent direct access to the registry backend ports from untrusted networks.

## Docker usage

### Push an image

Tag an existing image:

```bash
docker tag example:latest \
  public.registry.vegito.app/example:latest
```

Push it:

```bash
docker push public.registry.vegito.app/example:latest
```

### Pull an image

```bash
docker pull public.registry.vegito.app/example:latest
```

These examples assume that the HTTPS endpoint is reachable and that the client has the required permissions.

## BuildKit registry cache

The cache registry is intended for remote BuildKit cache imports and exports.

Example:

```bash
docker buildx build \
  --cache-from type=registry,ref=cache.registry.vegito.app/example/builder \
  --cache-to type=registry,ref=cache.registry.vegito.app/example/builder,mode=max \
  --tag public.registry.vegito.app/example:latest \
  --push \
  .
```

Using `mode=max` allows BuildKit to export intermediate build layers in addition to final-image layers.

This can improve cache reuse across builds and CI runners, but it can also increase storage consumption.

For multi-platform builds, use a Buildx builder configured with the required platforms.

Avoid concurrent cache exports to the same reference when independent builds may overwrite one another's cache metadata.

## Maintenance

### View logs

```bash
make logs
```

Follow logs:

```bash
make logs-f
```

### Restart services

```bash
docker compose restart
```

### Stop services

```bash
make down
```

Stopping containers does not remove the persistent registry data.

### Storage usage

Inspect the storage directories:

```bash
du -sh .containers/registry/data/*
```

Or inspect the external storage paths when custom locations are configured.

### Garbage collection

Docker Distribution stores image manifests and content-addressed blobs.

Over time, old blobs may remain after tags or manifests are replaced or deleted.

The deployment enables the registry deletion API:

```yaml
REGISTRY_STORAGE_DELETE_ENABLED: "true"
```

This setting does not automatically delete old cache data or perform garbage collection.

Garbage collection must be planned separately.

Run offline garbage collection only while writes to the affected registry storage are stopped, following the Docker Distribution maintenance procedure.

Do not manually delete individual files from the registry storage layout.

## Security considerations

This project intentionally keeps the registry containers lightweight.

Security controls are expected to be implemented by the deployment environment.

Recommended precautions:

- Terminate external connections using HTTPS.
- Restrict private and cache registries to trusted networks.
- Restrict write operations on the public registry.
- Prevent direct access to backend registry ports from untrusted networks.
- Consider authentication for publishing and administrative operations.
- Protect the underlying storage against unauthorized modification.
- Monitor storage consumption and filesystem availability.
- Keep Docker Distribution images updated.

**Important:** Private DNS resolution does not constitute network access control.

A service behind a publicly reachable ingress may still be accessible if an external client explicitly supplies the expected hostname.

## Project structure

```text
.
├── compose.yaml
├── Makefile
└── README.md
```

## License

MIT