ARG PREBUILD_IMAGE=revaulter-prebuild
FROM ${PREBUILD_IMAGE} AS prebuild

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=prebuild /revaulter /bin
HEALTHCHECK CMD ["/bin/revaulter", "healthcheck"]
CMD ["/bin/revaulter"]
ENTRYPOINT ["/bin/revaulter"]
