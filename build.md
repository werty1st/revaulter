## Step 1 — build the prebuild image (compiles frontend + Go binaries):

```bash
# auto-detect (arm64 on your server, amd64 on x86)
docker build -f prebuild.dockerfile -t revaulter-prebuild .
```
For a specific arch:
```bash
# explicit cross-compile to amd64
docker build -f prebuild.dockerfile --build-arg GOARCH=amd64 -t revaulter-prebuild .
````

## Step 2 — build the final images (just copies the binary from the prebuild image):

```bash
docker build -t revaulter:latest .
docker build -f Dockerfile-cli -t revaulter-cli:latest .
````

Both Dockerfile and Dockerfile-cli pull from revaulter-prebuild by default via the PREBUILD_IMAGE arg. If you tagged the prebuild image differently, pass it explicitly:

```bash
docker build --build-arg PREBUILD_IMAGE=myrepo/revaulter-prebuild:tag -t revaulter:latest .
```

