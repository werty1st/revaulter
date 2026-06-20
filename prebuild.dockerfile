# Stage 1: Build the Svelte frontend
FROM node:22-alpine AS frontend
WORKDIR /app/client/web
RUN corepack enable && corepack prepare pnpm@10.30.1 --activate
COPY client/web/package.json client/web/pnpm-lock.yaml client/web/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY client/web/ ./
RUN pnpm run build

# Stage 2: Build the Go binaries
FROM golang:1.26-alpine AS builder
ARG TARGETARCH=amd64
WORKDIR /app
ENV GOEXPERIMENT=jsonv2
ENV CGO_ENABLED=0
ENV GOOS=linux

COPY go.mod go.sum go.work go.work.sum ./
RUN go mod download

COPY . .
COPY --from=frontend /app/client/web/dist ./client/web/dist

RUN GOARCH=${TARGETARCH} go build -trimpath -o .bin/linux-${TARGETARCH}/revaulter ./cmd/revaulter && \
    GOARCH=${TARGETARCH} go build -trimpath -o .bin/linux-${TARGETARCH}/revaulter-cli ./cmd/cli

# Export stage: only the built binaries
FROM scratch
ARG TARGETARCH=amd64
COPY --from=builder /app/.bin/linux-${TARGETARCH}/ /
