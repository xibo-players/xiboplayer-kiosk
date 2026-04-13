from pathlib import Path

from xiboplayer_kiosk import preseed


def test_read_returns_empty_when_file_missing(tmp_path):
    assert preseed.read("xibo.cms_url", tmp_path / "nope") == ""


def test_read_extracts_value(tmp_path):
    p = tmp_path / "preseed.env"
    p.write_text(
        "xibo.cms_url=https://cms.example.com/\n"
        "xibo.cms_key=ABC123\n"
        "xibo.display_name=kiosk-01\n",
    )
    assert preseed.read("xibo.cms_url", p) == "https://cms.example.com/"
    assert preseed.read("xibo.cms_key", p) == "ABC123"


def test_read_returns_empty_for_absent_key(tmp_path):
    p = tmp_path / "preseed.env"
    p.write_text("xibo.foo=bar\n")
    assert preseed.read("xibo.missing", p) == ""


def test_read_never_evaluates_shell_metachars(tmp_path):
    # If we'd `source` the file, this would run `rm /tmp/bogus`. We don't.
    p = tmp_path / "preseed.env"
    p.write_text("xibo.evil=`rm /tmp/bogus`\n")
    assert preseed.read("xibo.evil", p) == "`rm /tmp/bogus`"


def test_read_all_skips_comments_and_blank(tmp_path):
    p = tmp_path / "preseed.env"
    p.write_text("# comment\n\nkey1=val1\nkey2=val2\n")
    assert preseed.read_all(p) == {"key1": "val1", "key2": "val2"}
