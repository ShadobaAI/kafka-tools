# 1C CI images v2

Build local Docker images for 1C CI tools from already downloaded distributions.

- `edtcli`: EDT CLI only, with system Java Runtime 17.
- `ibcmd`: 1C server tools plus OScript and Vanessa Runner.
- `client`: 1C client plus OScript and Vanessa Runner; developer license files are mounted at runtime.

The Docker build does not download 1C distributions. Put required files into `distr` before building.
The EDT image removes bundled platform support versions below the version passed with `--edt-platform-support`.

## Distributions

Expected files in `tools/docker-image-v2/distr`:

- EDT: `1c_edt_distr_offline_<edt-version>_<build>_linux_x86_64.tar.gz`
- 1C server tools: `deb64_<platform-version-with-underscores>_<build>.zip`
- 1C client: `client_<platform-version-with-underscores>_<build>.deb64.zip`
- OScript for `ibcmd` and `client`: `OneScript-<version>-linux-x64.zip`

Download examples:

```bash
python scripts/download_distribution.py edt 2025.2.6 ./distr
python scripts/download_distribution.py platform-server 8.3.27 ./distr
python scripts/download_distribution.py platform-client 8.3.27 ./distr
```

Use `ONEC_USERNAME` and `ONEC_PASSWORD` for `releases.1c.ru` when the downloader needs authentication. Do not pass these credentials into Docker build args.

## Local build

Install Python dependency:

```bash
python -m pip install pyyaml
```

Build images:

```bash
python scripts/build_image.py edtcli:2025.2.6 --edt-platform-support 8.3.27 --progress plain
python scripts/build_image.py ibcmd:8.3.27 --progress plain
python scripts/build_image.py client:8.3.27 --progress plain
```

Local tags:

- `edtcli:latest`
- `ibcmd:latest`
- `client:latest`

`scripts/build_image.py` stages only the matching archive into `.build-context` and passes it as a named BuildKit context. Distribution archives are mounted into install stages and are not copied into final image layers.

## Runtime License

The `client` image keeps license files outside the image:

- `/var/1C/licenses`
- `/home/usr1cv8/.1cv8`

Use one persistent Docker volume or one stable host path for these directories. Developer license activation uses `developer.1c.ru` credentials at runtime, not during image build.

## Publishing

Remote image names are resolved from `images.yml`:

- `ghcr.io/<org>/edtcli:latest`
- `ghcr.io/<org>/ibcmd:latest`
- `ghcr.io/<org>/client:latest`

Override registry when needed:

```bash
python scripts/build_image.py edtcli:2025.2.6 --edt-platform-support 8.3.27 --registry ghcr.io/<owner> --push
```

After a successful push, delete old GHCR package versions:

```bash
GITHUB_TOKEN=<token> python scripts/cleanup_ghcr.py --image ghcr.io/<org>/edtcli:latest
```
