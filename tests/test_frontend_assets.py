ROOT_ASSETS = {
    "/favicon.ico": "image/x-icon",
    "/favicon-32x32.png": "image/png",
    "/apple-touch-icon.png": "image/png",
    "/icon-192.png": "image/png",
    "/icon-512.png": "image/png",
    "/logo.png": "image/png",
    "/site.webmanifest": "application/manifest+json",
}


def _content_type(response):
    return response.headers["content-type"].split(";")[0]


def _is_html_fallback(response):
    return response.content.lstrip().lower().startswith(b"<!doctype html")


def test_frontend_root_assets_are_served_with_expected_content_types(client):
    for path, expected_content_type in ROOT_ASSETS.items():
        response = client.get(path)

        assert response.status_code == 200
        assert _content_type(response) == expected_content_type
        assert not _is_html_fallback(response)


def test_manifest_references_ytnd_icons(client):
    response = client.get("/site.webmanifest")

    assert response.status_code == 200
    manifest = response.json()
    assert manifest["name"] == "YTND Manager"
    assert manifest["short_name"] == "YTND"
    assert manifest["id"] == "/"
    assert manifest["scope"] == "/"
    assert manifest["start_url"] == "/"
    assert manifest["theme_color"] == "#08111F"
    assert manifest["background_color"] == "#08111F"

    icons = manifest["icons"]
    icon_sources = {icon["src"] for icon in icons}
    assert icon_sources == {"/icon-192.png", "/icon-512.png"}
    assert all(icon["type"] == "image/png" for icon in icons)
    assert all("maskable" in icon["purpose"] for icon in icons)
    assert all("vite" not in icon["src"].lower() for icon in icons)

    for icon_src in icon_sources:
        icon_response = client.get(icon_src)

        assert icon_response.status_code == 200
        assert _content_type(icon_response) == "image/png"
        assert not _is_html_fallback(icon_response)


def test_legacy_vite_icon_route_serves_ytnd_png(client):
    response = client.get("/vite.svg")

    assert response.status_code == 200
    assert _content_type(response) == "image/png"
    assert b"<svg" not in response.content[:200].lower()
    assert not _is_html_fallback(response)
