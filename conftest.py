def pytest_addoption(parser):
    parser.addoption("--image", default="ghcr.io/plume-works/core:edge")
    parser.addoption(
        "--inner-image",
        default="ghcr.io/plume-works/hello-world@sha256:1e4c05b897a751332ce85c7e9449da2d93514ea2dea6dbb0e2753c9e949b2bfa",
    )
