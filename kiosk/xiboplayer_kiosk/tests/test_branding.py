from xiboplayer_kiosk import branding


def test_brand_colors_unchanged():
    assert branding.BRAND_XIBO_COLOR == "#0097D8"
    assert branding.BRAND_PLAYER_COLOR == "#FFFFFF"


def test_heading_contains_both_colors():
    assert "#0097D8" in branding.BRAND_HEADING_MARKUP
    assert "#FFFFFF" in branding.BRAND_HEADING_MARKUP
    assert "xibo" in branding.BRAND_HEADING_MARKUP
    assert "player" in branding.BRAND_HEADING_MARKUP


def test_branded_heading_adds_subtitle():
    out = branding.branded_heading("First boot setup")
    assert "First boot setup" in out
    assert "size=\"small\"" in out


def test_branded_heading_no_subtitle():
    out = branding.branded_heading("")
    assert "size=\"small\"" not in out
